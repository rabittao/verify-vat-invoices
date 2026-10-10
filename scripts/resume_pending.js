#!/usr/bin/env node
// Resume checked workspace invoices, using one background browser and one page.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const { loadEnvFile } = require('./verify_invoices_helpers');
const { verifySingleInvoice } = require('./verify_invoices');
const { TrafficGuard, isRateLimitText } = require('./traffic_guard');

function isPending(record, root) {
  return !record['结果截图'] || !fs.existsSync(path.resolve(root, record['结果截图']));
}

async function main() {
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
  const stop = () => {
    stopping = true;
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
    const manifest = JSON.parse(fs.readFileSync(path.join(root, '.核对工作/manifest.json'), 'utf8'));
    const pending = manifest.filter(r => isPending(r, root));
    fs.writeFileSync(path.join(folder, 'pending-input.json'), JSON.stringify(pending, null, 2));
    console.log(`共 ${manifest.length} 张；跳过 ${manifest.length - pending.length} 张；待处理 ${pending.length} 张。`);
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1600, height: 1500 } });
    const page = await context.newPage();
    const guard = new TrafficGuard();
    page.trafficGuard = guard;
    page.on('dialog', async dialog => {
      if (isRateLimitText(dialog.message())) guard.pendingDialog = dialog.message();
      await dialog.dismiss().catch(() => {});
    });
    const resultsPath = path.join(folder, 'results.json');
    const results = fs.existsSync(resultsPath) ? JSON.parse(fs.readFileSync(resultsPath, 'utf8')) : [];
    for (const r of pending) {
      if (stopping) break;
      const record = {
        source_pdf: r['PDF文件名'], page_number: r['页码'], invoice_number: r['发票号码'],
        invoice_date: r['开票日期'].replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3'),
        pretax_amount: r['金额'], total_amount: r['价税合计'], invoice_type: '电子发票（普通发票）',
      };
      console.log(`正在处理 ${record.source_pdf} 第${record.page_number}页 ${record.invoice_number}`);
      page.invoiceOcrAttempts = 0;
      let result;
      for (;;) {
        status({ state: 'running', invoice_number: record.invoice_number, page: record.page_number });
        try {
          result = await verifySingleInvoice(page, record, folder, Math.max(1, 3 - page.invoiceOcrAttempts));
          guard.cooldownCount = 0;
          break;
        } catch (error) {
          if (stopping) break;
          if (error.code !== 'PLATFORM_RATE_LIMIT') throw error;
          await page.screenshot({ path: path.join(folder, `${record.invoice_number}-rate-limit.png`), fullPage: true }).catch(() => {});
          results.push({ ...record, verification_status: 'rate_limited', verification_message: error.message, verified_at: new Date().toISOString() });
          fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
          status({ state: 'cooldown', invoice_number: record.invoice_number, reason: error.message });
          await guard.cooldown();
          if (stopping) break;
          // 冷却后在同一个标签页刷新，清除旧提示再继续；识别预算不重置。
          await page.reload({ waitUntil: 'networkidle', timeout: 60000 });
          if (page.invoiceOcrAttempts >= 3) {
            result = { invoice_key: record.invoice_number, verification_status: 'captcha_error',
              verification_message: '已用完3次识别预算；平台限流等待已完成', captcha_attempts: page.invoiceOcrAttempts };
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
        const checked = execFileSync(path.join(root, '.核对工作/.venv/bin/python'),
          [path.join(__dirname, 'archive_resume_result.py'), record.invoice_number, textPath, screenshotPath], { encoding: 'utf8' });
        result.archive_check = checked.trim();
        console.log(checked.trim());
      }
      results.push({ source_pdf: record.source_pdf, page_number: record.page_number, ...result });
      fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));
      console.log(`结果：${result.verification_status}`);
      if (['daily_limit_exceeded', 'website_system_error'].includes(result.verification_status)) {
        console.log('平台每日限制或系统异常，保留进度后停止。');
        status({ state: 'stopped', reason: result.verification_status });
        return;
      }
    }
    status({ state: stopping ? 'stopped' : 'finished' });
  } catch (error) {
    status({ state: stopping ? 'stopped' : 'error', reason: error.message });
    if (!stopping) throw error;
  } finally {
    if (browser) await browser.close().catch(() => {});
    fs.rmSync(pidPath, { force: true });
  }
}
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { isPending };
