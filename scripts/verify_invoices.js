#!/usr/bin/env node
/* Verify extracted VAT invoices on the Chinatax site and write normalized results. */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const {
  callDeepSeekVision,
  parseCaptchaResponse,
  isPlainCaptchaPrompt,
} = require("./deepseek_captcha_client");
const {
  buildVerificationSignalSummary,
  classifyVerificationSignals,
  mergeScreenshotClassification,
  normalizeSignalText,
  parseScreenshotVerificationClassification,
  resolveScreenshotFallbackClassification,
  selectVisibleKeywordTexts,
  shouldRunFullPageScreenshotFallback,
  shouldRetryVerificationStatus,
} = require("./verification_result_classifier");
const {
  buildInvoiceKey,
  loadEnvFile,
  nowIso,
  resolveCaptchaExhaustion,
  selectBestScreenshotClip,
} = require("./verify_invoices_helpers");

const { installSubmissionTrace, submissionFailure, clickVerificationButton } = require("./submission_trace");

const { VERIFY_URL, MODERN_FIELDS, selectInvoiceDate } = require("./tax_site");
const { recognizeCheckedCaptcha } = require('./captcha_content_gate');
const MAX_FULL_TEXT_ATTEMPTS = 3;
const MAX_REFRESH_RETRIES = 40;
const VERIFY_SINGLE_INVOICE_TIMEOUT_MS = 4 * 60 * 1000; // 与验证码重试预算对齐，避免真实 captcha_error 被外层超时盖掉

loadEnvFile(path.resolve(__dirname, "..", ".env"));

function parseArgs(argv) {
  const args = {
    maxCaptchaAttempts: 3,
  };
  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];
    if (token === "--input-json") {
      args.inputJson = next;
      index += 1;
    } else if (token === "--output-json") {
      args.outputJson = next;
      index += 1;
    } else if (token === "--artifacts-dir") {
      args.artifactsDir = next;
      index += 1;
    } else if (token === "--max-captcha-attempts") {
      args.maxCaptchaAttempts = Number(next);
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${token}`);
    }
  }
  if (!args.inputJson || !args.outputJson || !args.artifactsDir) {
    throw new Error("Usage: verify_invoices.js --input-json <file> --output-json <file> --artifacts-dir <dir>");
  }
  if (!Number.isInteger(args.maxCaptchaAttempts) || args.maxCaptchaAttempts < 1 || args.maxCaptchaAttempts > 3) {
    throw new Error("--max-captcha-attempts must be an integer between 1 and 3");
  }
  return args;
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf-8"));
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function slugify(value) {
  return String(value)
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 80) || "invoice";
}

function sanitizeForInput(value) {
  return String(value ?? "").trim();
}

function normalizeDateForForm(value) {
  return sanitizeForInput(value).replace(/[^\d]/g, "");
}

function createSkippedResult(record, message, status = "skipped") {
  return {
    invoice_key: buildInvoiceKey(record),
    verification_status: status,
    verification_message: message,
    captcha_attempts: 0,
    captcha_rule: null,
    captcha_rule_display: null,
    captcha_candidates: [],
    captcha_image_path: null,
    captcha_preprocessed_path: null,
    verified_at: null,
    verification_amount_type: null,
    verification_amount_used: null,
    result_screenshot: null,
    result_text: null,
  };
}

async function requirePlaywright() {
  try {
    return require("playwright");
  } catch (error) {
    throw new Error(
      "Playwright is not installed. Run `npm install` in the verify-vat-invoices directory first."
    );
  }
}

async function resolveInputLocator(page, selectors) {
  for (const selector of selectors) {
    const all = page.locator(selector);
    const count = await all.count();
    if (count === 0) continue;
    // Prefer visible elements when duplicates exist
    for (let i = 0; i < count; i++) {
      const loc = all.nth(i);
      if (await loc.isVisible().catch(() => false)) {
        return loc;
      }
    }
    return all.first();
  }
  return null;
}

async function fillField(page, value, selectors, name) {
  // 确保弹窗不会阻挡点击
  await forceCloseDialogs(page);
  const locator = await resolveInputLocator(page, selectors);
  if (!locator) {
    throw new Error(`Unable to find input for ${name}`);
  }
  const cleanValue = sanitizeForInput(value);
  if (name === "invoice_date" && await locator.getAttribute("readonly") !== null) {
    await selectInvoiceDate(page, cleanValue);
    return locator;
  }
  await locator.click({ force: true });
  await locator.fill("");
  await locator.fill(cleanValue);

  // The chinatax website uses jQuery event listeners that don't fire on Playwright's fill().
  // Use the native value setter + jQuery trigger to activate the form validation JS.
  await locator.evaluate((el, val) => {
    const nativeSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, "value"
    ).set;
    nativeSetter.call(el, val);
    if (window.jQuery) {
      const $el = window.jQuery(el);
      ["input", "change", "keyup"].forEach(ev => $el.trigger(ev));
    } else {
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }, cleanValue);

  return locator;
}

async function findCaptchaImage(page) {
  const selectors = [
    "img[width='120'][height='50']",
    "#yzm_img",
    "img[alt*='验证码']",
    "img[title*='验证码']",
    "img[src*='yzm']",
    "img[src*='captcha']",
    ".yzm img",
  ];
  for (const selector of selectors) {
    const all = page.locator(selector);
    const count = await all.count();
    if (count === 0) continue;
    for (let i = 0; i < count; i++) {
      const loc = all.nth(i);
      if (await loc.isVisible().catch(() => false)) {
        return loc;
      }
    }
    return all.first();
  }
  throw new Error("Unable to find captcha image");
}

async function findSubmitButton(page) {
  const selectors = [
    "#checkfp",
    "button:has-text('查验')",
    "input[type='button'][value*='查验']",
    "input[type='submit'][value*='查验']",
    "a:has-text('查验')",
  ];
  for (const selector of selectors) {
    const all = page.locator(selector);
    const count = await all.count();
    if (count === 0) continue;
    // Prefer visible elements when duplicates exist
    for (let i = 0; i < count; i++) {
      const loc = all.nth(i);
      if (await loc.isVisible().catch(() => false)) {
        return loc;
      }
    }
    return all.first();
  }
  throw new Error("Unable to find verify button");
}

// ============================================================================
// Vision Model OCR for Captcha
// Model: deepseek-flash (DeepSeek official multimodal API)
// ============================================================================
function buildCaptchaPrompt() {
  return "识别图片中从左到右的全部验证码字符，保留大小写。逐个检查完整轮廓，忽略彩色干扰线和立体阴影。特别区分大写 I 与 T：I 的顶部和底部均有横线，T 只有顶部横线；区分 R 与 B：R 的右下部是斜腿，B 是封闭圆弧。不要把干扰线拆成字符，不要添加图片中不存在的字符。只输出字符，不要解释、标点或代码块。无法确定任何字符时只输出 UNKNOWN。只接受英文字母和数字。如果图片中出现任何中文汉字，整张只输出 CHINESE，不要输出其余字符，不要尝试把汉字转成字母。";
}

async function captureCaptchaWithVisionModel(imageBuffer, promptText) {
  return recognizeCheckedCaptcha(imageBuffer, buildCaptchaPrompt(promptText));
}

function buildVerificationScreenshotPrompt() {
  return [
    "你将看到一张中国税务发票查验页面截图。",
    "请只根据截图中当前可见内容判断终态。",
    "可选状态只有：success、daily_limit_exceeded、website_system_error、data_mismatch、captcha_error、form_still_active、unknown。",
    "如果截图中出现“发票查验明细”或完整发票明细弹层，判定为 success。",
    "如果截图中出现“超过该张发票当日查验次数”或“请于次日再次查验”，判定为 daily_limit_exceeded。",
    "如果截图中出现“系统异常，请重试”或类似系统错误弹窗，判定为 website_system_error。",
    "如果截图中出现“验证码错误”之类提示，判定为 captcha_error。",
    "请只输出一行 JSON，例如：{\"status\":\"success\",\"evidence\":\"发票查验明细\"}",
  ].join(" ");
}

async function classifyVerificationScreenshot(screenshotPath) {
  if (!screenshotPath || !fs.existsSync(screenshotPath)) {
    return null;
  }

  const screenshotBuffer = fs.readFileSync(screenshotPath);
  const apiResult = await callDeepSeekVision(
    screenshotBuffer,
    buildVerificationScreenshotPrompt(),
    { maxTokens: 120 }
  );
  return {
    classified: parseScreenshotVerificationClassification(apiResult.rawContent || apiResult.result),
    rawOutput: normalizeSignalText(apiResult.rawContent || apiResult.result),
  };
}

async function getVerificationScreenshotClip(page) {
  const geometry = await page.evaluate(() => {
    const normalizeText = (text) => String(text || "").replace(/\s+/g, " ").trim();
    const keywordPattern = /发票查验明细|查验次数|打印|关闭|验证码错误|验证码失效|校验码错误|图片验证码错误|系统异常|请重试|查无此票|信息不一致|不一致|字段不匹配|录入信息有误|超过该张发票当日查验次数|请于次日再次查验/;

    function isVisible(el) {
      if (!el || !el.isConnected) {
        return false;
      }
      const style = window.getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") {
        return false;
      }
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    }

    const candidates = [];
    const seen = new Set();
    for (const el of document.querySelectorAll("body *")) {
      if (!isVisible(el)) {
        continue;
      }
      const rect = el.getBoundingClientRect();
      if (rect.width < 120 || rect.height < 60) {
        continue;
      }
      const text = normalizeText(el.innerText || el.textContent);
      if (!text || !keywordPattern.test(text)) {
        continue;
      }
      const key = `${Math.round(rect.x)}:${Math.round(rect.y)}:${Math.round(rect.width)}:${Math.round(rect.height)}:${text.slice(0, 80)}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      candidates.push({
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        text,
      });
      if (candidates.length >= 30) {
        break;
      }
    }

    return {
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
      },
      candidates,
    };
  });

  return selectBestScreenshotClip(geometry?.candidates || [], geometry?.viewport || null);
}

