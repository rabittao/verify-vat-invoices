const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs'), os = require('os'), path = require('path');
const { spawnSync } = require('child_process');
test('queue starts only after normal completion and never after stopped/error status', () => {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'queue-retry-'));
 try {
  fs.mkdirSync(path.join(root,'scripts')); const out=path.join(root,'output/resume');fs.mkdirSync(out,{recursive:true});
  const script=path.join(root,'scripts/queued_retry.js');fs.copyFileSync(path.join(__dirname,'../scripts/queued_retry.js'),script);
  fs.writeFileSync(path.join(root,'scripts/resume_pending.js'),"require('fs').writeFileSync('started.json',JSON.stringify(process.argv.slice(2)))");
  const plan=path.join(out,'plan.json');fs.writeFileSync(plan,'{}');
  // A PID outside the OS process ID range is never alive.
  const pid=2147483647;
  for(const state of ['stopped','error','finished']) {
   fs.writeFileSync(path.join(out,'run-status.json'),JSON.stringify({pid,state}));
   const result=spawnSync(process.execPath,[script,plan,String(pid)],{timeout:5000});
   assert.equal(result.status,0);
   const status=JSON.parse(fs.readFileSync(path.join(out,'queued-retry-status.json')));
   assert.equal(status.state,state==='finished'?'finished':'cancelled');
   assert.equal(fs.existsSync(path.join(root,'started.json')),state==='finished');
  }
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root,'started.json'))),['--retry-plan='+plan]);
  const originalState=fs.readFileSync(path.join(out,'queued-retry-status.json'),'utf8');
  const separateState=path.join(out,'captcha-retry-status.json');
  const separate=spawnSync(process.execPath,[script,plan,String(pid),separateState],{timeout:5000});
  assert.equal(separate.status,0);
  assert.equal(JSON.parse(fs.readFileSync(separateState)).state,'finished');
  assert.equal(fs.readFileSync(path.join(out,'queued-retry-status.json'),'utf8'),originalState);
 } finally {fs.rmSync(root,{recursive:true,force:true});}
});
