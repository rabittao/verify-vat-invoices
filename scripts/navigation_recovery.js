const { MODERN_FIELDS } = require('./tax_site');

function isTransientNavigationError(error) {
  return error?.name === 'TimeoutError' || /net::ERR_(?:NETWORK_CHANGED|CONNECTION_RESET|CONNECTION_CLOSED|CONNECTION_TIMED_OUT|TIMED_OUT|INTERNET_DISCONNECTED|NAME_NOT_RESOLVED|FAILED)/.test(error?.message || '');
}

// Wait for the form we need, not for unrelated requests to become idle.
async function reloadInvoicePage(page, guard, maxAttempts = 2) {
  page.reuseInvoicePage = false;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await guard.wait('refresh');
    try {
      await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForSelector(MODERN_FIELDS.invoice_number, { state: 'visible', timeout: 15000 });
      page.reuseInvoicePage = true;
      page.lastNavigationError = null;
      return true;
    } catch (error) {
      if (!isTransientNavigationError(error)) throw error;
      page.lastNavigationError = error.message;
      console.log(`[页面恢复] ${attempt}/${maxAttempts} 失败：${error.message.split('\n')[0]}`);
    }
  }
  return false;
}

function navigationDeferred(page, record, error) {
  return { ...record, verification_status: 'navigation_deferred', failure_reason: 'page_navigation_failed',
    verification_message: error?.message || page.lastNavigationError || '页面恢复失败，保留待处理并继续下一张',
    captcha_attempts: page.invoiceOcrAttempts || 0, verified_at: new Date().toISOString() };
}
module.exports = { reloadInvoicePage, isTransientNavigationError, navigationDeferred };
