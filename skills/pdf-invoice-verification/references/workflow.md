# 项目入口与归档契约

以下命令在实际 repo 目录执行；占位路径和票号必须替换，不把示例作为真实票据提交。

## 新文件夹

先清点 PDF、页数和发票数量，识别重复票号、多票页或跨页票，保留原文件。当前工作区续跑器仅支持唯一 20 位票号、每张记录关联一个页码的电子普通发票；其他票种或布局需先适配，不能套用。

通用提取入口（需要项目 Python 依赖和 `QWEN_API_KEY`）：

```bash
python3 scripts/extract_invoices.py --input-dir /path/to/pdfs --output-json output/artifacts/intermediate/extracted.json --render-dir output/artifacts/rendered --recursive
```

通用查验入口（需要 Playwright、浏览器和 `DEEPSEEK_API_KEY`）：

```bash
node scripts/verify_invoices.js --input-json output/artifacts/intermediate/extracted.json --output-json output/artifacts/intermediate/verified.json --artifacts-dir output/artifacts/playwright --max-captcha-attempts 3
```

`run_pipeline.py` 可串联以上阶段，但不等于完成 PDF 同名文件夹归档。读取提取 JSON 的真实结构，不假设它与 manifest 相同。建立归档清单前核对原 PDF：票号保留字符串前导零、日期为 YYYYMMDD、金额用 Decimal 校验金额＋税额＝价税合计。提取不完整的记录先复核。

## 工作区布局和限制

当前归档脚本以源码目录上两级为资料根目录，`--recover` 还使用固定子目录 `verify-vat-invoices`，不是任意输入目录接口：

```text
资料根目录/
  原始文件.pdf
  verify-vat-invoices/       # 项目运行目录
  .核对工作/
    manifest.json
    .venv/bin/python        # 包含 Pillow
    OCR/<PDFstem>__001.json
  <PDFstem>/
    001_<20位票号>_查验结果.jpg
    核对清单.csv
  发票查验核对总表.csv
```

manifest 为数组；当前代码使用的字段：`PDF文件名`（basename）、`页码`（从1开始）、`发票号码`（唯一20位字符串）、`开票日期`（YYYYMMDD）、`金额`、`税额`、`价税合计`（金额字符串）、`结果截图`（相对资料根路径，初始为空）、`查验状态`、`票面核对`。

OCR 文件是含 `text`、`x`、`y` 的数组。当前 `expected_parties` 依赖特定票面布局：按 x<0.5 分左右，以 0.55<y<0.65 查购销双方。**这是现有票面适配器，不能假设所有 PDF 通用。** 新布局先验证坐标语义和提取结果，必要时适配并测试；缺失或多候选不猜名称。通用提取器不会自动生成这套坐标 OCR 和 manifest，不存在可直接调用的通用转换命令。

## 现有工作区续跑

先只检查归档依赖：

```bash
../.核对工作/.venv/bin/python scripts/archive_resume_result.py --check
```

先恢复已成功但未归档的结果（写入清单、无需网络）：

```bash
../.核对工作/.venv/bin/python scripts/archive_resume_result.py --recover
```

正常运行、单票验收和授权的页范围回查：

```bash
node scripts/resume_pending.js
node scripts/resume_pending.js --only-invoice=12345678901234567890
node scripts/resume_pending.js --retry-pdf=sample.pdf --retry-pages=13-20
```

页范围仅优先处理该范围，**之后仍会处理范围外待办**；若用户只授权范围内工作，不能直接使用此参数而放任全量运行。已有实际结果截图跳过。截图存在不证明清单一致，仍需归档审计。

后台启动应使用当前环境已有可靠的进程托管方式，stdout/stderr 写 `output/resume/run.log`；核验真正 runner PID、状态更新和日志，而不是只看启动命令退出码。重启前保存本轮范围和各票已用次数；`--completed-invoice=<票号>` 可重复指定，用于跳过本轮已完成尝试的票。保留部分预算应使用下文精确补跑计划，不能仅依赖此跳过参数。

停止时先确认 PID 命令行属于本项目，再发送 SIGTERM；不要对所有 node/Chrome 执行 kill。等待当前票结束的请求需观察该票终态及归档后再停止。

