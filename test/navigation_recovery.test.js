const { test } = require('node:test');
const assert = require('node:assert/strict');
const { reloadInvoicePage, navigationDeferred } = require('../scripts/navigation_recovery');
const timeout = () => Object.assign(new Error('page.reload: Timeout exceeded'), {name:'TimeoutError'});
test('reload timeout is bounded, preserves OCR budget, and next invoice can proceed', async () => {
  let calls=0;
  const page={invoiceOcrAttempts:2,reload:async()=>{calls++;throw timeout();},waitForSelector:async()=>{}};
  const guard={wait:async()=>{}};
  assert.equal(await reloadInvoicePage(page,guard),false);
  assert.equal(calls,2);assert.equal(page.invoiceOcrAttempts,2);assert.equal(page.reuseInvoicePage,false);
  assert.equal(navigationDeferred(page,{invoice_number:'test'}).verification_status,'navigation_deferred');
  page.reload=async opts=>assert.equal(opts.waitUntil,'domcontentloaded');
  assert.equal(await reloadInvoicePage(page,guard),true);
});
test('loaded document must also contain the form; non-network faults are not hidden',async()=>{
  const guard={wait:async()=>{}};
  let calls=0;
  const page={reload:async()=>{},waitForSelector:async()=>{calls++;throw timeout();}};
  assert.equal(await reloadInvoicePage(page,guard),false);assert.equal(calls,2);
  page.reload=async()=>{throw new Error('Target page, context or browser has been closed');};
  await assert.rejects(reloadInvoicePage(page,guard),/closed/);
});
