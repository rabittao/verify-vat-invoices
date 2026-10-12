const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const path = require('node:path');
const client = require('../scripts/deepseek_captcha_client');
const verifier = require('../scripts/verify_invoices');

test('DeepSeek request uses official vision shape and preserves final content', async () => {
  let seen;
  const result = await client.callDeepSeekVision(Buffer.from('image'), 'read', {
    env: { DEEPSEEK_API_KEY: 'test-only' },
    fetchImpl: async (url, request) => {
      seen = { url, request, payload: JSON.parse(request.body) };
      return { ok: true, json: async () => ({ choices: [{ message: { content: 'AbCd', reasoning_content: 'ignore' } }] }) };
    },
  });
  assert.equal(seen.url, 'https://api.deepseek.com/chat/completions');
  assert.equal(seen.payload.model, 'deepseek-flash');
  assert.equal(seen.payload.thinking.type, 'disabled');
  assert.equal(seen.payload.messages[0].content[1].image_url.url, 'data:image/png;base64,aW1hZ2U=');
  assert.equal(result.rawContent, 'AbCd');
});

test('plain prompt accepts alphanumeric answers and rejects any Chinese', () => {
  assert.equal(client.isPlainCaptchaPrompt('请输入验证码文字'), true);
  assert.equal(client.isPlainCaptchaPrompt('请输入验证码图片中 蓝色 文字'), false);
  assert.equal(client.isPlainCaptchaPrompt('其他请输入验证码文字'), false);
  assert.equal(client.parseCaptchaResponse(' AbCd '), 'AbCd');
  for (const answer of ['A1BC', '1234']) assert.equal(client.parseCaptchaResponse(answer), answer);
  for (const answer of ['CHINESE', 'A中BC', '仙乃日', '贝急T5', '尪FM', 'UNKNOWN', '答案是ABCD', 'AB CD', '```ABCD```', '']) {
    assert.equal(client.parseCaptchaResponse(answer), '');
  }
});

test('missing key fails without HTTP; 401 permanent, 429 transient, no body leaked', async () => {
  await assert.rejects(client.callDeepSeekVision(Buffer.from('x'), 'x', { env: {} }), /not configured/);
  for (const status of [401, 429, 503]) {
    await assert.rejects(client.callDeepSeekVision(Buffer.from('x'), 'x', {
      env: { DEEPSEEK_API_KEY: 'test-only' },
      fetchImpl: async () => ({ ok: false, status, text: () => { throw new Error('must not read'); } }),
    }), error => error.message === `DeepSeek API HTTP ${status}` && error.retryable === (status !== 401));
  }
});

test('truncated output never becomes a captcha candidate', async () => {
  const result = await client.callDeepSeekVision(Buffer.from('x'), 'x', {
    env: { DEEPSEEK_API_KEY: 'test-only' },
    fetchImpl: async () => ({ ok: true, json: async () => ({ choices: [{ finish_reason: 'length', message: { content: 'ABC' } }] }) }),
  });
  assert.equal(result.rawContent, '');
});

test('CLI budget is 3 and cannot multiply through page retries', () => {
  const args = ['node', 'verify', '--input-json', 'i', '--output-json', 'o', '--artifacts-dir', 'a'];
  assert.equal(verifier.parseArgs(args).maxCaptchaAttempts, 3);
  for (const value of ['0', '4', 'NaN', '1.5']) {
    assert.throws(() => verifier.parseArgs([...args, '--max-captcha-attempts', value]), /integer/);
  }
});

test('challenge gates model calls on the current prompt, including refresh changing it', async () => {
  // Run the actual challenge function with isolated browser/model boundaries.
  const file = path.resolve(__dirname, '../scripts/verify_invoices.js');
  const sandbox = { require: createRequire(file), module: { exports: {} }, __dirname: path.dirname(file), console, Buffer, process };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
  sandbox.calls = 0;
  sandbox.saves = 0;
  sandbox.hints = [];
  vm.runInContext(`
    readCaptchaPromptText = async () => hints.shift();
    resolveVerificationAmount = () => ({});
    findCaptchaImage = async () => ({ waitFor: async () => {}, screenshot: async () => Buffer.from('img') });
    enlargeCaptchaForModel = async (_, buffer) => buffer;
    preprocessCaptchaImages = () => { saves++; return { original: 'mock.png' }; };
    collectCaptchaCandidates = async () => { calls++; return { primaryCaptcha: 'ABCD', alternativeCaptchas: [] }; };
  `, sandbox);
  const page = { locator: () => ({ innerText: async () => '请输入验证码文字' }) };
  for (const hints of [
    ['请输入验证码图片中红色文字', '请输入验证码图片中红色文字'],
    ['请输入验证码文字', '请输入验证码图片中蓝色文字'],
    ['请输入验证码文字', '请输入验证码文字'],
  ]) {
    const expected = hints.every(hint => hint === '请输入验证码文字') ? 1 : 0;
    sandbox.hints = hints;
    const outcome = await sandbox.module.exports.readCaptchaChallenge(page, {}, '.', 'sample', 1);
    assert.equal(outcome.captchaCandidates.length, expected);
    assert.equal(outcome.imagePaths.original, expected ? 'mock.png' : null);
  }
  assert.equal(sandbox.calls, 1);
  assert.equal(sandbox.saves, 1);
});

test('empty recognitions never consume valid candidate budget and pause after selection cap', async () => {
  const file = path.resolve(__dirname, '../scripts/verify_invoices.js');
  const sandbox = { require: createRequire(file), module: { exports: {} }, __dirname: path.dirname(file), console, Buffer, process };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox);
  sandbox.calls = 0;
  vm.runInContext(`
    forceCloseDialogs = async () => {};
    fillField = async () => {};
    readCaptchaPromptText = async () => '请输入验证码文字';
    resolveVerificationAmount = () => ({ type: 'total_amount', value: '10.00' });
    refreshCaptcha = async () => {};
    readCaptchaChallenge = async () => {
      calls++;
      return { captchaRule: 'full_text', captchaRuleDisplay: '请输入验证码文字',
        promptText: '请输入验证码文字', captchaCandidates: [], captchaImage: {},
        imagePaths: { original: 'mock.png' }, candidateBundle: {}, captchaHash: String(calls) };
    };
  `, sandbox);
  let navigations = 0;
  const page = {
    goto: async () => { navigations++; }, waitForSelector: async () => {}, waitForTimeout: async () => {},
    keyboard: { press: async () => {} },
    locator: () => ({ innerText: async () => '价税合计', click: async () => {} }),
  };
  const record = { invoice_number: '12345678901234567890', invoice_date: '2026-09-02', pretax_amount: '10.00', total_amount: '10.00' };
  const outcome = await sandbox.module.exports.verifySingleInvoice(page, record, '.', 3);
  assert.equal(sandbox.calls, 40);
  assert.equal(navigations, 1);
  assert.equal(outcome.verification_status, 'captcha_selection_exhausted');
  assert.equal(outcome.captcha_attempts, 0);
  assert.equal(outcome.captcha_retry_history.length, 40);
});
