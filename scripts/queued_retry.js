// Start an explicitly authorized retry only after the current runner finishes normally.
const fs = require('fs');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const folder = path.resolve(__dirname, '../output/resume');
const stateFile = process.argv[4] ? path.resolve(process.argv[4]) : path.join(folder, 'queued-retry-status.json');
const plan = path.resolve(process.argv[2]);
const priorPid = Number(process.argv[3]);
function state(state, extra = {}) { fs.writeFileSync(stateFile, JSON.stringify({ state, pid: process.pid, updated_at: new Date().toISOString(), plan, ...extra }, null, 2)); }
function alive(pid) { try { process.kill(pid, 0); return true; } catch { return false; } }
async function main() {
  if (!Number.isInteger(priorPid) || priorPid < 1 || !fs.existsSync(plan)) throw Error('Invalid queue inputs');
  state('waiting', { waiting_for_pid: priorPid });
  while (alive(priorPid)) {
    const command = execFileSync('ps', ['-p', String(priorPid), '-o', 'command='], {encoding:'utf8'});
    if (!command.includes('scripts/resume_pending.js')) throw Error('PID no longer belongs to runner');
    await new Promise(resolve => setTimeout(resolve, 15000));
  }
  const status = JSON.parse(fs.readFileSync(path.join(folder, 'run-status.json'), 'utf8'));
  if (status.pid !== priorPid || status.state !== 'finished') {
    state('cancelled', {reason:'Original runner did not finish normally; no automatic restart'}); return;
  }
  state('starting');
  const log = fs.openSync(path.join(folder, 'run.log'), 'a');
  const child = spawn(process.execPath, [path.join(__dirname, 'resume_pending.js'), '--retry-plan=' + plan], { cwd:path.resolve(__dirname,'..'), stdio:['ignore',log,log] });
  fs.closeSync(log);
  state('running', { runner_pid: child.pid });
  child.on('error', error => state('error', {reason:error.message}));
  child.on('exit', code => state(code === 0 ? 'finished' : 'error', {exit_code:code}));
}
process.on('SIGTERM', () => { state('cancelled', {reason:'Queue stopped'}); process.exit(0); });
main().catch(error => { state('error', {reason:error.message}); process.exitCode=1; });
