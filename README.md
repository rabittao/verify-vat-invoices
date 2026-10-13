# verify-vat-invoices

批量处理目录中的 PDF 增值税发票：扫描 PDF、渲染页面、调用视觉模型抽取字段、自动访问国家税务总局发票查验平台完成查验，并输出结构化 JSON 结果。

仓库提供完整的本地运行链路，适合在本地或受控环境中批量处理发票文件，并保留中间结果和截图用于复核。

## 项目能力

- 扫描目录中的 `.pdf` 文件，支持递归查找
- 使用 `PyMuPDF` 将 PDF 页面渲染为 PNG
- 使用 `qwen-vl-max` 抽取增值税发票字段
- 自动规范化发票号码、日期、金额、校验码等字段
- 通过 `Playwright` 驱动浏览器访问税务查验网站
- 使用视觉模型识别验证码
- 输出中间结果、查验结果和过程截图，便于复核

## 处理流程

```text
PDF 目录
  -> scripts/run_pipeline.py
     -> scripts/extract_invoices.py
        -> rendered/*.png
        -> intermediate/extracted.json
     -> scripts/verify_invoices.js
        -> playwright/*.png
        -> intermediate/verified.json
```

### 阶段 1：发票字段抽取

入口脚本：`scripts/extract_invoices.py`

流程：

1. 扫描输入目录中的 PDF
2. 用 `PyMuPDF` 逐页渲染成 PNG
3. 将页面图片发送给 `qwen-vl-max`
4. 规范化字段格式
5. 进行基础校验
6. 输出 `extracted.json`

### 阶段 2：税务网站查验

入口脚本：`scripts/verify_invoices.js`

流程：

1. 读取 `extracted.json`
2. 按 `invoice_key` 去重
3. 启动浏览器访问税务查验站
4. 自动填写发票代码、号码、日期、金额或校验码
5. 截取验证码并调用视觉模型识别
6. 提交并分类查验结果
7. 输出 `verified.json` 和查验截图

## 仓库结构

```text
.
├── README.md
├── SKILL.md
├── package.json
├── requirements.txt
├── scripts
│   ├── extract_invoices.py
│   ├── run_pipeline.py
│   ├── verify_invoices.js
│   └── verify_invoices_helpers.js
└── output
    └── artifacts
```

## 环境要求

- Node.js `>= 18`
- Python `>= 3.9`
- macOS / Linux 均可，本仓库当前在 macOS 环境中验证过

本地检查到的运行版本：

- Node.js `v20.20.0`
- Python `3.13.9`

## 安装依赖

### Node.js

```bash
npm install
```

### Python

```bash
python3 -m pip install -r requirements.txt
```

## 环境变量

复制模板并填写：

```bash
cp .env.example .env
```

`.env` 需要的变量：

| 变量名 | 必填 | 作用 |
|---|---|---|
| `QWEN_API_KEY` | 是 | 抽取发票字段，供 `extract_invoices.py` 调用 DashScope Compatible API |
| `DEEPSEEK_API_KEY` | 是 | 识别验证码，供 `verify_invoices.js` 调用 DeepSeek 官方 API |
| `DEEPSEEK_CAPTCHA_MODEL` | 否 | 验证码 OCR 模型，默认 `deepseek-flash` |
| `DEEPSEEK_BASE_URL` | 否 | 默认 `https://api.deepseek.com`，须为 HTTPS |
| `CHROME_USER_DATA_DIR` | 否 | 指向本地 Chrome 用户目录，便于复用浏览器证书/信任配置 |

说明：

- 如果没有 `QWEN_API_KEY`，抽取阶段会直接失败
- 如果没有 `DEEPSEEK_API_KEY`，查验阶段中的验证码识别会失败
- 如果税务网站对浏览器信任链要求更严格，推荐配置 `CHROME_USER_DATA_DIR`

## 快速开始

### 一键运行完整流程

```bash
python3 scripts/run_pipeline.py --input-dir . --recursive
```

### 指定输入目录

```bash
python3 scripts/run_pipeline.py \
  --input-dir /path/to/pdfs \
  --output-root /path/to/output \
  --recursive
```

### 单独执行抽取

```bash
python3 scripts/extract_invoices.py \
  --input-dir /path/to/pdfs \
  --output-json output/artifacts/intermediate/extracted.json \
  --render-dir output/artifacts/rendered \
  --recursive
```

### 单独执行查验

```bash
node scripts/verify_invoices.js \
  --input-json output/artifacts/intermediate/extracted.json \
  --output-json output/artifacts/intermediate/verified.json \
  --artifacts-dir output/artifacts/playwright \
  --max-captcha-attempts 3
```

## 输出文件

默认输出目录：

