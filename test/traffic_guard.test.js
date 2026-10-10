const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { TrafficGuard, isRateLimitText } = require('../scripts/traffic_guard');
const { isPending } = require('../scripts/resume_pending');

test('one-minute limits are distinct from daily limits and wrong captchas', () => {
  for (const text of ['访问过于频繁，请1分钟后再试', '请于一分钟后再次查验', '访问频率过高，请60秒后重试', '操作太频繁']) {
    assert.equal(isRateLimitText(text), true);
  }
  for (const text of ['验证码错误', '请于次日再次查验', '发票查验明细']) assert.equal(isRateLimitText(text), false);
});

test('refresh and submission clocks are separate; cooldown backs off without requests', async () => {
  let now = 0;
  const sleeps = [];
  const guard = new TrafficGuard({ now: () => now, sleep: async ms => { sleeps.push(ms); now += ms; }, log: () => {} });
  await guard.wait('refresh');
  await guard.wait('refresh');
  assert.deepEqual(sleeps, [10000]);
  await guard.wait('submit');
  now += 1000;
  await guard.wait('submit');
  assert.equal(sleeps.at(-1), 64000);
  guard.pendingDialog = '请1分钟后再试';
  await guard.cooldown();
  await guard.cooldown();
  await guard.cooldown();
  await guard.cooldown();
  assert.deepEqual(sleeps.slice(-4), [65000, 130000, 260000, 300000]);
  assert.equal(guard.pendingDialog, '');
});

test('rate limit is checked before existing dialog cleanup can erase its evidence', async () => {
  const file = path.resolve(__dirname, '../scripts/verify_invoices.js');
  const sandbox = { require: createRequire(file), module: { exports: {} }, __dirname: path.dirname(file), console, Buffer, process };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8') + '\nmodule.exports.forceCloseDialogs = forceCloseDialogs;', sandbox);
  let cleaned = false;
  const page = { trafficGuard: new TrafficGuard(),
    locator: () => ({ innerText: async () => '访问过于频繁，请1分钟后再试' }),
    evaluate: async () => { cleaned = true; }, waitForTimeout: async () => {} };
  await assert.rejects(sandbox.module.exports.forceCloseDialogs(page), error => error.code === 'PLATFORM_RATE_LIMIT');
  assert.equal(cleaned, false);
  page.trafficGuard.pendingDialog = '请一分钟后再试';
  page.locator = () => ({ innerText: async () => '正常页面' });
  await assert.rejects(page.trafficGuard.check(page), error => error.code === 'PLATFORM_RATE_LIMIT');
});

test('resume skips only a result whose screenshot exists', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'invoice-resume-'));
  try {
    fs.writeFileSync(path.join(root, 'result.jpg'), 'test');
    assert.equal(isPending({ 结果截图: 'result.jpg' }, root), false);
    assert.equal(isPending({ 结果截图: 'missing.jpg' }, root), true);
    assert.equal(isPending({}, root), true);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
