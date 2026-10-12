// DeepSeek official Chat Completions vision API; secrets are read at call time.
function isPlainCaptchaPrompt(text) {
  return String(text || "").replace(/\s+/g, "").trim() === "请输入验证码文字";
}

function parseCaptchaResponse(text) {
  const value = String(text || "").trim();
  // Reject partial answers and explanatory text rather than stripping characters.
  return /^[A-Za-z0-9]{2,8}$/u.test(value) &&
    !/^(UNKNOWN|CHINESE|ERROR|NONE|NULL)$/i.test(value) &&
    !/答案|验证码|无法|识别|字符|文字/.test(value) ? value : "";
}

function buildDeepSeekVisionPayload({ prompt, base64Image, model = "deepseek-flash", maxTokens = 128 }) {
  return {
    model,
    messages: [{ role: "user", content: [
      { type: "text", text: prompt },
      { type: "image_url", image_url: { url: `data:image/png;base64,${base64Image}`, detail: "original" } },
    ] }],
    thinking: { type: "disabled" },
    max_tokens: maxTokens,
  };
}

async function callDeepSeekVision(imageBuffer, prompt, options = {}) {
  const env = options.env || process.env;
  const key = env.DEEPSEEK_API_KEY;
  if (!key || key === "your_deepseek_api_key_here") throw new Error("DEEPSEEK_API_KEY not configured");
  const model = env.DEEPSEEK_CAPTCHA_MODEL || "deepseek-flash";
  const base = (env.DEEPSEEK_BASE_URL || "https://api.deepseek.com").replace(/\/+$/, "");
  if (!base.startsWith("https://")) throw new Error("DEEPSEEK_BASE_URL must use HTTPS");
  let response;
  try {
    response = await (options.fetchImpl || fetch)(`${base}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify(buildDeepSeekVisionPayload({
        prompt, base64Image: imageBuffer.toString("base64"), model, maxTokens: options.maxTokens || 128,
      })),
      signal: AbortSignal.timeout(options.timeoutMs || 30000),
    });
  } catch (_) {
    const error = new Error("DeepSeek request failed or timed out");
    error.retryable = true;
    throw error;
  }
  if (!response.ok) {
    // Do not log server bodies, which may echo credentials or image content.
    const error = new Error(`DeepSeek API HTTP ${response.status}`);
    error.retryable = response.status === 429 || response.status >= 500;
    throw error;
  }
  let data;
  try { data = await response.json(); } catch (_) {
    const error = new Error("DeepSeek returned invalid JSON");
    error.retryable = true;
    throw error;
  }
  const message = data?.choices?.[0]?.message;
  const rawContent = data?.choices?.[0]?.finish_reason === "length" ? "" :
    (typeof message?.content === "string" ? message.content : "");
  return { rawContent, model };
}

module.exports = { isPlainCaptchaPrompt, parseCaptchaResponse, buildDeepSeekVisionPayload, callDeepSeekVision };
