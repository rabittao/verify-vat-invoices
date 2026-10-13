#!/usr/bin/env node
// Resume checked workspace invoices, using one background browser and one page.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const { RetryPlan } = require('./retry_plan');
const { loadEnvFile } = require('./verify_invoices_helpers');
const { verifySingleInvoice } = require('./verify_invoices');
const { TrafficGuard, isRateLimitText } = require('./traffic_guard');
const { EndpointCircuit, resolveInvoiceEndpoints } = require('./endpoint_circuit');
const { cleanupResumeImages } = require('./resume_image_retention');
const { VERIFY_URL } = require('./tax_site');
const { CaptchaNetworkRecovery } = require('./captcha_network_recovery');
const { reloadInvoicePage, isTransientNavigationError, navigationDeferred } = require('./navigation_recovery');

function isPending(record, root) {
  return !record['结果截图'] || !fs.existsSync(path.resolve(root, record['结果截图']));
}

function onlyInvoice(argv) {
  const value = argv.find(a => a.startsWith('--only-invoice='))?.slice('--only-invoice='.length);
  if (value !== undefined && !/^\d{20}$/.test(value)) throw new Error('--only-invoice 必须为20位票号');
  return value;
}

function retryScope(argv) {
  const pdf = argv.find(a => a.startsWith('--retry-pdf='))?.slice('--retry-pdf='.length);
  const pages = argv.find(a => a.startsWith('--retry-pages='))?.slice('--retry-pages='.length);
  if (!pdf && !pages) return () => false;
  const match = /^(\d+)-(\d+)$/.exec(pages || '');
  if (!pdf || path.basename(pdf) !== pdf || !match || Number(match[1]) < 1 || Number(match[1]) > Number(match[2])) {
    throw new Error('重新处理需指定 --retry-pdf=文件名.pdf 和 --retry-pages=起始页-结束页');
  }
  return row => row['PDF文件名'] === pdf && row['页码'] >= Number(match[1]) && row['页码'] <= Number(match[2]);
}

