const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'); const os = require('os'); const path = require('path');
const { RetryPlan } = require('../scripts/retry_plan');
test('retry preserves used budget across restart, excludes other invoices and rejects overspend', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'retry-plan-'));
  try {
    const file = path.join(dir, 'plan.json'), number = '12345678901234567890';
    fs.writeFileSync(file, JSON.stringify({invoices:[{invoice_number:number,used_attempts:1}]}));
    const plan = new RetryPlan(file), page = {};
    assert.equal(plan.includes('99999999999999999999'), false);
    plan.bind(page, number); assert.equal(page.invoiceOcrAttempts, 1);
    page.invoiceOcrAttempts++; assert.equal(new RetryPlan(file).used(number), 2);
    page.invoiceOcrAttempts--; assert.equal(new RetryPlan(file).used(number), 1);
    page.invoiceOcrAttempts = 3;
    assert.throws(() => page.invoiceOcrAttempts++, /exceeded/);
    assert.equal(new RetryPlan(file).used(number), 3);
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});
