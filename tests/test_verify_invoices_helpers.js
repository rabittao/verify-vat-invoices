const assert = require("node:assert/strict");
const test = require("node:test");

const {
  selectVerificationEvidenceScreenshot,
} = require("../scripts/verify_invoices_helpers");

test("verification evidence screenshot prefers modal crop over full page", () => {
  assert.equal(
    selectVerificationEvidenceScreenshot({
      modalScreenshotPath: "invoice-modal.png",
      fullPageScreenshotPath: "invoice-result.png",
    }),
    "invoice-modal.png"
  );
});

test("verification evidence screenshot falls back to full page when modal is unavailable", () => {
  assert.equal(
    selectVerificationEvidenceScreenshot({
      modalScreenshotPath: null,
      fullPageScreenshotPath: "invoice-result.png",
    }),
    "invoice-result.png"
  );
});
