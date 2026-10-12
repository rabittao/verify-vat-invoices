// Network refreshes are independent of the three recognized-captcha attempts.
const { reloadInvoicePage } = require('./navigation_recovery');
class CaptchaNetworkRecovery {
  constructor(maxRefreshes = 3) { this.maxRefreshes = maxRefreshes; this.refreshes = 0; }
  async recover(page, guard, result) {
    if (result.failure_reason !== 'modern_captcha_unavailable') return 'unrelated';
    if (this.refreshes >= this.maxRefreshes) {
      result.verification_status = 'captcha_deferred';
      result.verification_message = `验证码接口连续失败，已刷新${this.refreshes}次，本票暂缓并继续下一张`;
      result.captcha_network_refreshes = this.refreshes;
      return 'deferred';
    }
    this.refreshes++;
    result.captcha_network_refreshes = this.refreshes;
    console.log(`[验证码请求失败] 同一标签页刷新 ${this.refreshes}/${this.maxRefreshes}；不重置识别预算。`);
    if (!await reloadInvoicePage(page, guard, 1)) {
      result.verification_status = 'navigation_deferred';
      result.failure_reason = 'page_navigation_failed';
      result.verification_message = page.lastNavigationError;
      return 'deferred';
    }
    return 'retry';
  }
}
module.exports = { CaptchaNetworkRecovery };
