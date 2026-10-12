// An endpoint block is not a captcha rejection. Leave affected invoices pending.
class EndpointCircuit {
  constructor({ now = Date.now } = {}) { this.now = now; this.blocked = new Map(); }
  noteResult(result) {
    for (const retry of result.captcha_retry_history || []) {
      for (const request of retry.submission_trace?.requests || []) {
        if (!/ERR_BLOCKED_BY_ORB/.test(request.failure || '') && request.response_status !== 403) continue;
        const time = Date.parse(request.sent_at || result.verified_at);
        if (!Number.isFinite(time) || this.now() - time > 30 * 60 * 1000) continue;
        const host = new URL(request.url).hostname;
        this.blocked.set(host, { host, at: new Date(time).toISOString(), reason: request.failure || 'HTTP 403' });
      }
    }
  }
  reason(endpoint) { return endpoint ? this.blocked.get(new URL(endpoint).hostname) : undefined; }
}

async function resolveInvoiceEndpoints(page, records) {
  // 新版由表单校验后确定swjginfo；不能沿用旧版路由或猜新接口。
  if (typeof page.url === 'function' && new URL(page.url()).pathname.startsWith('/fpcygzfw/')) return {};
  // Use the site's actual routing function, including its 20-digit invoice handling.
  return page.evaluate(items => {
    if (typeof window.getSwjg !== 'function') throw new Error('税站路由函数 getSwjg 不可用，停止而非猜测省份接口');
    return Object.fromEntries(items.map(r => {
      const route = window.getSwjg(r.invoice_code || r.invoice_number, 1);
      return [r.invoice_number, route?.[1] || null];
    }));
  }, records);
}
module.exports = { EndpointCircuit, resolveInvoiceEndpoints };