async function collectVerificationSignals(page) {
  const signals = await page.evaluate(() => {
    const normalizeText = (text) => String(text || "").replace(/\s+/g, " ").trim();
    const keywordPattern = /发票查验明细|查验次数|打印|关闭|验证码错误|验证码失效|校验码错误|图片验证码错误|查无此票|信息不一致|不一致|字段不匹配|录入信息有误|发票号码|开票日期|价税合计|发票查验说明|首次查验前请点此安装根证书|查验成功|相符|超过该张发票当日查验次数|请于次日再次查验|超过.*查验次数/;

    function isVisible(el) {
      if (!el || !el.isConnected) {
        return false;
      }
      const style = window.getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") {
        return false;
      }
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    }

    const bodyText = normalizeText(document.body?.innerText || document.body?.textContent || "");
    const popupTexts = [];
    const visibleKeywordCandidates = [];
    const seen = new Set();
    const popupSelectors = [
      "dialog",
      "[role='dialog']",
      "#popup_container",
      ".popup",
      ".modal",
      ".ui-dialog",
      ".layui-layer",
      ".layui-layer-content",
    ];

    const pushText = (text) => {
      const normalized = normalizeText(text);
      if (!normalized || seen.has(normalized)) {
        return;
      }
      seen.add(normalized);
      popupTexts.push(normalized);
    };
    const pushVisibleText = (text) => {
      const normalized = normalizeText(text);
      if (!normalized || seen.has(`visible:${normalized}`)) {
        return;
      }
      seen.add(`visible:${normalized}`);
      visibleKeywordCandidates.push(normalized);
    };

    for (const selector of popupSelectors) {
      for (const el of document.querySelectorAll(selector)) {
        if (!isVisible(el)) {
          continue;
        }
        const text = normalizeText(el.innerText || el.textContent);
        if (text && keywordPattern.test(text)) {
          pushText(text);
        }
      }
    }

    for (const el of document.querySelectorAll("body *")) {
      if (!isVisible(el)) {
        continue;
      }
      const text = normalizeText(el.innerText || el.textContent);
      if (!text || text.length > 2500) {
        continue;
      }
      if (keywordPattern.test(text)) {
        pushVisibleText(text);
      }
    }

    return {
      bodyText,
      popupTexts,
      visibleKeywordCandidates,
    };
  });
  signals.popupTexts.push(...(page.verificationDialogs || []).map(d => d.message));
  // 真实结果可能在可见iframe内，直接读取，避免等待后再调用模型猜结果。
  if (typeof page.frames === "function") {
    for (const frame of page.frames()) {
      if (frame === page.mainFrame()) continue;
      const element = await frame.frameElement().catch(() => null);
      if (!element || !await element.isVisible().catch(() => false)) continue;
      const text = await frame.locator("body").innerText().catch(() => "");
      if (text) signals.popupTexts.push(text);
    }
  }
  return signals;
}