```text
output/
└── artifacts/
    ├── intermediate/
    │   ├── extracted.json
    │   └── verified.json
    ├── rendered/
    │   └── *.png
    └── playwright/
        └── *.png
```

### `extracted.json`

用于保存抽取阶段结果。常见状态：

| `extraction_status` | 含义 |
|---|---|
| `success` | 成功抽取出可用于查验的字段 |
| `missing_fields` | 抽取到了发票，但缺少关键字段，无法进入网站查验 |
| `no_invoice_detected` | 页面中没有识别到增值税发票，这不是错误 |
| `failed` | 渲染、模型调用或 PDF 读取失败 |

示例结构：

```json
{
  "generated_at": "2026-04-19T00:00:00+00:00",
  "input_dir": "/path/to/pdfs",
  "record_count": 2,
  "records": [
    {
      "source_pdf": "invoice.pdf",
      "page_number": 1,
      "invoice_type": "电子发票（普通发票）",
      "invoice_number": "12345678901234567890",
      "invoice_date": "2026-03-28",
      "pretax_amount": "330.19",
      "total_amount": "350.00",
      "extraction_status": "success",
      "validation_status": "pass",
      "invoice_key": "|12345678901234567890|2026-03-28|330.19"
    }
  ]
}
```

### `verified.json`

用于保存网站查验阶段结果。常见状态：

| `verification_status` | 含义 |
|---|---|
| `success` | 网站返回查验成功 |
| `data_mismatch` | 网站返回查无此票或信息不一致 |
| `captcha_error` | 验证码重试耗尽 |
| `daily_limit_exceeded` | 该发票当日查验次数超限 |
| `website_system_error` | 税务网站返回“系统异常，请重试”之类终态弹窗 |
| `verification_form_not_activated` | 页面校验未激活真实查验按钮 |
| `script_error` | 浏览器自动化脚本异常 |
| `skipped` | 该记录未进入网站查验 |

示例结构：

```json
{
  "generated_at": "2026-04-19T00:00:00+00:00",
  "source_file": "output/artifacts/intermediate/extracted.json",
  "results_by_key": {
    "|12345678901234567890|2026-03-28|330.19": {
      "verification_status": "success",
      "verification_message": "verification succeeded",
      "verification_amount_type": "total_amount",
      "verification_amount_used": "350.00",
      "result_screenshot": "output/artifacts/playwright/example.png"
    }
  }
}
```

## 浏览器策略

查验脚本按以下顺序启动浏览器：

1. Chrome 持久化用户配置目录
2. Firefox
3. Chromium

所有浏览器都会启用 `ignoreHTTPSErrors: true`。

## 验证码策略

- 仅在可见提示严格为“请输入验证码文字”时调用模型；红色、蓝色或未知提示先刷新。连续筛选40次仍无有效候选时暂缓该票，继续下一张
- 仅接受2–8个英文字母或数字，保留大小写；独立内容检查与识别结果须完全一致，含中文、检查不确定或结果不一致时刷新重试
- `--max-captcha-attempts` 默认 3，允许 1–3；每张发票最多尝试3个有效候选（仅字母和数字）；中文、空回答、UNKNOWN、内容检查不通过及暂时接口错误只刷新筛选，不占这3次预算。候选图片在提交前发生变化也不占预算
- API 身份验证错误立即停止该张，不浪费剩余重试；请求有 30 秒超时
- 验证结果截图的视觉兜底也复用 DeepSeek 接口，其调用不计入验证码识别次数
- 默认使用 `deepseek-flash` 进行验证码 OCR，也可以通过 `DEEPSEEK_CAPTCHA_MODEL` 切换支持图片输入的 DeepSeek 模型

## 查验结果判定策略

- 提交后不是只看一次整页文本，而是在固定时间窗口内短轮询页面可见内容
- 成功弹层优先级最高；只要可见区域出现 `发票查验明细`、`查验次数`、发票明细字段，或 `打印 / 关闭` 加发票明细组合，就直接判为 `success`
- 当 DOM 可见文本仍然偏模糊时，会继续读取结果截图做视觉兜底；截图兜底是统一链路，先看局部弹层，再在必要时补看整页截图
- `captcha_error` 只在没有命中更强终态时才成立，避免“成功弹层已出现但旧验证码错误残留文本还在”造成误判
- `daily_limit_exceeded`、`website_system_error` 这类终态一旦命中，会直接停止后续验证码重试

## 已知限制

- 目前只处理增值税发票，不覆盖机票、火车票、出租车票等票种
- 抽取和验证码识别都依赖外部模型服务，准确率受模型和图片质量影响
- 税务网站页面结构如果变化，Playwright 选择器和结果分类规则可能需要同步更新

