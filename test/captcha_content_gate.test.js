const { test } = require('node:test');
const assert = require('node:assert/strict');
const {inspectAnswer,recognizeCheckedCaptcha}=require('../scripts/captcha_content_gate');
test('Han, unknown classification, omissions and malformed checks fail closed',()=>{
 for(const raw of ['{}','not JSON','{"contains_chinese":null,"text":"EWM","count":3}',
 '{"contains_chinese":true,"text":"EWM","count":3}',
 '{"contains_chinese":false,"text":"EWM中","count":4}',
 '{"contains_chinese":false,"text":"EWM","count":4}']) assert.equal(inspectAnswer(raw).allowed,false);
});
test('Chinese inspection never calls OCR or produces a budget-consuming candidate',async()=>{
 let calls=0;
 const result=await recognizeCheckedCaptcha(Buffer.from('x'),'ocr',async()=>{calls++;return {rawContent:'{"contains_chinese":true,"text":"EWM中","count":4}'};});
 assert.equal(calls,1);assert.equal(result.primaryCaptcha,'');assert.equal(result.rejectionReason,'chinese_captcha_refresh');
});
test('partial OCR and case disagreements rejected; identical full answers accepted',async()=>{
 for(const answer of ['EW','ewm','EWM']){
  const responses=['{"contains_chinese":false,"text":"EWM","count":3}',answer];
  const result=await recognizeCheckedCaptcha(Buffer.from('x'),'ocr',async()=>({rawContent:responses.shift(),model:'test'}));
  assert.equal(result.primaryCaptcha,answer==='EWM'?'EWM':'');
 }
});
test('rejected content check leaves the actual challenge budget unchanged', async()=>{
 const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
 const {createRequire}=require('node:module');
 const file=path.resolve(__dirname,'../scripts/verify_invoices.js');
 const sandbox={require:createRequire(file),module:{exports:{}},__dirname:path.dirname(file),console,Buffer,process};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(file,'utf8'),sandbox);
 vm.runInContext(`
 readCaptchaPromptText=async()=> '请输入验证码文字';
 resolveVerificationAmount=()=>({});
 findCaptchaImage=async()=>({waitFor:async()=>{},screenshot:async()=>Buffer.from('test')});
 preprocessCaptchaImages=()=>({original:'mock.png'});
 collectCaptchaCandidates=async()=>recognizeCheckedCaptcha(Buffer.from('test'),'test',async()=>({rawContent:'{"contains_chinese":true,"text":"EWM中","count":4}'}));
 `,sandbox);
 const page={invoiceOcrAttempts:2,locator:()=>({innerText:async()=> '请输入验证码文字'})};
 const result=await sandbox.module.exports.readCaptchaChallenge(page,{},'.','test',1);
 assert.equal(result.captchaCandidates.length,0);assert.equal(page.invoiceOcrAttempts,2);
 assert.equal(result.candidateBundle.rejectionReason,'chinese_captcha_refresh');
});
