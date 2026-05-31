const assert = require("node:assert/strict");
const test = require("node:test");

const {
  formatTimingLog,
  measureAsync,
} = require("../scripts/timing_logger");

test("formatTimingLog emits stable grep-friendly timing fields", () => {
  assert.equal(
    formatTimingLog("captcha_ocr", 123.7, {
      model: "qwen3.6-plus",
      invoice_key: "|123|2026-03-28|350.00",
      retry: 2,
    }),
    "[timing] stage=captcha_ocr duration_ms=124 model=qwen3.6-plus invoice_key=\"|123|2026-03-28|350.00\" retry=2"
  );
});

test("measureAsync logs timing and preserves async result", async () => {
  const logs = [];
  const result = await measureAsync(
    "page_wait",
    () => Promise.resolve("ok"),
    { status: "success" },
    (message) => logs.push(message),
    () => 1000
  );

  assert.equal(result, "ok");
  assert.equal(logs.length, 1);
  assert.equal(logs[0], "[timing] stage=page_wait duration_ms=0 status=success");
});
