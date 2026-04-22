---
name: verify-vat-invoices
description: Use when Codex needs to scan folders for PDF 增值税发票, render pages, extract invoice fields with Qwen vision, verify them on the 国家税务总局发票查验平台, and write structured extracted.json / verified.json results with screenshots for review.
---

# Verify VAT Invoices

批量处理目录中的 PDF 增值税发票，输出可复核的结构化结果和查验截图。

## 何时使用

- 用户要批量扫描目录里的 PDF 发票
- 用户要从 PDF 页面中抽取发票号码、日期、金额、校验码等字段
- 用户要把抽取结果送到国家税务总局发票查验平台继续核验
- 用户要拿到 `extracted.json`、`verified.json` 和浏览器截图做复盘

不要把它用于机票、火车票、出租车票等非增值税票种。

## 主流程

1. 运行 `scripts/run_pipeline.py` 做完整流程
2. Python 阶段用 `scripts/extract_invoices.py`
   - 递归扫描 PDF
   - 用 `PyMuPDF` 渲染页面
   - 调用 Qwen 视觉模型抽取字段
   - 写出 `artifacts/intermediate/extracted.json`
3. Node.js 阶段用 `scripts/verify_invoices.js`
   - 读取 `extracted.json`
   - 访问税务查验站
   - 识别验证码并提交
   - 分类页面终态
   - 写出 `artifacts/intermediate/verified.json` 和 `artifacts/playwright/*.png`

## 运行前提

- Python 依赖已安装：`python3 -m pip install -r requirements.txt`
- Node.js 依赖已安装：`npm install`
- `.env` 中至少有：
  - `QWEN_API_KEY`
  - `OPENROUTER_API_KEY`
- 可选：
  - `OPENROUTER_CAPTCHA_MODEL`
  - `CHROME_USER_DATA_DIR`

如果税站对浏览器信任链要求更严格，优先配置 `CHROME_USER_DATA_DIR` 复用本地 Chrome 用户目录。

## 常用命令

完整流程：

```bash
python3 scripts/run_pipeline.py \
  --input-dir /path/to/pdfs \
  --output-root /path/to/output \
  --recursive
```

只做抽取：

```bash
python3 scripts/extract_invoices.py \
  --input-dir /path/to/pdfs \
  --output-json output/artifacts/intermediate/extracted.json \
  --render-dir output/artifacts/rendered \
  --recursive
```

只做查验：

```bash
node scripts/verify_invoices.js \
  --input-json output/artifacts/intermediate/extracted.json \
  --output-json output/artifacts/intermediate/verified.json \
  --artifacts-dir output/artifacts/playwright \
  --max-captcha-attempts 3
```

语法检查：

```bash
node --check scripts/verify_invoices.js
node --check scripts/verification_result_classifier.js
python3 -m py_compile scripts/extract_invoices.py scripts/run_pipeline.py
```

## 输出约定

关键产物：

- `artifacts/intermediate/extracted.json`
- `artifacts/intermediate/verified.json`
- `artifacts/rendered/*.png`
- `artifacts/playwright/*.png`

`verified.json` 里的常见终态：

- `success`
- `daily_limit_exceeded`
- `data_mismatch`
- `captcha_error`
- `website_system_error`
- `verification_form_not_activated`
- `script_error`
- `skipped`

如果需要字段级解释或状态语义，直接看本仓库的 [README.md](README.md)。

## 当前查验策略

- 提交后会短轮询页面可见内容，而不是只看一次整页文本
- 成功弹层优先级最高；命中 `发票查验明细`、`查验次数`、发票明细字段或 `打印/关闭` 组合后，应直接判为 `success`
- 当 DOM 信号不够稳定时，会用截图做统一兜底：先看局部弹层，再按需补看整页截图
- `daily_limit_exceeded`、`website_system_error` 这类终态命中后，应直接停止后续验证码重试

## 使用时的关键注意点

- 重放历史样本时，输入 JSON 里的 `invoice_date`、`pretax_amount`、`total_amount`、`check_code` 必须和票种要求匹配，否则页面可能停在 `verification_form_not_activated`
- 电子发票不一定填发票代码；但金额字段一定要和页面当前要求一致
- `verified.json` 是后续汇总、筛选和人工复核的主结果文件；不要只看终端日志
- 结果截图是判断“成功弹层 / 次数超限 / 系统异常 / 验证码错误”的第一手证据
