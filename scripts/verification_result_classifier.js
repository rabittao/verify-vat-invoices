function normalizeSignalText(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}

function uniqTexts(texts) {
  return Array.from(new Set((texts || []).map(normalizeSignalText).filter(Boolean)));
}

function hasSuccessSignal(text) {
  const normalized = normalizeSignalText(text);
  if (!normalized) {
    return false;
  }

  if (/查验成功|相符/.test(normalized)) {
    return true;
  }
  if (/发票查验明细/.test(normalized)) {
    return true;
  }
  if (/(?:结果|信息)?一致(?!不)/.test(normalized) && !/不一致/.test(normalized)) {
    return true;
  }

  const detailFieldPattern = /(发票号码|开票日期|价税合计|购买方|销售方|项目名称|税额|查验时间)/;
  if (/查验次数/.test(normalized) && detailFieldPattern.test(normalized)) {
    return true;
  }
  if (/打印/.test(normalized) && /关闭/.test(normalized) && detailFieldPattern.test(normalized)) {
    return true;
  }

  return false;
}

function hasWebsiteSystemErrorSignal(text) {
  const normalized = normalizeSignalText(text);
  if (!normalized) {
    return false;
  }
  return /系统异常|请重试！?\(\d+\)|请稍后重试|服务异常/.test(normalized);
}

function getVerificationSignalPriority(text) {
  const normalized = normalizeSignalText(text);
  if (!normalized) {
    return -1;
  }
  if (hasSuccessSignal(normalized)) {
    return 100;
  }
  if (/超过.*查验次数|超过该张发票当日查验|请于次日再次查验/.test(normalized)) {
    return 90;
  }
  if (hasWebsiteSystemErrorSignal(normalized)) {
    return 85;
  }
  if (/查无此票|信息不一致|不一致|字段不匹配|录入信息有误/.test(normalized)) {
    return 80;
  }
  if (/验证码错误|校验码错误|图片验证码错误/.test(normalized)) {
    return 70;
  }
  if (/发票查验说明|首次查验前请点此安装根证书/.test(normalized)) {
    return 60;
  }
  if (/发票号码|开票日期|价税合计|验证码|查验/.test(normalized)) {
    return 40;
  }
  return 0;
}

function selectVisibleKeywordTexts(texts, limit = 12) {
  return uniqTexts(texts)
    .map((text, index) => ({
      text,
      index,
      priority: getVerificationSignalPriority(text),
      length: text.length,
    }))
    .sort((left, right) => (
      right.priority - left.priority ||
      right.length - left.length ||
      left.index - right.index
    ))
    .slice(0, limit)
    .sort((left, right) => left.index - right.index)
    .map((entry) => entry.text);
}

function buildVerificationSignalSummary(signals) {
  const popupTexts = Array.isArray(signals?.popupTexts) ? signals.popupTexts : [];
  const visibleKeywordTexts = Array.isArray(signals?.visibleKeywordTexts) ? signals.visibleKeywordTexts : [];
  const summary = [
    `popup_count=${popupTexts.length}`,
    `visible_keyword_count=${visibleKeywordTexts.length}`,
    `body_length=${normalizeSignalText(signals?.bodyText).length}`,
  ];
  if (popupTexts[0]) {
    summary.push(`popup_0=${popupTexts[0].slice(0, 160)}`);
  }
  if (visibleKeywordTexts[0]) {
    summary.push(`visible_0=${visibleKeywordTexts[0].slice(0, 160)}`);
  }
  return summary.join("; ");
}

function shouldRetryVerificationStatus(status) {
  return status === "captcha_error" || status === "form_still_active";
}

function classifyTerminalStatusText(text) {
  const normalized = normalizeSignalText(text);
  if (!normalized) {
    return null;
  }

  if (hasSuccessSignal(normalized)) {
    return {
      status: "success",
      message: "verification succeeded",
      matchedText: normalized,
    };
  }

  if (/超过.*查验次数|超过该张发票当日查验|请于次日再次查验/.test(normalized)) {
    return {
      status: "daily_limit_exceeded",
      message: "daily verification limit exceeded for this invoice",
      matchedText: normalized,
    };
  }

  if (hasWebsiteSystemErrorSignal(normalized)) {
    return {
      status: "website_system_error",
      message: "website reported a transient system error",
      matchedText: normalized,
    };
  }

  if (/查无此票|信息不一致|不一致|字段不匹配|录入信息有误/.test(normalized)) {
    return {
      status: "data_mismatch",
      message: "website reported invoice mismatch",
      matchedText: normalized,
    };
  }

  if (/验证码错误|校验码错误|图片验证码错误/.test(normalized)) {
    return {
      status: "captcha_error",
      message: "captcha rejected by website",
      matchedText: normalized,
    };
  }

  if (/发票查验说明|首次查验前请点此安装根证书|form_still_active/.test(normalized)) {
    return {
      status: "form_still_active",
      message: "verification form is still active",
      matchedText: normalized,
    };
  }

  return null;
}

