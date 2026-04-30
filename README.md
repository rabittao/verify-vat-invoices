# verify-vat-invoices

批量处理目录中的 PDF 增值税发票：扫描 PDF、渲染页面、调用视觉模型抽取字段、自动访问国家税务总局发票查验平台完成查验，并输出结构化 JSON 结果。

仓库提供完整的本地运行链路，适合在本地或受控环境中批量处理发票文件，并保留中间结果和截图用于复核。

## 项目能力

- 扫描目录中的 `.pdf` 文件，支持递归查找
- 使用 `PyMuPDF` 将 PDF 页面渲染为 PNG
- 使用 `qwen3.5-plus` 抽取增值税发票字段
- 自动规范化发票号码、日期、金额、校验码等字段
- 通过 `Playwright` 驱动浏览器访问税务查验网站
- 使用视觉模型识别验证码
- 输出中间结果、查验结果和过程截图，便于复核
- 提供 `FastAPI + SQLite` 服务层，支持登录、上传任务、台账查询、导出和系统配置
- 提供 `Flutter` 移动端工程骨架，覆盖任务、台账、设置三条主流程

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
3. 将页面图片发送给 `QWEN_INVOICE_MODEL` 指定的视觉模型
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
├── app
│   ├── main.py
│   ├── models.py
│   ├── services.py
│   └── worker.py
├── mobile_app
│   ├── pubspec.yaml
│   └── lib
├── scripts
│   ├── extract_invoices.py
│   ├── run_pipeline.py
│   ├── verify_invoices.js
│   └── verify_invoices_helpers.js
├── tests
└── output
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
| `QWEN_INVOICE_MODEL` | 否 | 发票抽取模型，默认 `qwen3.5-plus` |
| `OPENROUTER_API_KEY` | 是 | 识别验证码，供 `verify_invoices.js` 调用 OpenRouter |
| `OPENROUTER_CAPTCHA_MODEL` | 否 | 验证码 OCR 模型，默认 `google/gemini-3-flash-preview` |
| `CHROME_USER_DATA_DIR` | 否 | 指向本地 Chrome 用户目录，便于复用浏览器证书/信任配置 |
| `API_SECRET_KEY` | 强烈建议 | FastAPI 本地后端签发 bearer token 的签名密钥；未配置时仅会生成当前进程有效的临时随机值 |
| `APP_ADMIN_USERNAME` | 否 | 启动时自动初始化的本地管理员用户名，默认 `admin` |
| `APP_ADMIN_PASSWORD` | 强烈建议 | 启动时自动初始化的本地管理员密码；未配置时仅首次启动会生成临时随机密码并写入日志 |

说明：

- 如果没有 `QWEN_API_KEY`，抽取阶段会直接失败
- 如果没有 `OPENROUTER_API_KEY`，查验阶段中的验证码识别会失败
- 如果税务网站对浏览器信任链要求更严格，推荐配置 `CHROME_USER_DATA_DIR`
- 发布或多人共用环境下，请显式设置 `API_SECRET_KEY` 和 `APP_ADMIN_PASSWORD`，不要依赖临时随机值

## 快速开始

### 启动本地后端 API

```bash
uvicorn app.main:app --reload
```

后端会同时输出两类日志，便于调试上传、抽取、税站核验和入库结果：

- 控制台日志：直接显示在 `uvicorn` 运行窗口。
- 文件日志：`app_data/logs/app.log`。
- 单任务脚本日志：`app_data/jobs/<job_id>/pipeline.log`，包含 `extract_invoices.py` 和 `verify_invoices.js` 的 `stdout/stderr`。

实时查看文件日志：

```bash
tail -f app_data/logs/app.log
```

默认会在本地初始化一个管理员账户，用户名默认是 `admin`。
请在 `.env` 中显式配置 `APP_ADMIN_PASSWORD`；如果未配置，首次启动只会生成一次临时随机密码并写入后端日志。

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

## API 概览

后端主要提供以下接口：

- `POST /api/auth/login`
- `GET /api/tasks`
- `POST /api/tasks`
- `GET /api/tasks/{job_id}`
- `GET /api/tasks/{job_id}/items/{job_item_id}`
- `POST /api/tasks/{job_id}/files/{file_id}/retry`
- `GET /api/invoices`
- `GET /api/invoices/{invoice_id}`
- `POST /api/exports`
- `GET /api/exports`
- `GET /api/admin/system-config`
- `PUT /api/admin/system-config`
- `POST /api/admin/system-config/validate`

## 测试

当前仓库最小后端回归测试入口：

```bash
pytest -q
```

已覆盖：

- 配置优先级
- 任务上传与 worker 入库
- 成功入台账、失败留任务明细
- 台账分页
- 导出任务链路

## Flutter 说明

移动端工程位于 `mobile_app/`，已搭好 `Flutter + Riverpod + go_router + dio + file_picker` 骨架，包含：

- 登录页
- 任务页
- 批量确认页
- 任务详情页
- 台账页
- 台账详情页
- 导出记录页
- 设置页 / 系统配置页

当前机器未安装 Flutter SDK，因此本轮未能本机执行 `flutter pub get`、`flutter test` 或真机调试；后续在具备 Flutter 环境的机器上可直接继续接入 API 和状态逻辑。
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

- 自动识别“红色文字 / 蓝色文字 / 全部文字”三种规则
- 识别不到明确规则时会刷新验证码，不立即提交
- 单页内有提交重试和刷新重试
- `--max-captcha-attempts` 表示页面级重试次数；单页验证码耗尽后，如果还有剩余页面级次数，会重新打开查验页面继续尝试
- 默认使用 `google/gemini-3-flash-preview` 进行验证码 OCR，也可以通过 `OPENROUTER_CAPTCHA_MODEL` 切换 OpenRouter 上的其他模型

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