function normalizeCollectedSignals(signals) {
  return {
    bodyText: signals?.bodyText || "",
    popupTexts: Array.isArray(signals?.popupTexts) ? signals.popupTexts : [],
    visibleKeywordTexts: selectVisibleKeywordTexts(signals?.visibleKeywordTexts || signals?.visibleKeywordCandidates || []),
  };
}

async function waitForVerificationOutcome(page, timeoutMs = 15000, intervalMs = 300) {
  const deadline = Date.now() + timeoutMs;
  let latestSignals = normalizeCollectedSignals(await collectVerificationSignals(page));
  let latestClassification = classifyVerificationSignals(latestSignals);

  while (Date.now() < deadline) {
    if (page.trafficGuard) await page.trafficGuard.check(page);
    latestSignals = normalizeCollectedSignals(await collectVerificationSignals(page));
    latestClassification = classifyVerificationSignals(latestSignals);

    if (["success", "daily_limit_exceeded", "data_mismatch", "captcha_error"].includes(latestClassification.status)) {
      return {
        signals: latestSignals,
        classified: latestClassification,
      };
    }

    if (page.submissionTrace?.requests?.some(r => r.failure || (r.response_status !== null && r.response_status >= 400))) break;
    await page.waitForTimeout(intervalMs);
  }

  latestSignals = normalizeCollectedSignals(await collectVerificationSignals(page));
  latestClassification = classifyVerificationSignals(latestSignals);

  return {
    signals: latestSignals,
    classified: latestClassification,
  };
}

function resolveVerificationAmount(pageText, record) {
  // 增值税电子普通发票不需要填写金额，只需校验码
  if (record.invoice_type && record.invoice_type.includes("增值税电子普通发票")) {
    return { type: "none", value: null };
  }
  // 电子发票（普通发票）使用价税合计
  if (record.invoice_type && record.invoice_type.includes("电子发票")) {
    return {
      type: "total_amount",
      value: record.total_amount,
    };
  }
  // 增值税发票根据页面提示判断
  if (String(pageText || "").includes("价税合计") && record.total_amount) {
    return {
      type: "total_amount",
      value: record.total_amount,
    };
  }
  return {
    type: "pretax_amount",
    value: record.pretax_amount,
  };
}

function detectCaptchaRule(pageText) {
  const text = String(pageText || "");
  if (text.includes("请输入验证码图片中红色文字")) {
    return "red_text";
  }
  if (text.includes("请输入验证码图片中蓝色文字")) {
    return "blue_text";
  }
  if (text.includes("请输入验证码文字")) {
    return "full_text";
  }
  return "unknown";
}

function captchaRuleDisplay(rule, promptText) {
  if (rule === "red_text") {
    return "请输入验证码图片中红色文字";
  }
  if (rule === "blue_text") {
    return "请输入验证码图片中蓝色文字";
  }
  if (rule === "full_text") {
    return "请输入验证码文字";
  }
  const compactPrompt = String(promptText || "").replace(/\s+/g, " ").trim();
  return compactPrompt || "未识别到明确验证码规则";
}

async function readCaptchaPromptText(page) {
  return page.evaluate(() => {
    // Find the VISIBLE captcha input (page may have duplicate hidden forms)
    const candidates = [
      ...document.querySelectorAll(".t-form-item__yzm input"),
      ...document.querySelectorAll("#yzm"),
      ...document.querySelectorAll("input[name='yzm']"),
      ...document.querySelectorAll("input[placeholder*='验证码']"),
    ];
    let input = null;
    for (const el of candidates) {
      const rect = el.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        input = el;
        break;
      }
    }
    if (!input && candidates.length > 0) {
      input = candidates[0];
    }
    if (!input) {
      return "";
    }

    const nodes = [
      input.closest(".t-form-item__yzm")?.parentElement,
      input.parentElement,
      input.closest("td"),
      input.closest("tr"),
      input.closest("tbody"),
      input.closest("table"),
    ].filter(Boolean);

    const seen = new Set();
    const texts = [];
    for (const node of nodes) {
      if (seen.has(node)) {
        continue;
      }
      seen.add(node);
      const text = String(node.innerText || "").trim();
      if (text) {
        texts.push(text);
      }
    }
    return texts.join("\n").match(/请输入验证码(?:图片中\s*(?:红色|蓝色)\s*文字|文字)/)?.[0] || "";
  });
}

function preprocessCaptchaImages(imageBuffer, artifactsDir, screenshotBase, attempt, captchaRetry = 0) {
  const retrySuffix = captchaRetry > 0 ? `-retry-${captchaRetry}` : "";
  const originalPath = path.join(artifactsDir, `${screenshotBase}-attempt-${attempt}${retrySuffix}-captcha-original.png`);
  fs.writeFileSync(originalPath, imageBuffer);

  const paths = {
    original: originalPath,
  };

  return paths;
}

async function collectCaptchaCandidates(captchaBuffer, promptText) {
  // Single call to vision model
  return await captureCaptchaWithVisionModel(captchaBuffer, promptText);
}

async function refreshCaptcha(page, captchaImage) {
  if (page.trafficGuard) await page.trafficGuard.wait("refresh");
  // 先强制关闭所有弹窗
  await forceCloseDialogs(page);
  await captchaImage.click({ force: true });
  await page.waitForTimeout(600);
}

