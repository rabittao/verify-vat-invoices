const { callDeepSeekVision, parseCaptchaResponse } = require('./deepseek_captcha_client');

const INSPECTION_PROMPT = '检查图片中全部可见验证码字符，不要忽略任何字符，也不要只挑英文字母。先判断是否含任意中文汉字，包括倾斜、重叠、局部遮挡的汉字；不需要判断汉字具体读音。逐字抄录全部字符，保持顺序和大小写。只返回JSON：{"contains_chinese":true或false或null,"text":"完整字符","count":字符总数}。不能确定是否有汉字时用null。text中无法确定的字符用?占位，不能删除；count包含汉字和无法辨认的字符。';

function inspectAnswer(raw) {
  let data;
  try { data = JSON.parse(raw); } catch (_) { return { allowed:false, reason:'content_check_uncertain' }; }
  if (data?.contains_chinese === true || /\p{Script=Han}/u.test(String(data?.text || ''))) {
    return { allowed:false, reason:'chinese_captcha_refresh' };
  }
  if (data?.contains_chinese !== false || typeof data.text !== 'string' ||
      !parseCaptchaResponse(data.text) || !Number.isInteger(data.count) || data.count !== data.text.length) {
    return { allowed:false, reason:'content_check_uncertain' };
  }
  return { allowed:true, text:data.text, count:data.count };
}

async function recognizeCheckedCaptcha(image, prompt, call = callDeepSeekVision) {
  const inspection = await call(image, INSPECTION_PROMPT);
  const gate = inspectAnswer(inspection.rawContent);
  const base = { alternativeCaptchas:[], modelUsed:inspection.model,
    contentCheck: { ...gate, raw:inspection.rawContent } };
  if (!gate.allowed) return { ...base, primaryCaptcha:'', rawOutput:inspection.rawContent,
    rejectionReason:gate.reason, confidenceNote:'content check rejected; not submitted' };
  const answer = await call(image, prompt);
  const candidate = parseCaptchaResponse(answer.rawContent);
  // Independent full transcription must agree; a plausible partial OCR answer is insufficient.
  const accepted = candidate && candidate === gate.text;
  return { ...base, primaryCaptcha:accepted ? candidate : '', rawOutput:answer.rawContent,
    rejectionReason:accepted ? null : 'content_check_disagreement',
    confidenceNote:`${answer.model}: content check and transcription agreement` };
}
module.exports = { inspectAnswer, recognizeCheckedCaptcha };
