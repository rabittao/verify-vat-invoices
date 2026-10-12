const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { cleanupResumeImages } = require('../scripts/resume_image_retention');

test('keeps plain failed captchas and error screenshots; removes successful temporary images and filtered captchas', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'retention-'));
  const folder = path.join(root, 'resume'); fs.mkdirSync(folder);
  const success = '11111111111111111111', failure = '22222222222222222222', active = '33333333333333333333';
  const put = name => { const file = path.join(folder, name); fs.writeFileSync(file, 'image'); return file; };
  try {
    const plain = put(`${failure}-retry-1-captcha-original.png`);
    const filtered = put(`${failure}-retry-2-captcha-original.png`);
    const error = put(`${failure}-retry-1-result.png`);
    const done = put(`${success}-result.jpg`);
    const running = put(`${active}-captcha-original.png`);
    fs.mkdirSync(path.join(root, 'pdf')); fs.writeFileSync(path.join(root, 'pdf/formal.jpg'), 'formal');
    const report = cleanupResumeImages({ folder, root, records: [{ 发票号码: success, 结果截图: 'pdf/formal.jpg' }],
      results: [{ captcha_retry_history: [{ captcha_hint_text: '请输入验证码文字', captcha_image_path: plain },
        { captcha_hint_text: '请输入验证码图片中蓝色文字', captcha_image_path: filtered }] }], protectedNumber: active, graceMs: 0 });
    assert.equal(report.deleted.length, 2);
    assert.ok(fs.existsSync(plain) && fs.existsSync(error) && fs.existsSync(running));
    assert.ok(!fs.existsSync(done) && !fs.existsSync(filtered));
    assert.ok(fs.existsSync(path.join(root, 'pdf/formal.jpg')));
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test('missing formal result never triggers successful-invoice deletion; recent files protected', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'retention-'));
  try {
    const file = path.join(root, '11111111111111111111-result.jpg'); fs.writeFileSync(file, 'error');
    const report = cleanupResumeImages({ folder: root, root, records: [{ 发票号码: '11111111111111111111', 结果截图: 'missing.jpg' }], results: [], graceMs: 0 });
    assert.equal(report.deleted.length, 0);
    assert.ok(fs.existsSync(file));
    const captcha = path.join(root, '22222222222222222222-captcha-original.png'); fs.writeFileSync(captcha, 'fresh');
    assert.equal(cleanupResumeImages({ folder: root, root, records: [], results: [] }).protected.length, 2);
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});
