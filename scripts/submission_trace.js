// Observe the site's own verification request; never send a separate verification request.
function isVerificationRequest(request) {
  try { const path = new URL(request.url()).pathname; return /\/(?:vatQuery|query)\/?$/i.test(path) || (path.includes('/fpcy/') && !path.includes('getVerifyCode') && request.method?.() === 'POST'); } catch (_) { return false; }
}

function installSubmissionTrace(page) {
  if (page._submissionTraceInstalled || typeof page.on !== 'function') return;
  page._submissionTraceInstalled = true;
  page.on('request', request => {
    if (!page.submissionTrace || !isVerificationRequest(request)) return;
    const url = new URL(request.url());
    const event = { url: url.origin + url.pathname, sent_at: new Date().toISOString(), response_status: null,
      finished: false, failure: null };
    page.submissionTrace.requests.push(event);
    (page._submissionRequests ||= new WeakMap()).set(request, event);
  });
  page.on('response', response => {
    const event = page._submissionRequests?.get(response.request());
    if (event) event.response_status = response.status();
  });
  page.on('requestfinished', request => {
    const event = page._submissionRequests?.get(request);
    if (event) { event.finished = true; event.finished_at = new Date().toISOString(); }
  });
  page.on('requestfailed', request => {
    const event = page._submissionRequests?.get(request);
    if (event) event.failure = request.failure()?.errorText || 'request_failed';
  });
}

function submissionFailure(trace) {
  const requests = trace?.requests || [];
  if (!requests.length) return 'verification_request_not_sent';
  if (requests.some(r => /ERR_BLOCKED_BY_ORB/.test(r.failure || '') || r.response_status === 403)) return 'verification_endpoint_blocked';
  if (requests.some(r => r.failure || (r.response_status !== null && r.response_status >= 400))) return 'verification_request_failed';
  if (requests.some(r => !r.finished)) return 'verification_response_timeout';
  return 'verification_response_without_details';
}
async function clickVerificationButton(page, button) {
  try {
    // JSONP查验由结果弹窗判断，不等待点击引发的导航。
    await button.click({ timeout: 8000, noWaitAfter: true });
  } catch (error) {
    if (error.name !== 'TimeoutError') throw error;
    // 点击超时不能证明请求没发出；继续读取平台结果，绝不再次点击。
    page.submissionTrace.click_timeout = { at: new Date().toISOString(),
      request_observed: Boolean(page.submissionTrace.requests.length), message: error.message };
  }
}
module.exports = { clickVerificationButton, installSubmissionTrace, submissionFailure, isVerificationRequest };