async function main() {
  const planFile = process.argv.slice(2).find(a => a.startsWith('--retry-plan='))?.slice('--retry-plan='.length);
  const plan = planFile ? new RetryPlan(path.resolve(planFile)) : null;
  const singleInvoice = onlyInvoice(process.argv.slice(2));
  const explicitlyRetry = retryScope(process.argv.slice(2));
  const completed = new Set(process.argv.slice(2).filter(a => a.startsWith('--completed-invoice=')).map(a => a.slice('--completed-invoice='.length)));
  if ([...completed].some(n => !/^\d{20}$/.test(n))) throw new Error('本轮已完成票号必须为20位数字');
  const root = path.resolve(__dirname, '../..');
  const folder = path.resolve(__dirname, '../output/resume');
  fs.mkdirSync(folder, { recursive: true });
  loadEnvFile(path.resolve(__dirname, '../.env'));
  if (!process.env.DEEPSEEK_API_KEY) throw new Error('DEEPSEEK_API_KEY not configured');
  const pidPath = path.join(folder, 'runner.pid');
  if (fs.existsSync(pidPath)) {
    const prior = Number(fs.readFileSync(pidPath, 'utf8'));
    let alive = false;
    if (Number.isInteger(prior) && prior > 0) {
      try { process.kill(prior, 0); alive = true; } catch (_) {}
    }
    if (alive) throw new Error(`已有运行实例 PID ${prior}，不重复启动。`);
  }
  const lock = fs.openSync(pidPath, 'w');
  fs.writeFileSync(lock, String(process.pid));
  fs.closeSync(lock);
  let browser;
  let stopping = false;
  const stopController = new AbortController();
  const stop = () => {
    stopping = true;
    stopController.abort();
    console.log('收到停止请求，保留结果并关闭后台浏览器。');
    if (browser) void browser.close();
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
  const statusPath = path.join(folder, 'run-status.json');
  function status(value) {
    fs.writeFileSync(statusPath, JSON.stringify({ pid: process.pid, updated_at: new Date().toISOString(), ...value }, null, 2));
  }
  try {
    // Fail before querying invoices if local archival dependencies are unavailable.
    const archivePython = path.join(root, '.核对工作/.venv/bin/python');
    const archiveScript = path.join(__dirname, 'archive_resume_result.py');
    execFileSync(archivePython, [archiveScript, '--check'], { encoding: 'utf8' });
    const recovered = JSON.parse(execFileSync(archivePython, [archiveScript, '--recover'], { encoding: 'utf8' }));
    const resultsPath = path.join(folder, 'results.json');
    const results = fs.existsSync(resultsPath) ? JSON.parse(fs.readFileSync(resultsPath, 'utf8')) : [];
    results.push(...recovered);
    fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
    const manifest = JSON.parse(fs.readFileSync(path.join(root, '.核对工作/manifest.json'), 'utf8'));
    const unresolved = manifest.filter(r => isPending(r, root));
    const pending = unresolved.filter(r => !completed.has(r['发票号码']) && (!plan || (plan.includes(r['发票号码']) && plan.used(r['发票号码']) < 3)) && (!singleInvoice || r['发票号码'] === singleInvoice)).sort((a, b) => Number(explicitlyRetry(b)) - Number(explicitlyRetry(a)));
    status({ state: 'starting', total: manifest.length, pending: pending.length });
    fs.writeFileSync(path.join(folder, 'pending-input.json'), JSON.stringify(pending, null, 2));
    console.log(`共 ${manifest.length} 张；已有截图跳过 ${manifest.length - unresolved.length} 张；${singleInvoice ? `单票验证 ${singleInvoice}；` : ''}本次待处理 ${pending.length} 张。`);
    browser = await chromium.launch({ headless: true });
    // 江苏 getVerifyCode 的 OPTIONS 对 HeadlessChrome 返回403；同版本普通UA实测200。
    // 只统一浏览器兼容标识，保留证书校验、CORS和原有节流。
    const context = await browser.newContext({ viewport: { width: 1600, height: 1500 },
      userAgent: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${browser.version()} Safari/537.36` });
    const page = await context.newPage();
    const guard = new TrafficGuard({ signal: stopController.signal });
    // 跨实例切换也从真实提交时间计时，避免立即再提交触发一分钟限制。
    for (const result of results) {
      for (const retry of result.captcha_retry_history || []) {
        const submitted = Date.parse(retry.submitted_at);
        if (Number.isFinite(submitted) && (guard.lastSubmit === null || submitted > guard.lastSubmit)) guard.lastSubmit = submitted;
      }
    }
    page.trafficGuard = guard;
    page.captchaNetwork = [];
    page.on('response', response => {
      const url=new URL(response.url());
      if(/getVerifyCode/.test(url.pathname))page.captchaNetwork.push({url:url.origin+url.pathname,status:response.status()});
    });
    page.on('requestfailed', request => {
      const url=new URL(request.url());
      if(/getVerifyCode/.test(url.pathname))page.captchaNetwork.push({url:url.origin+url.pathname,error:request.failure()?.errorText});
    });
    page.on('dialog', async dialog => {
      const evidence = { message: dialog.message(), type: dialog.type(), at: new Date().toISOString() };
      (page.verificationDialogs ||= []).push(evidence);
      fs.appendFileSync(path.join(folder, "native-dialogs.jsonl"), JSON.stringify(evidence) + "\n");
      if (isRateLimitText(evidence.message)) guard.pendingDialog = evidence.message;
      await dialog.accept().catch(() => {});
    });
    const circuit = new EndpointCircuit();
    results.forEach(result => circuit.noteResult(result));
    await page.goto(VERIFY_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const endpoints = await resolveInvoiceEndpoints(page, pending.map(r => ({ invoice_number: r['发票号码'] })));
    fs.writeFileSync(path.join(folder, 'endpoint-routing.json'), JSON.stringify(endpoints, null, 2));
    let deferred = 0;
    for (const r of pending) {
      if (stopping) break;
      const record = {
        source_pdf: r['PDF文件名'], page_number: r['页码'], invoice_number: r['发票号码'],
        invoice_date: r['开票日期'].replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3'),
        pretax_amount: r['金额'], total_amount: r['价税合计'], invoice_type: '电子发票（普通发票）',
      };
      console.log(`正在处理 ${record.source_pdf} 第${record.page_number}页 ${record.invoice_number}`);
      if (explicitlyRetry(r)) console.log(`按用户指定重新处理第${record.page_number}页，本票不因本轮其他票的接口拦截记录提前跳过。`);
      const blocked = explicitlyRetry(r) ? null : circuit.reason(endpoints[record.invoice_number]);
      if (blocked) {
        deferred++;
        status({ state: 'running', invoice_number: record.invoice_number, page: record.page_number, deferred,
          reason: `${blocked.host} 被拦截，继续其他接口的发票` });
        results.push({ ...record, verification_status: 'endpoint_deferred', failure_reason: 'verification_endpoint_blocked',
          verification_message: `${blocked.host} 已被拦截（${blocked.reason}），本轮暂缓，保留待处理状态`,
          submitted_attempts: 0, verified_at: new Date().toISOString() });
        fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
        console.log(`暂缓：${blocked.host} 已被拦截，继续下一张；未识别或提交新验证码。`);
        continue;
      }
      if (plan) plan.bind(page, record.invoice_number);
      else page.invoiceOcrAttempts = 0;
      let result;
      const captchaRecovery = new CaptchaNetworkRecovery(3);
      for (;;) {
        if (plan && page.invoiceOcrAttempts >= 3) {
          result = { invoice_key: record.invoice_number, verification_status: 'captcha_error',
            failure_reason: 'captcha_budget_exhausted', captcha_attempts: page.invoiceOcrAttempts, verified_at: new Date().toISOString() };
          break;
        }
        status({ state: 'running', invoice_number: record.invoice_number, page: record.page_number });
        try {
          result = await verifySingleInvoice(page, record, folder, Math.max(1, 3 - page.invoiceOcrAttempts));
          circuit.noteResult(result);
          if (result.failure_reason === 'modern_captcha_unavailable') {
            results.push({source_pdf:record.source_pdf,page_number:record.page_number,...result});
            fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
            status({state:'cooldown',invoice_number:record.invoice_number,page:record.page_number,
              reason:'验证码请求失败，准备刷新当前标签页',captcha_network_refreshes:captchaRecovery.refreshes});
            const action = await captchaRecovery.recover(page, guard, result);
            if (action === 'retry') continue;
            deferred++;
            break;
          }
          if (result.failure_reason === 'verification_endpoint_blocked') {
            deferred++;
            result.verification_status = 'endpoint_deferred';
            result.verification_message = '查验接口被拦截，保留待处理状态，本轮继续其他发票';
            break;
          }
          if (result.verification_status === 'request_error' && page.invoiceOcrAttempts < 3) {
            results.push({ source_pdf: record.source_pdf, page_number: record.page_number, ...result });
            fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
            status({ state: 'cooldown', invoice_number: record.invoice_number, reason: result.verification_message });
            await guard.cooldown('查验请求异常');
            if (stopping) break;
            if (!await reloadInvoicePage(page, guard)) {
              result = navigationDeferred(page, record); deferred++; break;
            }
            continue;
          }
          if (result.verification_status === 'captcha_selection_exhausted') {
            // 暂缓而非误报已用完3次，避免无有效候选时无限占据当前票。
            deferred++;
            result.verification_status = 'captcha_deferred';
            result.verification_message = '本轮40次筛选未取得足够有效候选，保留待处理状态，继续下一张';
            break;
          }
          guard.cooldownCount = 0;
          break;
        } catch (error) {
          if (stopping) break;
          if (isTransientNavigationError(error)) {
            page.reuseInvoicePage = false;
            result = navigationDeferred(page, record, error); deferred++; break;
          }
          if (error.code !== 'PLATFORM_RATE_LIMIT') throw error;
          await page.screenshot({ path: path.join(folder, `${record.invoice_number}-rate-limit.png`), fullPage: true }).catch(() => {});
          results.push({ ...record, verification_status: 'rate_limited', verification_message: error.message, verified_at: new Date().toISOString() });
          fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
          status({ state: 'cooldown', invoice_number: record.invoice_number, reason: error.message });
          await guard.cooldown();
          if (stopping) break;
          // 冷却后在同一个标签页刷新，清除旧提示再继续；识别预算不重置。
          if (!await reloadInvoicePage(page, guard)) {
            result = navigationDeferred(page, record); deferred++; break;
          }
          if (page.invoiceOcrAttempts >= 3) {
            result = { invoice_key: record.invoice_number, verification_status: 'captcha_error',
              verification_message: '已用完3次有效验证码预算；平台限流等待已完成', captcha_attempts: page.invoiceOcrAttempts };
            break;
          }
        }
      }
      if (stopping || !result) break;
      if (result.verification_status === 'success') {
        const textPath = path.join(folder, `${record.invoice_number}-platform.txt`);
        const screenshotPath = path.join(folder, `${record.invoice_number}-result.jpg`);
        const texts = await Promise.all(page.frames().map(frame => frame.locator('body').innerText().catch(() => '')));
        fs.writeFileSync(textPath, texts.join('\n'));
        await page.screenshot({ path: screenshotPath, fullPage: true, type: 'jpeg', quality: 95, animations: 'disabled' });
        fs.writeFileSync(path.join(folder, `${record.invoice_number}-success.json`), JSON.stringify(result, null, 2));
        const checked = execFileSync(path.join(root, '.核对工作/.venv/bin/python'),
          [path.join(__dirname, 'archive_resume_result.py'), record.invoice_number, textPath, screenshotPath], { encoding: 'utf8' });
        const archived = JSON.parse(checked);
        result.archive_check = archived.archive_check;
        result.archive_verified = archived.archive_verified;
        result.archived_screenshot = archived.result_screenshot;
        result.archive_sha256 = archived.archive_sha256;
        console.log(`归档回读通过：${archived.result_screenshot}；${archived.archive_check}`);
      }
      result.cumulative_captcha_attempts = page.invoiceOcrAttempts;
      results.push({ source_pdf: record.source_pdf, page_number: record.page_number, ...result });
      fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
      if (result.archive_verified) {
        const archivedRecords = JSON.parse(fs.readFileSync(path.join(root, '.核对工作/manifest.json'), 'utf8'));
        const cleaned = cleanupResumeImages({ folder, root, records: archivedRecords.filter(r => r['发票号码'] === record.invoice_number),
          results, protectedNumber: null, graceMs: 0 });
        console.log(`成功归档后清理 ${cleaned.deleted.length} 张临时图片，正式结果截图保留。`);
      }
      console.log(`结果：${result.verification_status}；原因：${result.failure_reason || result.verification_message || "无"}；实际提交：${result.submitted_attempts ?? "见重试记录"}`);
      if (['daily_limit_exceeded', 'website_system_error'].includes(result.verification_status)) {
        console.log('平台每日限制或系统异常，保留进度后停止。');
        status({ state: 'stopped', reason: result.verification_status });
        return;
      }
    }
    status({ state: stopping ? 'stopped' : 'finished', deferred, reason: deferred ? '暂缓的发票仍待处理，未标为查验成功' : undefined });
  } catch (error) {
    status({ state: stopping ? 'stopped' : 'error', reason: error.message });
    if (!stopping) throw error;
  } finally {
    if (browser) await browser.close().catch(() => {});
    fs.rmSync(pidPath, { force: true });
  }
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { isPending, retryScope, onlyInvoice };
