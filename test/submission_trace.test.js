const {test}=require('node:test');
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {installSubmissionTrace,submissionFailure}=require('../scripts/submission_trace');

test('tracks the actual site request and distinguishes aborted network from missing request',async()=>{
 const browser=await chromium.launch({headless:true});
 try{
  const page=await browser.newPage();installSubmissionTrace(page);installSubmissionTrace(page);
  page.submissionTrace={requests:[]};
  assert.equal(submissionFailure(page.submissionTrace),'verification_request_not_sent');
  await page.route('https://tax.test/**',route=>route.abort('connectionfailed'));
  await page.setContent('<button onclick="this.disabled=true;fetch(\'https://tax.test/NWebQuery/vatQuery?yzm=ABCD\').catch(()=>window.failed=true)">查验</button>');
  await page.getByRole('button',{name:'查验'}).click();
  await page.waitForFunction(()=>window.failed);
  assert.equal(page.submissionTrace.requests.length,1);
  assert.ok(page.submissionTrace.requests[0].failure);
  assert.equal(submissionFailure(page.submissionTrace),'verification_request_failed');
  assert.equal(page.submissionTrace.requests[0].url,'https://tax.test/NWebQuery/vatQuery');
  assert.equal(await page.getByRole('button',{name:'查验'}).isDisabled(),true);
 }finally{await browser.close();}
});

test('classifies pending and completed responses separately',()=>{
 assert.equal(submissionFailure({requests:[{finished:false,response_status:null}]}),'verification_response_timeout');
 assert.equal(submissionFailure({requests:[{finished:true,response_status:200}]}),'verification_response_without_details');
 assert.equal(submissionFailure({requests:[{finished:true,response_status:503}]}),'verification_request_failed');
});


test('click timeout observes existing request without submitting twice',async()=>{
 const {clickVerificationButton}=require('../scripts/submission_trace');
 for(const sent of [false,true]) {
  const page={submissionTrace:{requests:sent?[{finished:false}]:[]}};let clicks=0;
  await clickVerificationButton(page,{click:async opts=>{clicks++;assert.equal(opts.noWaitAfter,true);assert.equal(opts.timeout,8000);const e=new Error('performing click action');e.name='TimeoutError';throw e;}});
  assert.equal(clicks,1);assert.equal(page.submissionTrace.click_timeout.request_observed,sent);
 }
});

test('expired captcha is classified and confirmed with native page callback',async()=>{
 const {classifyVerificationSignals}=require('../scripts/verification_result_classifier');
 const {acknowledgeCaptchaError}=require('../scripts/verify_invoices');
 assert.equal(classifyVerificationSignals({bodyText:'提示 验证码失效!',popupTexts:['验证码失效!'],visibleKeywordTexts:[]}).status,'captcha_error');
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage();
  await page.setContent('<div id="popup_container"><p>验证码失效!</p><button onclick="window.confirmed=true;document.getElementById(&quot;popup_container&quot;).remove()">确定</button></div>');
  assert.equal(await acknowledgeCaptchaError(page),true);
  assert.equal(await page.evaluate(()=>window.confirmed),true);
 }finally{await browser.close();}
});


test('modern toast waits for disappearance without clicking unrelated confirm; hidden duplicates ignored',async()=>{
 const {acknowledgeCaptchaError}=require('../scripts/verify_invoices');
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage();
  await page.setContent('<p style="display:none">验证码错误!</p><div class="t-message">验证码错误!</div><button onclick="window.wrongClick=true">确定</button>');
  await page.evaluate(()=>setTimeout(()=>document.querySelector('.t-message').remove(),150));
  assert.equal(await acknowledgeCaptchaError(page),true);
  assert.equal(await page.evaluate(()=>window.wrongClick),undefined);
 }finally{await browser.close();}
});

test('confirmation is scoped to the actual error dialog',async()=>{
 const {acknowledgeCaptchaError}=require('../scripts/verify_invoices');
 const browser=await chromium.launch({headless:true});
 try {
  const page=await browser.newPage();
  await page.setContent('<button onclick="window.wrongClick=true">确定</button><div class="t-dialog" role="dialog"><p>验证码错误!</p><button onclick="window.confirmed=true;this.parentElement.remove()">确定</button></div>');
  assert.equal(await acknowledgeCaptchaError(page),true);
  assert.equal(await page.evaluate(()=>window.confirmed),true);
  assert.equal(await page.evaluate(()=>window.wrongClick),undefined);
 }finally{await browser.close();}
});
