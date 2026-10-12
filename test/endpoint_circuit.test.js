const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { EndpointCircuit, resolveInvoiceEndpoints } = require('../scripts/endpoint_circuit');
const { submissionFailure } = require('../scripts/submission_trace');
const { TrafficGuard } = require('../scripts/traffic_guard');
const { retryScope, isPending, onlyInvoice } = require('../scripts/resume_pending');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

test('single invoice mode requires an exact invoice number', () => {
  assert.equal(onlyInvoice([]), undefined);
  assert.equal(onlyInvoice(['--only-invoice=12345678901234567890']), '12345678901234567890');
  assert.throws(() => onlyInvoice(['--only-invoice=']), /20位/);
  assert.throws(() => onlyInvoice(['--only-invoice=13-20']), /20位/);
});

test('explicit retry covers selected PDF pages but still skips existing result screenshots', () => {
  const scope = retryScope(['--retry-pdf=sample.pdf', '--retry-pages=13-20']);
  assert.equal(scope({ PDF文件名: 'sample.pdf', 页码: 13 }), true);
  assert.equal(scope({ PDF文件名: 'sample.pdf', 页码: 20 }), true);
  assert.equal(scope({ PDF文件名: 'another.pdf', 页码: 13 }), false);
  assert.equal(scope({ PDF文件名: 'sample.pdf', 页码: 21 }), false);
  assert.throws(() => retryScope(['--retry-pages=13-20']), /重新处理需指定/);
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'retry-scope-'));
  try {
    fs.writeFileSync(path.join(root, 'existing.jpg'), 'test');
    const row = { PDF文件名: 'sample.pdf', 页码: 20, 结果截图: 'existing.jpg' };
    assert.equal(scope(row), true);
    assert.equal(isPending(row, root), false);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test('ORB/403 defers only affected endpoint; captcha and transient failures do not block it', () => {
  const now = Date.now();
  const circuit = new EndpointCircuit({ now: () => now });
  const result = failure => ({ captcha_retry_history: [{ submission_trace: { requests: [{
    url: 'https://fpcy.zhejiang.chinatax.gov.cn/NWebQuery/vatQuery', sent_at: new Date(now).toISOString(), failure,
  }] } }] });
  circuit.noteResult(result('net::ERR_CONNECTION_FAILED'));
  assert.equal(circuit.reason('https://fpcy.zhejiang.chinatax.gov.cn:443/NWebQuery'), undefined);
  circuit.noteResult(result('net::ERR_BLOCKED_BY_ORB'));
  assert.ok(circuit.reason('https://fpcy.zhejiang.chinatax.gov.cn:443/NWebQuery'));
  assert.equal(circuit.reason('https://fpcy.jiangsu.chinatax.gov.cn:80/NWebQuery'), undefined);
  assert.equal(submissionFailure({ requests: [{ failure: 'net::ERR_BLOCKED_BY_ORB', response_status: null }] }), 'verification_endpoint_blocked');
  assert.equal(submissionFailure({ requests: [{ response_status: 403 }] }), 'verification_endpoint_blocked');
  const stale = new EndpointCircuit({ now: () => now + 31 * 60 * 1000 });
  stale.noteResult(result('net::ERR_BLOCKED_BY_ORB'));
  assert.equal(stale.blocked.size, 0); // 不把历史拦截永久缓存。
});

test('routing uses full invoice number through site function, never guesses regional prefixes', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent('<script>window.getSwjg=(number,flag)=>{if(number.length!==20||flag!==1)throw Error("incorrect arguments");return ["浙江","https://fpcy.zhejiang.chinatax.gov.cn:443/NWebQuery"]}</script>');
    const number = '12345678901234567890';
    const routes = await resolveInvoiceEndpoints(page, [{ invoice_number: number }]);
    assert.equal(routes[number], 'https://fpcy.zhejiang.chinatax.gov.cn:443/NWebQuery');
    await page.evaluate(() => { delete window.getSwjg; });
    await assert.rejects(resolveInvoiceEndpoints(page, [{ invoice_number: number }]), /getSwjg 不可用/);
  } finally { await browser.close(); }
});

test('stop interrupts an outstanding one-minute wait immediately', async () => {
  const controller = new AbortController();
  const guard = new TrafficGuard({ signal: controller.signal, log: () => {} });
  const pending = guard.cooldown();
  controller.abort();
  await assert.rejects(pending, /运行已停止/);
});
