const {test}=require('node:test');
const assert=require('node:assert/strict');
const {CaptchaNetworkRecovery}=require('../scripts/captcha_network_recovery');
test('network failure refreshes same page three times, preserves OCR budget, then defers',async()=>{
 const recovery=new CaptchaNetworkRecovery();let reloads=0,waits=0;
 const page={invoiceOcrAttempts:2,waitForSelector:async()=>{},reload:async opts=>{assert.equal(opts.waitUntil,'domcontentloaded');reloads++;}};
 const guard={wait:async kind=>{assert.equal(kind,'refresh');waits++;}};
 for(let i=0;i<3;i++){
  assert.equal(await recovery.recover(page,guard,{failure_reason:'modern_captcha_unavailable'}),'retry');
  assert.equal(page.invoiceOcrAttempts,2);assert.equal(page.reuseInvoicePage,true);
 }
 const result={failure_reason:'modern_captcha_unavailable'};
 assert.equal(await recovery.recover(page,guard,result),'deferred');
 assert.equal(result.verification_status,'captcha_deferred');assert.equal(result.captcha_network_refreshes,3);
 assert.equal(reloads,3);assert.equal(waits,3);assert.equal(page.invoiceOcrAttempts,2);
});
test('successful or unrelated result does not refresh',async()=>{
 assert.equal(await new CaptchaNetworkRecovery().recover({}, {},{verification_status:'success'}),'unrelated');
});