function parseScreenshotVerificationClassification(rawText) {
  const normalized = normalizeSignalText(rawText);
  if (!normalized) {
    return null;
  }

  try {
    const parsed = JSON.parse(normalized);
    const combined = normalizeSignalText(
      [parsed.status, parsed.evidence, parsed.reason, parsed.message].filter(Boolean).join(" ")
    );
    const fromJson = classifyTerminalStatusText(combined);
    if (fromJson) {
      return fromJson;
    }
  } catch (_) {
    // Fall back to keyword parsing below.
  }

  return classifyTerminalStatusText(normalized);
}

function mergeScreenshotClassification(currentClassification, screenshotClassification) {
  if (!currentClassification) {
    return screenshotClassification || null;
  }
  if (!screenshotClassification) {
    return currentClassification;
  }
  if (
    shouldRetryVerificationStatus(currentClassification.status) &&
    !shouldRetryVerificationStatus(screenshotClassification.status) &&
    screenshotClassification.status !== "page_parse_error"
  ) {
    return screenshotClassification;
  }
  return currentClassification;
}

function shouldRunFullPageScreenshotFallback(screenshotClassification) {
  if (!screenshotClassification) {
    return true;
  }
  return shouldRetryVerificationStatus(screenshotClassification.status);
}

function resolveScreenshotFallbackClassification(currentClassification, screenshotResults) {
  const results = Array.isArray(screenshotResults) ? screenshotResults : [];
  let classification = currentClassification || null;
  const outputs = {};
  let appliedSource = null;

  for (const result of results) {
    if (!result) {
      continue;
    }
    if (result.source) {
      outputs[result.source] = result.rawOutput || "n/a";
    }
    const merged = mergeScreenshotClassification(classification, result.classified || null);
    if (merged !== classification && result.source) {
      appliedSource = result.source;
    }
    classification = merged || classification;
  }

  return {
    classification,
    appliedSource,
    outputs,
  };
}

function classifyVerificationSignals(signals) {
  const popupTexts = uniqTexts(signals?.popupTexts);
  const visibleKeywordTexts = uniqTexts(signals?.visibleKeywordTexts);
  const bodyText = normalizeSignalText(signals?.bodyText);
  const visibleContexts = uniqTexts([...popupTexts, ...visibleKeywordTexts]);
  const allContexts = uniqTexts([...visibleContexts, bodyText]);

  // Success must come from visible popup/snippet evidence rather than broad page text,
  // otherwise hidden/stale body content can override terminal error popups.
  const successMatch = visibleContexts.find(hasSuccessSignal);
  if (successMatch) {
    return {
      status: "success",
      message: "verification succeeded",
      matchedText: successMatch,
    };
  }

  const limitMatch = allContexts.find((text) => /超过.*查验次数|超过该张发票当日查验|请于次日再次查验/.test(text));
  if (limitMatch) {
    return {
      status: "daily_limit_exceeded",
      message: "daily verification limit exceeded for this invoice",
      matchedText: limitMatch,
    };
  }

  const systemErrorMatch = allContexts.find(hasWebsiteSystemErrorSignal);
  if (systemErrorMatch) {
    return {
      status: "website_system_error",
      message: "website reported a transient system error",
      matchedText: systemErrorMatch,
    };
  }

  const mismatchMatch = allContexts.find((text) => /查无此票|信息不一致|不一致|字段不匹配|录入信息有误/.test(text));
  if (mismatchMatch) {
    return {
      status: "data_mismatch",
      message: "website reported invoice mismatch",
      matchedText: mismatchMatch,
    };
  }

  const captchaMatch = allContexts.find((text) => /验证码错误|校验码错误|图片验证码错误/.test(text));
  if (captchaMatch) {
    return {
      status: "captcha_error",
      message: "captcha rejected by website",
      matchedText: captchaMatch,
    };
  }

  const rootCertificateMatch = allContexts.find((text) => /发票查验说明|首次查验前请点此安装根证书/.test(text));
  if (rootCertificateMatch && /发票号码|开票日期|验证码|查验/.test(bodyText)) {
    return {
      status: "form_still_active",
      message: "root certificate guidance shown but form is still accessible",
      matchedText: rootCertificateMatch,
    };
  }

  if (/发票号码|开票日期|验证码|查验/.test(bodyText)) {
    return {
      status: "form_still_active",
      message: "verification form is still active",
      matchedText: bodyText,
    };
  }

  return {
    status: "page_parse_error",
    message: `unable to classify website response: ${bodyText.slice(0, 220)}`,
    matchedText: bodyText,
  };
}

module.exports = {
  buildVerificationSignalSummary,
  classifyVerificationSignals,
  classifyTerminalStatusText,
  getVerificationSignalPriority,
  hasSuccessSignal,
  hasWebsiteSystemErrorSignal,
  mergeScreenshotClassification,
  normalizeSignalText,
  parseScreenshotVerificationClassification,
  resolveScreenshotFallbackClassification,
  selectVisibleKeywordTexts,
  shouldRunFullPageScreenshotFallback,
  shouldRetryVerificationStatus,
};