async function waitForSubmitButton(page, timeout = 5000) {
  // The website has two buttons: #uncheckfp (gray, always visible) and
  // #checkfp (blue, hidden until all 4 fields pass validation).
  // Wait for #checkfp to become visible after form is filled.
  try {
    const button = typeof page.url === "function" && page.url().includes("/fpcygzfw/")
      ? page.getByRole("button", { name: /^查\s*验$/ }) : page.locator("#checkfp");
    await button.waitFor({ state: "visible", timeout });
    return button;
  } catch (_) {
    return null;
  }
}

async function acknowledgeCaptchaError(page) {
  const messages = page.getByText(/^(?:图片)?验证码(?:错误|失效)[！!。]?$/);
  let message;
  for (let i = 0; i < await messages.count(); i++) {
    const candidate = messages.nth(i);
    if (await candidate.isVisible().catch(() => false)) { message = candidate; break; }
  }
  if (!message) return false;
  // 新版TDesign Message是自动消失的提示条，不存在“确定”按钮。
  const isToast = await message.evaluate(el => Boolean(el.closest('.t-message')) &&
    !el.closest('[role="dialog"], .t-dialog, #popup_container'));
  if (isToast) {
    await message.waitFor({ state: "hidden", timeout: 10000 });
    return true;
  }
  const dialog = message.locator('xpath=ancestor::*[@role="dialog" or @id="popup_container" or contains(concat(" ",normalize-space(@class)," ")," t-dialog ")][1]');
  const scope = await dialog.count() ? dialog : page;
  const buttons = [scope.getByRole("button", { name: /^\s*确定\s*$/ }),
    scope.getByText("确定", { exact: true })];
  for (const candidates of buttons) {
    for (let i = 0; i < await candidates.count(); i++) {
      const button = candidates.nth(i);
      if (!await button.isVisible().catch(() => false)) continue;
      await button.click({timeout:8000});
      await message.waitFor({ state: "hidden", timeout: 5000 });
      return true;
    }
  }
  throw new Error("验证码错误提示不属于自动消失的提示条，且没有可点击的确定按钮；保留现场停止。");
}

async function forceCloseDialogs(page) {
  if (page.trafficGuard) await page.trafficGuard.check(page);
  // 点击确定执行网站回调；保留无法确认的异常现场。
  await acknowledgeCaptchaError(page);
  await page.waitForTimeout(200);
}

async function enlargeCaptchaForModel(page, buffer) {
  return Buffer.from(await page.evaluate(async base64 => {
    const img = new Image();
    img.src = "data:image/png;base64," + base64;
    await img.decode();
    const canvas = document.createElement("canvas");
    canvas.width = img.naturalWidth * 4;
    canvas.height = img.naturalHeight * 4;
    const context = canvas.getContext("2d");
    context.imageSmoothingEnabled = false;
    context.drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/png").split(",")[1];
  }, buffer.toString("base64")), "base64");
}

async function readCaptchaChallenge(page, record, artifactsDir, screenshotBase, attempt, captchaRetry = 0, lastCaptchaHash = null) {
  // 先完成实际提交间隔等待，再获取当前验证码；等待后的图片不能沿用旧截图。
  if (page.trafficGuard) {
    const waited = await page.trafficGuard.wait("submit");
    await page.trafficGuard.check(page);
    if (waited > 0) await refreshCaptcha(page, await findCaptchaImage(page));
  }
  const pageText = await page.locator("body").innerText();
  const promptText = await readCaptchaPromptText(page);
  const amountInfo = resolveVerificationAmount(pageText, record);
  const captchaRule = isPlainCaptchaPrompt(promptText) ? "full_text" : "unknown";
  const captchaImage = await findCaptchaImage(page);
  await captchaImage.waitFor({ state: "visible", timeout: 15000 });
  let captchaBuffer = await captchaImage.screenshot();

  // 检测验证码图片是否真的刷新了：对比 hash，如果和上次一样则强制点击刷新
  let currentHash = crypto.createHash("md5").update(captchaBuffer).digest("hex");
  if (lastCaptchaHash && currentHash === lastCaptchaHash) {
    console.log(`[captcha] Image unchanged (hash=${currentHash.slice(0, 8)}), forcing refresh...`);
    for (let refreshAttempt = 0; refreshAttempt < 3; refreshAttempt++) {
      await refreshCaptcha(page, captchaImage);
      await page.waitForTimeout(800);
      captchaBuffer = await captchaImage.screenshot();
      const newHash = crypto.createHash("md5").update(captchaBuffer).digest("hex");
      if (newHash !== currentHash) {
        currentHash = newHash;
        console.log(`[captcha] Image refreshed successfully (new hash=${newHash.slice(0, 8)})`);
        break;
      }
      console.log(`[captcha] Refresh attempt ${refreshAttempt + 1} failed, image still unchanged`);
    }
  }

  const capturedAt = nowIso();
  // 刷新图片后重新读提示，避免旧提示与新图片组合。
  const currentPrompt = await readCaptchaPromptText(page);
  const ready = isPlainCaptchaPrompt(currentPrompt);
  // 不对颜色筛选或未知提示调用模型。
  const preprocessed = ready ? preprocessCaptchaImages(captchaBuffer, artifactsDir, screenshotBase, attempt, captchaRetry) : { original: null };
  let ocrBuffer = captchaBuffer;
  let ocrImagePath = preprocessed.original;
  if (ready && process.env.CAPTCHA_MODEL_IMAGE_SCALE === "4") {
    ocrBuffer = await enlargeCaptchaForModel(page, captchaBuffer);
    ocrImagePath = preprocessed.original.replace(/-original\.png$/, "-model-4x.png");
    fs.writeFileSync(ocrImagePath, ocrBuffer);
  }

  let candidateBundle = { primaryCaptcha: "", alternativeCaptchas: [] };
  if (ready) {
    if (page.trafficGuard) await page.trafficGuard.check(page);
    try {
      candidateBundle = await collectCaptchaCandidates(ocrBuffer, currentPrompt);
    } catch (error) {
      if (!error.retryable) throw error;
      candidateBundle.confidenceNote = error.message;
      candidateBundle.rejectionReason = "model_transient_error";
    }
  }
  const captchaCandidates = [candidateBundle.primaryCaptcha, ...candidateBundle.alternativeCaptchas].filter(Boolean);
  if (captchaCandidates.length && Number.isInteger(page.invoiceOcrAttempts)) page.invoiceOcrAttempts++;
  return {
    pageText,
    promptText: currentPrompt,
    captchaRuleDisplay: captchaRuleDisplay(ready ? "full_text" : "unknown", currentPrompt),
    amountInfo,
    captchaRule: ready ? "full_text" : "unknown",
    captchaImage,
    imagePaths: { original: preprocessed.original, ocr_used: ocrImagePath, ...preprocessed },
    candidateBundle,
    captchaCandidates,
    captchaHash: currentHash,
    capturedAt,
    recognizedAt: ready ? nowIso() : null,
  };
}