## DeepSeek 接入与验证

验证码采用 `deepseek-flash` 的 Chat Completions 图片输入，关闭思考模式，仅提取最终回答。参考 [官方图像理解文档](https://api-docs.deepseek.com/zh-cn/guides/vision/) 与 [思考模式文档](https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/)。验证码图片会发送至 DeepSeek；结果截图视觉兜底会发送包含发票信息的截图。

填写本地 `.env` 中的 `DEEPSEEK_API_KEY` 后使用前述查验命令。无需 OpenAI 或 OpenRouter 密钥；完整 PDF 抽取流程仍需要 QWEN_API_KEY。

运行 `npm test` 验证请求格式、错误处理、提示筛选和输出校验；离线测试不等同于真实模型识别或税务网站查验成功。

### 本工作目录断点续跑

该续跑入口用于现有工作目录，依赖上一级目录的 `.核对工作/.venv/bin/python`（含 Pillow）、已采集清单及票面OCR；这些本地发票资料及辅助环境不包含在仓库中。归档核对模块 `scripts/workspace_archive.py` 随项目提供，不再引用外部 `查验程序/invoice_check.py`。通用抽取和查验仍使用前述命令。

`node scripts/resume_pending.js` 读取上一级目录 `.核对工作/manifest.json`，仅处理没有实际结果截图的发票。默认在后台浏览器的同一个标签页中处理全部发票，不弹出浏览器窗口，不使用日常工作浏览器的用户配置。

单票验证可使用 `node scripts/resume_pending.js --only-invoice=20位发票号码`，只处理指定未归档发票，完成即退出，不继续其他票。续跑浏览器使用与实际 Chromium 版本匹配的普通 Chrome User-Agent：2026-10-12 同票对照中，默认 HeadlessChrome 标识使江苏验证码 OPTIONS 返回403，普通标识返回200；已完成江苏单票真实查验及归档验证。此配置保留后台运行、证书校验、CORS与节流。

页面恢复等待 `domcontentloaded` 和发票输入框可见，不再等待全站请求进入 `networkidle`。查验异常或限流后的刷新最多尝试2次；网络超时后记录 `navigation_deferred` 并继续下一张，保留已用验证码预算。验证码接口自身的刷新仍沿用最多3次规则，若页面刷新也失败则立即暂缓该票。浏览器关闭、程序错误和归档核验失败仍停止并报告，不掩盖为成功。

验证码刷新至少间隔10秒，查验提交至少间隔65秒。识别到一分钟限流或访问频繁提示（包括网页弹窗与原生 alert）后，暂停65秒再在同一标签页刷新，继续当前发票；连续限流等待逐步延长，最长5分钟。每张发票的3次识别预算在限流续跑时保留。每日查验次数上限仍会停止，不按一分钟限流重试。

进度和日志保存于 `output/resume/run-status.json`、`output/resume/results.json`、`output/resume/run.log`。运行PID保存于 `output/resume/runner.pid`，已有实例时拒绝重复启动；可向该PID发送SIGTERM停止。已有结果截图继续按原PDF文件名目录归档。

修正：提交间隔只从实际查验提交开始计时；等待结束会刷新并重新读取验证码，提交前再检查图片及提示是否变化。“验证码错误”会点击网页中的“确定”（原生 alert 自动接受），再按原有3次预算重试。不再要求纯英文字母。重试记录包含模型原始回答、拒绝原因、图片获取/识别/提交时间和网站反馈；原生弹窗另存 `output/resume/native-dialogs.jsonl`。这些诊断资料只保存本地。

续跑预算更新：只在“请输入验证码文字”提示下识别，有效字母、数字和中文候选计入3次，筛选刷新与接口暂时错误不计入。筛选轮次耗尽返回 `captcha_selection_exhausted`，续跑器等待后继续同一票，保留已用有效候选次数。不再进行纯英文筛选；模型回答中的数字和中文不会因此被过滤。

提交诊断：程序监听网站自己的 `vatQuery/query` 请求，不另发查验请求。按钮变灰后若请求未发送、网络失败、超时或返回后仍无详情，会分别记录原因，并在剩余有效候选预算内等待、刷新同一页面重试；不再一律标为验证码错误。可见结果iframe直接读取，减少不必要的结果截图模型调用。历史图片回放表明，4倍放大仍可能误识别，默认保持原图输入；`CAPTCHA_MODEL_IMAGE_SCALE=4` 仅作为可选实验。

接口拦截处理：`ERR_BLOCKED_BY_ORB` 或 HTTP 403 单独标记为 `verification_endpoint_blocked`，当前发票及本轮使用同一接口的发票记为 `endpoint_deferred`，保留待处理状态并继续其他接口的发票，不重复消耗验证码。接口地址由税站实际 `getSwjg` 函数解析完整票号，保存于 `output/resume/endpoint-routing.json`，不猜省份编码。启动时仅复用最近30分钟的拦截证据；不修改浏览器安全设置或绕过服务端拦截。40次筛选仍无足够有效候选时记为 `captcha_deferred`，不误报用完3次，也不无限停留。停止信号会立即中断限流等待。

归档恢复：启动前检查本地归档依赖，并从已保存的平台详情文本与JPEG截图补回尚未归档的成功结果，再计算待处理清单。成功提交记录先保存为 `output/resume/<票号>-success.json`，避免归档异常丢失提交证据。单独运行 `.核对工作/.venv/bin/python verify-vat-invoices/scripts/archive_resume_result.py --recover`（在上一级工作目录）只恢复本地结果，不启动浏览器或再次查验。必须存在详情标题、匹配的发票号码和有效JPEG才归档；核对差异明确标为待复核。使用同一Python运行 `test/workspace_archive_test.py` 验证归档、错票拒绝、差异保留及损坏截图拒绝。

每次归档后回读目标图片并比较SHA256，核验目录及文件名与原PDF、页码、票号一致；回读manifest、总表与对应文件夹核对清单的路径、状态、核对字段。全部一致才输出“归档回读通过”，并在本轮结果记录写入 `archive_verified`、`archived_screenshot` 和 `archive_sha256`。任何回读失败都会保留已取得的结果证据并停止本轮，避免把未正确归档的结果当作已完成。

用户明确要求回查指定页时，可运行 `node scripts/resume_pending.js --retry-pdf=sample.pdf --retry-pages=13-20`。该范围中没有实际结果截图的发票优先逐张重新尝试，不因其他发票的接口拦截记录提前跳过；当前票若仍被接口拦截会如实记录暂缓，并继续下一张。已有结果截图仍跳过，范围之外的待处理发票随后继续。此选项仅用于明确授权的重新处理，监控不得自行启动或重置预算。

临时图片保留：仅在当前提示为“请输入验证码文字”时保存验证码图片，颜色或未知提示只刷新，不写图片。成功归档且回读通过后清理该票在 `output/resume` 的所有临时图片，PDF对应文件夹的正式结果截图保留；失败票保留已记录的普通文字验证码和错误现场图片。`node scripts/resume_image_retention.js` 清理历史文件，只作用于resume根目录的图片：删除已正式归档票的临时图片和未用于已记录普通文字识别的验证码图片，保留其他错误图片、JSON及文本。后台运行时保护当前票和最近2分钟写入的文件。逐文件清理清单保存于 `output/diagnosis/resume-image-cleanup-*.json`。

查验入口使用 `https://inv-veri.chinatax.gov.cn/fpcygzfw/national-invoice-check`。新版表单通过日期控件选择开票日期；不会返回旧版或沿用旧版地区接口。验证码接口未返回有效图片时保留诊断，在同一标签页最多刷新3次；仍失败则暂缓当前票并继续下一张，网络刷新不消耗或重置验证码识别预算，已有正式截图仍跳过。

验证码中文筛选：提示仍须为“请输入验证码文字”。模型看到任意汉字时返回 `CHINESE`，本地同时拒绝任何含汉字的回答；这些情况刷新图片、不提交、不消耗每票3次有效候选预算。仅接受完整英文字母/数字答案，保留大小写。筛选刷新仍受10秒间隔和每轮40次上限约束。运行中的Node进程不会热加载代码，规则从下次启动生效。

中文漏检防护：先独立检查图片是否含汉字并完整抄录全部字符，再进行验证码识别。检查明确无中文、字符数与完整抄录一致、两次结果逐字一致才生成有效候选；中文、未知、格式异常、识别不一致均刷新且不消耗3次预算。内容检查结果保存在重试记录的 `content_check`。该防护仍依赖视觉模型，不保证中文零漏检；相较单次识别会增加一次模型请求，且不一致时采用保守刷新。

## 可移植的 Codex 技能

仓库内的 [pdf-invoice-verification](skills/pdf-invoice-verification/SKILL.md) 包含断点续跑、持久化预算、队列、逐票截图归档和OCR复核流程。复制该完整目录至 Codex 技能目录后，以 `$pdf-invoice-verification` 调用，并明确指定本地项目及PDF目录。

首次使用请读 [环境准备及当前移植限制](skills/pdf-invoice-verification/references/setup.md)。技能不含密钥、票据、截图或业务清单；新电脑需自行配置依赖和本地凭据。当前工作区归档器需要特定目录布局、manifest及坐标OCR，不能把安装技能等同于任意PDF目录立即一键运行。
