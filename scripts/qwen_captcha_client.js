const QWEN_CAPTCHA_MODEL = process.env.QWEN_CAPTCHA_MODEL || "qwen3.6-plus";

function buildQwenCaptchaPayload({
  prompt,
  base64Image,
  model = QWEN_CAPTCHA_MODEL,
  maxTokens = 20,
}) {
  return {
    model,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image_url",
            image_url: {
              url: `data:image/png;base64,${base64Image}`,
            },
          },
          {
            type: "text",
            text: prompt,
          },
        ],
      },
    ],
    max_tokens: maxTokens,
  };
}

function extractQwenOutputText(responseBody) {
  const content = responseBody?.choices?.[0]?.message?.content;
  return typeof content === "string" ? content : "";
}

module.exports = {
  QWEN_CAPTCHA_MODEL,
  buildQwenCaptchaPayload,
  extractQwenOutputText,
};