async function verifySingleInvoice(page, record, artifactsDir, maxCaptchaAttempts) {
  installSubmissionTrace(page);
  const screenshotBase = slugify(`${record.invoice_number}-${record.invoice_date}`);
  const fieldSelectors = {
    invoice_code: ["#fpdm", "input[name='fpdm']", "input[placeholder*='发票代码']"],
    invoice_number: ["#fphm", "input[name='fphm']", "input[placeholder*='发票号码']"],
    invoice_date: ["#kprq", "input[name='kprq']", "input[placeholder*='开票日期']"],
    pretax_amount: ["#kjje", "input[name='kjje']", "input[placeholder*='开具金额']", "input[placeholder*='金额']"],
    captcha: ["#yzm", "input[name='yzm']", "input[placeholder*='验证码']"],
  };

  for (const [key, selector] of Object.entries(MODERN_FIELDS)) fieldSelectors[key].unshift(selector);

  for (let attempt = 1; attempt <= 1; attempt += 1) {
    await forceCloseDialogs(page);
    page.captchaNetwork = [];
    if (!page.reuseInvoicePage) await page.goto(VERIFY_URL, { waitUntil: "domcontentloaded", timeout: 30000 });
    page.reuseInvoicePage = false;
    await page.waitForSelector(MODERN_FIELDS.invoice_number, { state: "visible", timeout: 30000 });
    await page.waitForTimeout(1000);

    // 页面加载后先关闭所有弹窗
    await forceCloseDialogs(page);
    try {
      await page.keyboard.press("Escape");
      await page.waitForTimeout(300);
    } catch (_) {}

    // 检测并跳过根证书引导页
    try {
      const pageText = await page.locator("body").innerText();
      if (/首次查验前请点此安装根证书|您使用的是.*浏览器.*请参照操作说明安装根证书/.test(pageText)) {
        const clickSelectors = [
          "text=查验",
          "text=发票查验说明",
          "a:has-text('查验')",
          "button:has-text('查验')",
        ];
        for (const selector of clickSelectors) {
          try {
            const el = page.locator(selector).first();
            if (await el.isVisible({ timeout: 1000 }).catch(() => false)) {
              await el.click({ force: true });
              await page.waitForTimeout(1500);
              break;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 再次关闭弹窗（根证书引导可能触发 dialog）
    await forceCloseDialogs(page);

    // 填写发票代码（电子发票无发票代码，跳过）
    // 增值税电子普通发票：填写发票代码后，表单会动态将"开具金额"变为"校验码"
    const isEInvoice = record.invoice_type && record.invoice_type.includes("增值税电子普通发票");
    if (record.invoice_code) {
      await fillField(page, record.invoice_code, fieldSelectors.invoice_code, "invoice_code");
      if (isEInvoice) {
        // 等待表单动态变化：标签从"开具金额"变为"校验码"
        await page.waitForTimeout(1500);
      } else {
        await page.waitForTimeout(300);
      }
    }

    // 填写发票号码
    await fillField(page, record.invoice_number, fieldSelectors.invoice_number, "invoice_number");
    await page.waitForTimeout(500);

    // 读取页面信息，确定金额类型（价税合计 vs 开具金额）
    const pageText = await page.locator("body").innerText();
    const promptText = await readCaptchaPromptText(page);
    const amountInfo = resolveVerificationAmount(pageText, record);

    // 填写日期
    const dateValue = normalizeDateForForm(record.invoice_date);
    await fillField(page, dateValue, fieldSelectors.invoice_date, "invoice_date");

    // 增值税电子普通发票：校验码填入 #kjje（填发票代码后标签已变为"校验码"）
    // 其他发票类型：填写金额
    if (isEInvoice && record.check_code) {
      await fillField(page, record.check_code, fieldSelectors.pretax_amount, "check_code");
    } else if (amountInfo.value) {
      await fillField(page, amountInfo.value, fieldSelectors.pretax_amount, "pretax_amount");
    }

    await page.locator("body").click({ position: { x: 10, y: 10 } });
    await page.waitForTimeout(1000); // 等待验证码图片加载

    // 关闭填表后可能弹出的 <dialog>（根证书提示等）
    await forceCloseDialogs(page);

    // 新版默认占位图不能拿去OCR；接口失败时保留诊断并停止批次。
    try {
      if (typeof page.url === "function" && page.url().includes("/fpcygzfw/")) await page.waitForFunction(() => {
        const img = document.querySelector('img[width="120"][height="50"]');
        return img && img.complete && img.naturalWidth > 0 && !/\/code\.[^/]+\.png/.test(img.getAttribute('src') || '');
      }, null, { timeout: 15000 });
    } catch (error) {
      if (error.name !== 'TimeoutError') throw error;
      const screenshot = path.join(artifactsDir, `${screenshotBase}-captcha-unavailable.png`);
      await page.screenshot({path:screenshot,fullPage:true});
      return { invoice_key:buildInvoiceKey(record), verification_status:'website_system_error',
        verification_message:'新版验证码接口未返回有效图片，等待刷新重试',
        failure_reason:'modern_captcha_unavailable',captcha_attempts:0,verified_at:nowIso(),
        result_screenshot:screenshot,captcha_network:page.captchaNetwork || [] };
    }

    // 验证码识别重试循环：最多提交 3 次 full_text 验证码
    const maxFullTextAttempts = Math.min(maxCaptchaAttempts, MAX_FULL_TEXT_ATTEMPTS);
    let challenge = null;
    let fullTextAttempts = 0;
    let captchaRetryCount = 0;
    const maxRefreshRetries = MAX_REFRESH_RETRIES; // 最多刷新验证码的次数，防止无限循环
    const captchaRetryHistory = []; // 记录每次重试的结果
    let lastCaptchaHash = null; // 追踪上一次验证码图片 hash，检测是否真正刷新

    while (fullTextAttempts < maxFullTextAttempts && captchaRetryCount < maxRefreshRetries) {
      // 读取验证码（传入上次 hash 以检测图片是否真正刷新）
      challenge = await readCaptchaChallenge(
        page,
        record,
        artifactsDir,
        screenshotBase,
        attempt,
        captchaRetryCount,
        lastCaptchaHash
      );
      lastCaptchaHash = challenge.captchaHash;

      const captchaRule = challenge.captchaRule;
      const captchaCandidates = challenge.captchaCandidates;
      const imagePaths = challenge.imagePaths;
      const candidateBundle = challenge.candidateBundle;

      // 如果是 unknown 规则，刷新验证码继续等待有效类型（不计入提交次数）
      if (captchaRule === "unknown") {
        console.log(`[captcha] Detected ${captchaRule}, refreshing to get a known captcha type`);
        captchaRetryCount++;
        await refreshCaptcha(page, challenge.captchaImage);
        await page.waitForTimeout(1000);
        lastCaptchaHash = null; // 重置 hash，下次循环允许任意验证码图片
        continue;
      }

      // full_text：记录本次重试结果
      const retryResult = {
        retry: captchaRetryCount,
        valid_attempt: captchaCandidates.length ? fullTextAttempts + 1 : null,
        captcha_rule: captchaRule,
        captcha_rule_display: challenge.captchaRuleDisplay,
        captcha_hint_text: challenge.promptText,
        captcha_candidates: captchaCandidates,
        captcha_image_path: imagePaths.original,
        captcha_preprocessed_path: imagePaths.ocr_used || imagePaths.original,
        confidence_note: candidateBundle?.confidenceNote || null,
        candidate_origins: candidateBundle?.candidateOrigins || [],
        model_raw_output: candidateBundle?.rawOutput ?? null,
        content_check: candidateBundle?.contentCheck || null,
        rejection_reason: candidateBundle?.rejectionReason || null,
        captured_at: challenge.capturedAt || null,
        recognized_at: challenge.recognizedAt || null,
        submitted_at: null,
        outcome: captchaCandidates.length ? "ready_to_submit" : "recognition_rejected",
      };
      captchaRetryHistory.push(retryResult);

      if (captchaCandidates.length === 0) {
        // 空回答、UNKNOWN和说明文字不消耗有效候选的3次预算。
        captchaRetryCount++;
        await refreshCaptcha(page, challenge.captchaImage);
        await page.waitForTimeout(1000);
        lastCaptchaHash = null;
        continue;
      }

      // 模型返回时再次校验图片和提示，避免后台异步刷新造成旧答案提交。
      const liveImage = await findCaptchaImage(page);
      const liveHash = crypto.createHash("md5").update(await liveImage.screenshot()).digest("hex");
      const livePrompt = await readCaptchaPromptText(page);
      if (liveHash !== challenge.captchaHash || !isPlainCaptchaPrompt(livePrompt)) {
        retryResult.outcome = "challenge_changed_before_submit";
        retryResult.rejection_reason = "challenge_changed_before_submit";
        retryResult.valid_attempt = null;
        if (Number.isInteger(page.invoiceOcrAttempts)) page.invoiceOcrAttempts--;
        captchaRetryCount++;
        lastCaptchaHash = null;
        continue;
      }
      // 填写验证码
      await fillField(page, captchaCandidates[0], fieldSelectors.captcha, "captcha");
      // 等待网站 JS 验证所有字段并激活蓝色查验按钮
      const submitButton = await waitForSubmitButton(page, 5000);
      if (!submitButton) {
        const blockedScreenshot = path.join(artifactsDir, `${screenshotBase}-attempt-${attempt}-form-not-activated.png`);
        await page.screenshot({ path: blockedScreenshot, fullPage: true });
        return {
          invoice_key: buildInvoiceKey(record),
          verification_status: "verification_form_not_activated",
          verification_message: "form validation did not activate the live verify button",
          captcha_attempts: Math.min(fullTextAttempts + 1, maxFullTextAttempts),
          captcha_rule: captchaRule,
          captcha_rule_display: challenge.captchaRuleDisplay,
          captcha_hint_text: challenge.promptText,
          captcha_candidates: captchaCandidates,
          captcha_image_path: imagePaths.original,
          captcha_preprocessed_path: imagePaths.ocr_used || imagePaths.original,
          captcha_retry_history: captchaRetryHistory,
          verified_at: nowIso(),
          verification_amount_type: amountInfo.type,
          verification_amount_used: amountInfo.value,
          result_screenshot: blockedScreenshot,
          result_text: challenge.pageText.slice(0, 3000),
        };
      }
      if (page.trafficGuard) {
        await page.trafficGuard.check(page);
      }
      page.verificationDialogs = [];
      page.submissionTrace = { started_at: nowIso(), requests: [] };
      await clickVerificationButton(page, submitButton);
      if (page.trafficGuard) page.trafficGuard.markSubmitted();
      retryResult.submitted_at = nowIso();
      retryResult.outcome = "submitted";

      const outcome = await waitForVerificationOutcome(page);
      let classified = outcome.classified;
      let verificationSignals = outcome.signals;

      if (shouldRetryVerificationStatus(classified.status)) {
        await page.waitForTimeout(800);
        const confirmSignals = normalizeCollectedSignals(await collectVerificationSignals(page));
        const confirmClassified = classifyVerificationSignals(confirmSignals);
        if (!shouldRetryVerificationStatus(confirmClassified.status)) {
          verificationSignals = confirmSignals;
          classified = confirmClassified;
        }
      }

      const screenshotPath = path.join(artifactsDir, `${screenshotBase}-attempt-${attempt}-retry-${captchaRetryCount}-result.png`);
      await page.screenshot({ path: screenshotPath, fullPage: true });
      let modalScreenshotPath = null;
      const screenshotClip = await getVerificationScreenshotClip(page);
      if (screenshotClip) {
        modalScreenshotPath = path.join(
          artifactsDir,
          `${screenshotBase}-attempt-${attempt}-retry-${captchaRetryCount}-modal.png`
        );
        await page.screenshot({
          path: modalScreenshotPath,
          clip: screenshotClip,
        });
      }

      if (shouldRetryVerificationStatus(classified.status)) {
        const postScreenshotSignals = normalizeCollectedSignals(await collectVerificationSignals(page));
        const postScreenshotClassified = classifyVerificationSignals(postScreenshotSignals);
        if (!shouldRetryVerificationStatus(postScreenshotClassified.status)) {
          verificationSignals = postScreenshotSignals;
          classified = postScreenshotClassified;
        }
      }

      let screenshotFallback = null;
      if (classified.status === "form_still_active" && !page._submissionTraceInstalled) {
        try {
          const modalFallback = modalScreenshotPath
            ? await classifyVerificationScreenshot(modalScreenshotPath)
            : null;
          const fullPageFallback = shouldRunFullPageScreenshotFallback(modalFallback?.classified || null)
            ? await classifyVerificationScreenshot(screenshotPath)
            : null;
          const resolvedFallback = resolveScreenshotFallbackClassification(classified, [
            modalFallback ? { source: "modal", ...modalFallback } : null,
            fullPageFallback ? { source: "full_page", ...fullPageFallback } : null,
          ]);

          screenshotFallback = {
            modal: modalFallback,
            fullPage: fullPageFallback,
            outputs: resolvedFallback.outputs,
            appliedSource: resolvedFallback.appliedSource,
          };
          classified = resolvedFallback.classification || classified;
        } catch (error) {
          screenshotFallback = {
            modal: null,
            fullPage: null,
            rawOutput: `screenshot_fallback_error: ${error.message}`,
          };
        }
      }

      // 更新本次重试历史中的结果截图
      if (captchaRetryHistory.length > 0) {
        const latestRetry = captchaRetryHistory[captchaRetryHistory.length - 1];
        latestRetry.result_screenshot = screenshotPath;
        latestRetry.platform_status = classified.status;
        latestRetry.platform_message = classified.matchedText || classified.message;
        latestRetry.native_dialogs = [...(page.verificationDialogs || [])];
        latestRetry.submission_trace = page.submissionTrace || null;
        if (classified.status === "form_still_active" && page._submissionTraceInstalled) {
          classified = { status: "request_error", message: submissionFailure(page.submissionTrace) };
        }
        latestRetry.outcome = classified.status === "captcha_error" ? "captcha_rejected" : classified.status;
      }

      if (shouldRetryVerificationStatus(classified.status)) {
        fullTextAttempts++;
        captchaRetryCount++;
        // 确认错误弹窗，触发网站的原有恢复逻辑；不能直接删除弹窗DOM。
        if (classified.status === "captcha_error") await acknowledgeCaptchaError(page);
        if (fullTextAttempts >= maxFullTextAttempts) break;
        // 网站在提交后可能清空表单字段，重新填写所有字段
        await forceCloseDialogs(page);
        if (record.invoice_code) {
          await fillField(page, record.invoice_code, fieldSelectors.invoice_code, "invoice_code");
          if (isEInvoice) {
            await page.waitForTimeout(1500);
          } else {
            await page.waitForTimeout(300);
          }
        }
        await fillField(page, record.invoice_number, fieldSelectors.invoice_number, "invoice_number");
        await page.waitForTimeout(300);
        await fillField(page, dateValue, fieldSelectors.invoice_date, "invoice_date");
        if (isEInvoice && record.check_code) {
          await fillField(page, record.check_code, fieldSelectors.pretax_amount, "check_code");
        } else if (amountInfo.value) {
          await fillField(page, amountInfo.value, fieldSelectors.pretax_amount, "pretax_amount");
        }
        await page.waitForTimeout(500);
        // 使用新的验证码图片定位器（旧的可能在提交后失效）
        const freshCaptchaImage = await findCaptchaImage(page);
        await refreshCaptcha(page, freshCaptchaImage);
        await page.waitForTimeout(1000);
        lastCaptchaHash = null; // 重置 hash，允许下次循环接受刷新后的新验证码
        continue;
      }

      // 成功或page_variant_changed，直接返回
      return {
        invoice_key: buildInvoiceKey(record),
        verification_status: classified.status,
        verification_message: classified.message,
        failure_reason: classified.status === "request_error" ? classified.message : null,
        captcha_attempts: Math.min(fullTextAttempts + 1, maxFullTextAttempts),
        captcha_rule: captchaRule,
        captcha_rule_display: challenge.captchaRuleDisplay,
        captcha_hint_text: challenge.promptText,
        captcha_candidates: captchaCandidates,
        captcha_image_path: imagePaths.original,
        captcha_preprocessed_path: imagePaths.ocr_used || imagePaths.original,
        captcha_retry_history: captchaRetryHistory,
        verified_at: nowIso(),
        verification_amount_type: amountInfo.type,
        verification_amount_used: amountInfo.value,
        result_screenshot: screenshotPath,
        result_text: [
          `captcha_hint_text: ${challenge.promptText}`,
          `captcha_confidence: ${candidateBundle.confidenceNote || "n/a"}`,
          `captcha_origins: ${candidateBundle?.candidateOrigins?.join(", ") || "n/a"}`,
          `matched_status_signal: ${normalizeSignalText(classified.matchedText).slice(0, 500)}`,
          `screenshot_fallback_applied: ${screenshotFallback?.appliedSource || "n/a"}`,
          `screenshot_fallback_modal: ${screenshotFallback?.outputs?.modal || screenshotFallback?.modal?.rawOutput || "n/a"}`,
          `screenshot_fallback_full: ${screenshotFallback?.outputs?.full_page || screenshotFallback?.fullPage?.rawOutput || screenshotFallback?.rawOutput || "n/a"}`,
          `signal_summary: ${buildVerificationSignalSummary(verificationSignals)}`,
          verificationSignals.popupTexts.join("\n---\n").slice(0, 3000),
          (verificationSignals.visibleKeywordTexts || []).join("\n---\n").slice(0, 3000),
          verificationSignals.bodyText.slice(0, 3000),
        ].join("\n"),
      };
    }

    const exhaustionOutcome = resolveCaptchaExhaustion({
      attempt,
      maxCaptchaAttempts: 1,
      record,
      challenge,
      captchaRetryHistory,
      amountInfo,
      fullTextAttempts,
      maxFullTextAttempts,
      maxRefreshRetries,
    });
    if (exhaustionOutcome.action === "retry_page") {
      continue;
    }
    return exhaustionOutcome.result;
  }

  return resolveCaptchaExhaustion({
    attempt: maxCaptchaAttempts,
    maxCaptchaAttempts,
    record,
    challenge: null,
    captchaRetryHistory: [],
    amountInfo: null,
    fullTextAttempts: 0,
    maxFullTextAttempts: 0,
    maxRefreshRetries: 0,
  }).result;
}

async function main() {
  const args = parseArgs(process.argv);

  ensureDir(args.artifactsDir);
  ensureDir(path.dirname(args.outputJson));

  const extractionPayload = loadJson(args.inputJson);
  const records = extractionPayload.records || [];
  const uniqueRecords = new Map();
  const resultsByKey = {};

  for (const record of records) {
    const invoiceKey = buildInvoiceKey(record);
    if (!invoiceKey) {
      const message = record.extraction_status === "no_invoice_detected"
        ? (record.extraction_message || "page does not contain a VAT invoice")
        : "missing required fields for website verification";
      resultsByKey[record.record_id] = createSkippedResult(
        record,
        message
      );
      continue;
    }
    if (record.extraction_status !== "success" && record.extraction_status !== "missing_fields") {
      resultsByKey[invoiceKey] = createSkippedResult(record, record.extraction_message || "extraction failed");
      continue;
    }
    if (record.extraction_status === "missing_fields") {
      resultsByKey[invoiceKey] = createSkippedResult(record, record.extraction_message || "missing verification fields");
      continue;
    }
    if (!uniqueRecords.has(invoiceKey)) {
      uniqueRecords.set(invoiceKey, record);
    }
  }

  // 优先启动独立的 Chrome（使用用户配置），其次 Firefox，最后用 Chromium
  let context = null;
  let shouldCloseBrowser = true;

  const userDataDir = process.env.CHROME_USER_DATA_DIR ||
    (process.platform === "darwin" ? `${process.env.HOME}/Library/Application Support/Google/Chrome` : null);

  try {
    const { chromium } = await requirePlaywright();

    // 使用 launchPersistentContext 来使用用户配置文件
    if (userDataDir) {
      try {
        console.log("[browser] Trying to launch Chrome with user profile...");
        context = await chromium.launchPersistentContext(userDataDir, {
          headless: true,
          ignoreHTTPSErrors: true,
          userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        });
        console.log("[browser] Using Chrome with user profile");
        shouldCloseBrowser = true;
      } catch (launchError) {
        console.log(`[browser] Chrome user profile launch failed: ${launchError.message}`);
        context = null;
      }
    }

    // 如果 Chrome 失败，尝试 Firefox
    if (!context) {
      try {
        const { firefox } = await requirePlaywright();
        const browser = await firefox.launch({ headless: true });
        context = await browser.newContext({
          ignoreHTTPSErrors: true,
          userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0",
        });
        shouldCloseBrowser = true;
        console.log("[browser] Using Firefox");
      } catch (firefoxError) {
        console.log(`[browser] Firefox launch failed: ${firefoxError.message}`);
        context = null;
      }
    }

    // 最后尝试普通 Chromium
    if (!context) {
      console.log("[browser] Falling back to Chromium...");
      const { chromium: chromiumFallback } = await requirePlaywright();
      const browser = await chromiumFallback.launch({ headless: true });
      context = await browser.newContext({
        ignoreHTTPSErrors: true,
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      });
      shouldCloseBrowser = true;
    }
  } catch (error) {
    console.log(`[browser] All browser launch attempts failed: ${error.message}`);
    throw error;
  }

  try {
    for (const [invoiceKey, record] of uniqueRecords.entries()) {
      const page = await context.newPage();
      try {
        const result = await Promise.race([
          verifySingleInvoice(
            page,
            record,
            args.artifactsDir,
            args.maxCaptchaAttempts
          ),
          new Promise((_, reject) =>
            setTimeout(
              () => reject(new Error(`verifySingleInvoice timed out after ${VERIFY_SINGLE_INVOICE_TIMEOUT_MS / 1000}s`)),
              VERIFY_SINGLE_INVOICE_TIMEOUT_MS
            )
          ),
        ]);
        resultsByKey[invoiceKey] = result;
      } catch (error) {
        const screenshotPath = path.join(args.artifactsDir, `${slugify(invoiceKey)}-script-error.png`);
        try {
          await page.screenshot({ path: screenshotPath, fullPage: true });
        } catch (_) {
          // Ignore screenshot failures.
        }
        resultsByKey[invoiceKey] = {
          invoice_key: invoiceKey,
          verification_status: "script_error",
          verification_message: String(error.message || error),
          captcha_attempts: 0,
          captcha_rule: null,
          captcha_rule_display: null,
          captcha_candidates: [],
          captcha_image_path: null,
          captcha_preprocessed_path: null,
          verified_at: nowIso(),
          verification_amount_type: null,
          verification_amount_used: null,
          result_screenshot: fs.existsSync(screenshotPath) ? screenshotPath : null,
          result_text: null,
        };
      } finally {
        await page.close();
      }
    }
  } finally {
    if (shouldCloseBrowser && context) {
      await context.browser().close();
    }
  }

  const output = {
    generated_at: nowIso(),
    source_file: args.inputJson,
    results_by_key: resultsByKey,
  };
  fs.writeFileSync(args.outputJson, `${JSON.stringify(output, null, 2)}\n`, "utf-8");
  console.log(`Wrote verification results to ${args.outputJson}`);
}

if (require.main === module) main().catch((error) => {
  console.error(`[verify_invoices] ${error.stack || error.message || error}`);
  process.exit(1);
});

module.exports = { parseArgs, buildCaptchaPrompt, readCaptchaChallenge, verifySingleInvoice, acknowledgeCaptchaError, enlargeCaptchaForModel };