## 归档与故障证据

关键实现：
- `resume_pending.js`：工作区循环、同标签页恢复、状态和结果记录。
- `captcha_content_gate.js`：独立完整抄录与识别一致性。
- `submission_trace.js`：实际网站请求证据，避免重复提交。
- `archive_resume_result.py`：详情匹配、JPEG检验及归档入口。
- `workspace_archive.py`：字段核对、归档锁、清单和SHA256回读。
- `resume_image_retention.js`：只清理临时图，保留失败证据。

`success` 可能仍含“存在差异待复核”；分别统计平台详情、归档成功和字段一致。归档失败先保存证据、停止并报告，不能清临时图或伪造 archive_verified。

故障定位按同一票同一次尝试关联截图、`captcha_retry_history`、`content_check`、实际请求时间和网页反馈。只看最终输入框无法证明该验证码提交时仍有效。403 属于接口拒绝，不能直接归因为 OCR。不要从历史成功案例推断当前接口一定可用。

回归检查：

```bash
node --test test/*.test.js
../.核对工作/.venv/bin/python test/workspace_archive_test.py
git diff --check
```

## 精确补跑、持久化预算与队列

先读当前 `scripts/retry_plan.js`、`scripts/queued_retry.js` 和 `resume_pending.js`，确认参数仍受支持。

- `node scripts/resume_pending.js --retry-plan=/absolute/path/plan.json` 只处理计划内票号，已有实际归档截图跳过，`used_attempts >= 3` 不再提交。
- 计划 JSON 顶层为 `invoices` 数组，每项含 `invoice_number`（唯一20位字符串）、`source_pdf`、`page_number`、`used_attempts`（0–3整数）。记录 `initial_used_attempts` 便于审计。起始次数依据当前轮历史，不能全部默认0。
- `RetryPlan.bind` 通过临时文件和 rename 持久化有效候选计数，重启继续读取。筛选刷新不占次数，但仍遵守刷新频率和筛选上限。
- 用户明确要求再次查验已耗尽次数的票：创建新的独立计划，保留 `previous_round_attempts`、`previous_verified_at` 与原始 results；新一轮 `used_attempts=0`、上限3。不要覆盖旧计划或删除历史失败记录。
- 排队入口：`node scripts/queued_retry.js /absolute/path/plan.json PRIOR_RUNNER_PID /absolute/path/unique-queue-status.json`。每组队列使用独立状态文件、计划和日志，避免默认状态文件被第二组覆盖。
- 队列只在前序PID退出且 `run-status.json` 的PID匹配、状态为 `finished` 时启动。前序被停止或异常则取消；不自行重启。启动前检查同一计划是否已有队列，避免重复启动。
- 后台启动后回读真实队列PID、命令行和状态。测试 `test/queued_retry.test.js` 与 `test/retry_plan.test.js`，验证异常不启动、状态隔离、次数保持与超额拒绝。离线测试不代表平台已成功。

## 页面与网络故障定位

- 已填写但按钮灰色：区分表单输入事件未触发、按钮可操作条件、请求已发出、详情未被识别。对照输入、提交时间、真实请求与页面反馈；不靠移除 disabled 或强制点击掩盖原因。
- 验证码已变更、中文漏检、缺字或两次识别不一致：刷新不提交；不做全局字符替换猜验证码。模型无法保证零漏检。
- 新版提示可能是消息条，没有“确定”按钮；读取真实组件，等待消失或按实际关闭入口处理，不能无限等待不存在的按钮。
- `net::ERR_FAILED`、`ERR_NETWORK_CHANGED`、`ERR_INTERNET_DISCONNECTED`：有界刷新恢复，失败记录单票暂缓后继续其他票。刷新超时不能终止整批，也不能用OCR预算代替网络重试。
- 403：对照手工成功与程序的真实URL、浏览器版本/UA、网络代理、请求响应。历史上真实浏览器UA适配有帮助，但不是通用结论；不猜接口、不无限重放、不关闭浏览器安全机制。
- 点击超时后可能已出现详情：先读取新旧详情弹层并核验返回票号，再归档。不能直接记失败或刷新丢失成功结果。
