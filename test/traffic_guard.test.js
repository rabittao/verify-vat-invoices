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
  assert.equal(guard.lastSubmit, null);
  guard.markSubmitted();
  now += 1000;
  await guard.wait('submit');
  assert.equal(sleeps.at(-1), 64000);
  assert.equal(guard.lastSubmit, 10000);
  const before = sleeps.length;
  await guard.wait('submit');
  assert.equal(sleeps.length, before); // 没有实际提交，不再额外等65秒。
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

test('real challenge function captures after cooldown and refresh, never old image', async () => {
  const file = path.resolve(__dirname, '../scripts/verify_invoices.js');
  const sandbox = { require: createRequire(file), module: { exports: {} }, __dirname: path.dirname(file), console, Buffer, process };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
  sandbox.currentImage = 'old';
  sandbox.modelImage = null;
  sandbox.prompt = '请输入验证码文字';
  vm.runInContext(`
    readCaptchaPromptText = async () => prompt;
    resolveVerificationAmount = () => ({});
    findCaptchaImage = async () => ({waitFor:async()=>{},screenshot:async()=>Buffer.from(currentImage)});
    refreshCaptcha = async () => {currentImage='fresh-after-wait';};
    enlargeCaptchaForModel = async (_, buffer) => buffer;
    preprocessCaptchaImages = () => ({original:'mock.png'});
    collectCaptchaCandidates = async buffer => {modelImage=buffer.toString();return {primaryCaptcha:'ABCD',alternativeCaptchas:[]};};
  `, sandbox);
  const page = { locator: () => ({ innerText: async () => '' }),
    trafficGuard: { wait: async () => { sandbox.currentImage='changed-during-wait'; return 65000; }, check: async () => {} } };
  await sandbox.module.exports.readCaptchaChallenge(page, {}, '.', 'sample', 1);
  assert.equal(sandbox.modelImage, 'fresh-after-wait');
  sandbox.modelImage = null;
  vm.runInContext(`refreshCaptcha=async()=>{currentImage='color-image';prompt='请输入验证码图片中蓝色文字';};`, sandbox);
  const result = await sandbox.module.exports.readCaptchaChallenge(page, {}, '.', 'sample', 1);
  assert.equal(sandbox.modelImage, null);
  assert.equal(result.captchaRule, 'unknown');
});

test('captcha error acknowledgement invokes website button callback in real local browser', async () => {
  const { chromium } = require('playwright');
  const { acknowledgeCaptchaError } = require('../scripts/verify_invoices');
  const browser = await chromium.launch({headless:true});
  try {
    const page = await browser.newPage();
    await page.setContent(`<div id="popup_container"><p>验证码错误!</p><button onclick="window.confirmed=true;document.getElementById('popup_container').style.display='none'">确定</button></div>`);
    assert.equal(await acknowledgeCaptchaError(page), true);
    assert.equal(await page.evaluate(() => window.confirmed), true);
    assert.equal(await page.locator('#popup_container').count(), 1); // 回调关闭弹窗，未删除DOM。
    assert.equal(await acknowledgeCaptchaError(page), false);
  } finally { await browser.close(); }
});

test('actual retry loop acknowledges every captcha rejection, including final attempt', async () => {
  const file = path.resolve(__dirname, '../scripts/verify_invoices.js');
  const sandbox = { require: createRequire(file), module: { exports: {} }, __dirname: path.dirname(file), console, Buffer, process };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
  sandbox.confirmed = 0;
  sandbox.submitted = 0;
  sandbox.selections = 0;
  const hash = require('crypto').createHash('md5').update(Buffer.from('fresh')).digest('hex');
  sandbox.hash = hash;
  vm.runInContext(`
    forceCloseDialogs=async()=>{};
    fillField=async()=>{};
    refreshCaptcha=async()=>{};
    readCaptchaPromptText=async()=> '请输入验证码文字';
    resolveVerificationAmount=()=>({value:'10.00'});
    findCaptchaImage=async()=>({screenshot:async()=>Buffer.from('fresh')});
    readCaptchaChallenge=async()=>{selections++;return {captchaHash:hash,captchaRule:'full_text',captchaRuleDisplay:'请输入验证码文字',
      promptText:'请输入验证码文字',captchaCandidates:selections<=5 ? [] : ['ABCD'],captchaImage:{},imagePaths:{original:'mock'},candidateBundle:{}};};
    waitForSubmitButton=async()=>({click:async()=>{submitted++;}});
    waitForVerificationOutcome=async()=>({classified:{status:'captcha_error',message:'验证码错误'},
      signals:{popupTexts:['验证码错误!'],visibleKeywordTexts:[],bodyText:''}});
    collectVerificationSignals=async()=>({popupTexts:['验证码错误!'],visibleKeywordTexts:[],bodyText:''});
    getVerificationScreenshotClip=async()=>null;
    classifyVerificationScreenshot=async()=>{throw new Error('explicit captcha rejection must not use vision fallback');};
    acknowledgeCaptchaError=async()=>{confirmed++;return true;};
  `, sandbox);
  const page={goto:async()=>{},waitForSelector:async()=>{},waitForTimeout:async()=>{},screenshot:async()=>{},
    keyboard:{press:async()=>{}},locator:()=>({innerText:async()=>'',click:async()=>{}})};
  const result=await sandbox.module.exports.verifySingleInvoice(page,
    {invoice_number:'12345678901234567890',invoice_date:'2026-09-02',total_amount:'10.00'},'.',3);
  assert.equal(sandbox.selections,8); // 5次无有效英文候选后，仍允许3次英文查验。
  assert.equal(sandbox.submitted,3);
  assert.equal(sandbox.confirmed,3);
  assert.equal(result.submitted_attempts,3);
  assert.equal(result.failure_reason,'captcha_rejected');
  assert.equal(result.captcha_retry_history.length,8);
});

test('model preprocessing enlarges pixels 4x and prompt distinguishes I/T and R/B', async () => {
  const { chromium } = require('playwright');
  const { enlargeCaptchaForModel, buildCaptchaPrompt } = require('../scripts/verify_invoices');
  const browser = await chromium.launch({headless:true});
  try {
    const page = await browser.newPage();
    await page.setContent('<canvas id="sample" width="120" height="50"></canvas>');
    const source = Buffer.from(await page.evaluate(() => document.querySelector('canvas').toDataURL('image/png').split(',')[1]), 'base64');
    const modelImage = await enlargeCaptchaForModel(page, source);
    assert.equal(modelImage.readUInt32BE(16),480);
    assert.equal(modelImage.readUInt32BE(20),200);
    assert.match(buildCaptchaPrompt(),/I 与 T/);
    assert.match(buildCaptchaPrompt(),/R 与 B/);
  } finally { await browser.close(); }
});
