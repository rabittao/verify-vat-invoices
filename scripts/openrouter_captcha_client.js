const OPENROUTER_CAPTCHA_MODEL = process.env.OPENROUTER_CAPTCHA_MODEL || "google/gemini-3-flash-preview";

function buildOpenRouterCaptchaPayload({
  prompt,
  base64Image,
  model = OPENROUTER_CAPTCHA_MODEL,
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

function extractOpenRouterOutputText(responseBody) {
  const content = responseBody?.choices?.[0]?.message?.content;
  return typeof content === "string" ? content : "";
}

module.exports = {
  OPENROUTER_CAPTCHA_MODEL,
  buildOpenRouterCaptchaPayload,
  extractOpenRouterOutputText,
};
