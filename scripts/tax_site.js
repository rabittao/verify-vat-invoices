const VERIFY_URL = 'https://inv-veri.chinatax.gov.cn/fpcygzfw/national-invoice-check';
const MODERN_FIELDS = {invoice_code:'.t-form-item__fpdm input',invoice_number:'.t-form-item__fphm input',invoice_date:'.t-form-item__kprq input',pretax_amount:'.t-form-item__kpje input',captcha:'.t-form-item__yzm input'};
async function selectInvoiceDate(page,value) {
 const input=page.locator(MODERN_FIELDS.invoice_date);
 if(await input.inputValue()===value)return;
 if(!/^\d{8}$/.test(value))throw new Error('Invalid invoice date');
 await input.click();
 const panel=page.locator('.t-date-picker__panel:visible');
 const target=Number(value.slice(0,4))*12+Number(value.slice(4,6))-1;
 for(let i=0;i<72;i++) {
  const year=await panel.locator('.t-date-picker__header-controller-year input').inputValue();
  const month=await panel.locator('.t-date-picker__header-controller-month input').inputValue();
  const y=Number(year.replace(/\D/g,'')),m=Number(month.replace(/\D/g,''));
  if(!y||m<1||m>12)throw new Error('Unable to read date-picker month');
  const current=y*12+m-1;
  if(current===target){
   await panel.locator('td.t-date-picker__cell:not(.t-date-picker__cell--additional):not(.t-date-picker__cell--disabled)').filter({hasText:new RegExp('^'+Number(value.slice(6))+'$')}).click();
   if(await input.inputValue()!==value)throw new Error('Date-picker value mismatch');
   return;
  }
  await panel.locator(current>target?'button[title="上个月"]':'button[title="下个月"]').click();
 }
 throw new Error('Date-picker month navigation exceeded limit');
}
module.exports={VERIFY_URL,MODERN_FIELDS,selectInvoiceDate};
