const MINUTE_MS = 65000;

function interruptibleSleep(ms, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); signal?.removeEventListener('abort', abort); reject(new Error('运行已停止')); };
    const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms);
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
  });
}

function isRateLimitText(text) {
  const compact = String(text || '').replace(/\s+/g, '');
  return /(?:1|一)分钟(?:后|内|之内)|(?:60|六十)秒(?:后|内)|访问(?:过于|过|太)?频繁|(?:操作|请求|查验)(?:过于|过|太)?频繁|访问频率|请求频率|rate_limit/.test(compact);
}

class RateLimitError extends Error {
  constructor(text) {
    super(String(text).slice(0, 500));
    this.code = 'PLATFORM_RATE_LIMIT';
  }
}

class TrafficGuard {
  constructor({ now = Date.now, sleep, signal, log = console.log } = {}) {
    this.now = now;
    this.sleep = sleep || (ms => interruptibleSleep(ms, signal));
    this.log = log;
    this.lastRefresh = null;
    this.lastSubmit = null;
    this.pendingDialog = '';
    this.cooldownCount = 0;
  }

  async wait(kind) {
    const key = kind === 'submit' ? 'lastSubmit' : 'lastRefresh';
    const interval = kind === 'submit' ? MINUTE_MS : 10000;
    const remaining = this[key] === null ? 0 : interval - (this.now() - this[key]);
    if (remaining > 0) {
      this.log(`[节流] ${kind === 'submit' ? '查验提交' : '验证码刷新'}等待 ${Math.ceil(remaining / 1000)} 秒。`);
      await this.sleep(remaining);
    }
    if (kind !== 'submit') this[key] = this.now();
    return Math.max(remaining, 0);
  }

  markSubmitted() {
    this.lastSubmit = this.now();
  }

  async check(page) {
    const body = await page.locator('body').innerText().catch(() => '');
    const text = this.pendingDialog || body;
    if (isRateLimitText(text)) throw new RateLimitError(text);
  }

  async cooldown(reason = "限流") {
    // 连续限流时逐步延长等待，期间不向平台发送请求。
    const delay = Math.min(MINUTE_MS * 2 ** this.cooldownCount++, 300000);
    this.log(`[${reason}] 等待 ${Math.ceil(delay / 1000)} 秒后继续当前发票。`);
    await this.sleep(delay);
    this.pendingDialog = '';
  }
}

module.exports = { isRateLimitText, RateLimitError, TrafficGuard };
