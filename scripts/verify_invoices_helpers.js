function nowIso() {
  return new Date().toISOString();
}

function loadEnvFile(envPath, processEnv = process.env, fsModule = require("fs")) {
  if (!fsModule.existsSync(envPath)) {
    return;
  }

  const lines = fsModule.readFileSync(envPath, "utf-8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) {
      continue;
    }
    const eqIndex = trimmed.indexOf("=");
    const key = trimmed.slice(0, eqIndex).trim();
    const value = trimmed.slice(eqIndex + 1).trim();
    if (!(key in processEnv) || processEnv[key] === "") {
      processEnv[key] = value;
    }
  }
}

function buildInvoiceKey(record) {
  const required = [record.invoice_number, record.invoice_date, record.pretax_amount];
  if (!required.every(Boolean)) {
    return null;
  }
  return [
    record.invoice_code || "",
    record.invoice_number,
    record.invoice_date,
    record.pretax_amount,
  ].join("|");
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function scoreScreenshotCandidate(candidate, viewport) {
  const width = Number(candidate?.width || 0);
  const height = Number(candidate?.height || 0);
  if (width <= 0 || height <= 0) {
    return -Infinity;
  }

  const viewportWidth = Number(viewport?.width || 0);
  const viewportHeight = Number(viewport?.height || 0);
  const centerX = Number(candidate?.x || 0) + width / 2;
  const centerY = Number(candidate?.y || 0) + height / 2;
  const viewportCenterX = viewportWidth / 2;
  const viewportCenterY = viewportHeight / 2;
  const dx = centerX - viewportCenterX;
  const dy = centerY - viewportCenterY;
  const distance = Math.sqrt(dx * dx + dy * dy);
  const maxDistance = Math.sqrt(viewportWidth * viewportWidth + viewportHeight * viewportHeight) || 1;
  const centerScore = 1 - distance / maxDistance;
  const areaScore = (width * height) / Math.max(viewportWidth * viewportHeight, 1);

  const text = String(candidate?.text || "");
  let keywordScore = 0;
  if (/发票查验明细/.test(text)) keywordScore += 6;
  if (/查验次数/.test(text)) keywordScore += 4;
  if (/打印/.test(text) && /关闭/.test(text)) keywordScore += 4;
  if (/发票号码|开票日期|价税合计|合计/.test(text)) keywordScore += 3;
  if (/手把手教您查发票/.test(text)) keywordScore -= 3;

  return keywordScore * 100 + areaScore * 1000 + centerScore * 200;
}

function selectBestScreenshotClip(candidates, viewport, padding = 16) {
  const list = Array.isArray(candidates) ? candidates : [];
  const best = list
    .map((candidate) => ({ candidate, score: scoreScreenshotCandidate(candidate, viewport) }))
    .sort((left, right) => right.score - left.score)[0]?.candidate;

  if (!best) {
    return null;
  }

  const viewportWidth = Number(viewport?.width || 0);
  const viewportHeight = Number(viewport?.height || 0);
  const x = clamp(Math.round(Number(best.x || 0) - padding), 0, Math.max(viewportWidth - 1, 0));
  const y = clamp(Math.round(Number(best.y || 0) - padding), 0, Math.max(viewportHeight - 1, 0));
  const maxWidth = Math.max(viewportWidth - x, 1);
  const maxHeight = Math.max(viewportHeight - y, 1);

  return {
    x,
    y,
    width: clamp(Math.round(Number(best.width || 0) + padding * 2), 1, maxWidth),
    height: clamp(Math.round(Number(best.height || 0) + padding * 2), 1, maxHeight),
  };
}

function resolveCaptchaExhaustion({
  attempt,
  maxCaptchaAttempts,
  record,
  challenge,
  captchaRetryHistory,
  amountInfo,
  fullTextAttempts = 0,
  maxFullTextAttempts = 10,
  maxRefreshRetries = 40,
}) {
  if (attempt < maxCaptchaAttempts) {
    return {
      action: "retry_page",
      nextAttempt: attempt + 1,
    };
  }

  const lastRetry = captchaRetryHistory.length > 0
    ? captchaRetryHistory[captchaRetryHistory.length - 1]
    : null;
  const lastResultScreenshot = lastRetry?.result_screenshot || null;

  return {
    action: "return_result",
    result: {
      invoice_key: buildInvoiceKey(record),
      verification_status: "captcha_error",
      verification_message: fullTextAttempts >= maxFullTextAttempts
        ? `captcha failed after ${maxFullTextAttempts} full_text attempts`
        : `captcha failed: could not get full_text captcha after ${maxRefreshRetries} refreshes`,
      captcha_attempts: attempt,
      captcha_rule: challenge?.captchaRule || null,
      captcha_rule_display: challenge?.captchaRuleDisplay || "未识别到明确验证码规则",
      captcha_hint_text: challenge?.promptText || null,
      captcha_candidates: challenge?.captchaCandidates || [],
      captcha_image_path: challenge?.imagePaths?.original || null,
      captcha_preprocessed_path: challenge?.imagePaths?.ocr_used || challenge?.imagePaths?.original || null,
      captcha_retry_history: captchaRetryHistory,
      verified_at: nowIso(),
      verification_amount_type: amountInfo?.type || null,
      verification_amount_used: amountInfo?.value || null,
      result_screenshot: lastResultScreenshot,
      result_text: null,
    },
  };
}

module.exports = {
  buildInvoiceKey,
  loadEnvFile,
  nowIso,
  resolveCaptchaExhaustion,
  selectBestScreenshotClip,
};
