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

- 仅在可见提示严格为“请输入验证码文字”时调用模型；红色、蓝色或未知提示先刷新，最多刷新 40 次
- 仅接受 3–8 个英文字母，保留大小写；含中文、数字、解释或 UNKNOWN 的输出均按识别失败刷新重试
- `--max-captcha-attempts` 默认 3，允许 1–3；每张发票最多识别 3 次，包含识别为空、接口暂时失败和网站拒绝后的重试，不再通过重开页面倍增次数
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

该续跑入口用于现有工作目录，依赖上一级目录的 `查验程序/invoice_check.py`、`.核对工作/.venv/bin/python` 与已采集清单；这些本地发票资料及辅助环境不包含在仓库中。通用抽取和查验仍使用前述命令。

`node scripts/resume_pending.js` 读取上一级目录 `.核对工作/manifest.json`，仅处理没有实际结果截图的发票。默认在后台浏览器的同一个标签页中处理全部发票，不弹出浏览器窗口，不使用日常工作浏览器的用户配置。

验证码刷新至少间隔10秒，查验提交至少间隔65秒。识别到一分钟限流或访问频繁提示（包括网页弹窗与原生 alert）后，暂停65秒再在同一标签页刷新，继续当前发票；连续限流等待逐步延长，最长5分钟。每张发票的3次识别预算在限流续跑时保留。每日查验次数上限仍会停止，不按一分钟限流重试。

进度和日志保存于 `output/resume/run-status.json`、`output/resume/results.json`、`output/resume/run.log`。运行PID保存于 `output/resume/runner.pid`，已有实例时拒绝重复启动；可向该PID发送SIGTERM停止。已有结果截图继续按原PDF文件名目录归档。
