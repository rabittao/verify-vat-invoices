const assert = require("node:assert/strict");
const test = require("node:test");

const {
  shouldRunFullPageScreenshotFallback,
} = require("../scripts/verification_result_classifier");

test("full page screenshot fallback runs when modal classification is missing", () => {
  assert.equal(shouldRunFullPageScreenshotFallback(null), true);
});

test("full page screenshot fallback is skipped when modal already shows captcha error", () => {
  assert.equal(
    shouldRunFullPageScreenshotFallback({
      status: "captcha_error",
      message: "captcha rejected by website",
    }),
    false
  );
});

test("full page screenshot fallback still runs for ambiguous active form state", () => {
  assert.equal(
    shouldRunFullPageScreenshotFallback({
      status: "form_still_active",
      message: "verification form is still active",
    }),
    true
  );
});
