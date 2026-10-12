const fs = require('fs');
const path = require('path');
const { isPlainCaptchaPrompt } = require('./deepseek_captcha_client');

function cleanupResumeImages({ folder, root, records, results, protectedNumber = null, graceMs = 120000, now = Date.now() }) {
  const successful = new Set(records.filter(r => r['结果截图'] && fs.existsSync(path.resolve(root, r['结果截图']))).map(r => r['发票号码']));
  const plain = new Set();
  const inspect = retry => {
    if (!isPlainCaptchaPrompt(retry.captcha_hint_text || retry.captcha_rule_display || '')) return;
    for (const key of ['captcha_image_path', 'captcha_preprocessed_path']) {
      if (retry[key]) plain.add(path.resolve(retry[key]));
    }
  };
  for (const result of results) { inspect(result); for (const retry of result.captcha_retry_history || []) inspect(retry); }
  const report = { deleted: [], kept: [], protected: [] };
  for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
    if (!entry.isFile() || !/\.(?:png|jpe?g)$/i.test(entry.name)) continue;
    const file = path.join(folder, entry.name);
    const number = /^(\d{20})(?:-|_)/.exec(entry.name)?.[1];
    if (!number || number === protectedNumber || (graceMs > 0 && now - fs.statSync(file).mtimeMs < graceMs)) {
      report.protected.push(entry.name); continue;
    }
    let reason;
    if (successful.has(number)) reason = '已存在正式结果截图，删除该票临时图片';
    else if (/-captcha-(?:original|model-4x)\.png$/i.test(entry.name) && !plain.has(path.resolve(file))) reason = '未用于已记录的普通文字验证码识别';
    if (reason) { fs.unlinkSync(file); report.deleted.push({ file: entry.name, reason }); }
    else report.kept.push(entry.name);
  }
  return report;
}
module.exports = { cleanupResumeImages };

if (require.main === module) {
  const root = path.resolve(__dirname, '../..');
  const folder = path.resolve(__dirname, '../output/resume');
  const records = JSON.parse(fs.readFileSync(path.join(root, '.核对工作/manifest.json'), 'utf8'));
  const results = JSON.parse(fs.readFileSync(path.join(folder, 'results.json'), 'utf8'));
  const status = JSON.parse(fs.readFileSync(path.join(folder, 'run-status.json'), 'utf8'));
  let alive = false;
  try { if (status.pid) { process.kill(status.pid, 0); alive = true; } } catch (_) {}
  const report = cleanupResumeImages({ folder, root, records, results, protectedNumber: alive ? status.invoice_number : null, graceMs: alive ? 120000 : 0 });
  const reportPath = path.resolve(__dirname, '../output/diagnosis/resume-image-cleanup-' + Date.now() + '.json');
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ deleted: report.deleted.length, kept: report.kept.length, protected: report.protected.length, report: reportPath }));
}
