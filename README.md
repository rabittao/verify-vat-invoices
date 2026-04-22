# verify-vat-invoices

批量处理目录中的 PDF 增值税发票：扫描 PDF、渲染页面、调用视觉模型抽取字段、自动访问国家税务总局发票查验平台完成查验，并输出结构化 JSON 结果。

这个仓库当前定位是一个可用的自动化工具，而不是完整产品。它已经具备主流程、错误兜底和结果留痕能力，适合在本地或受控环境中批量处理发票文件。

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
| `OPENROUTER_API_KEY` | 是 | 识别验证码，供 `verify_invoices.js` 调用 OpenRouter |
| `OPENROUTER_CAPTCHA_MODEL` | 否 | 验证码 OCR 模型，默认 `google/gemini-3-flash-preview` |
| `CHROME_USER_DATA_DIR` | 否 | 指向本地 Chrome 用户目录，便于复用浏览器证书/信任配置 |

说明：

- 如果没有 `QWEN_API_KEY`，抽取阶段会直接失败
- 如果没有 `OPENROUTER_API_KEY`，查验阶段中的验证码识别会失败
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

## 真实回归样例

下面只保留经过脱敏后的结论摘要，不在公开仓库中引用本机路径、真实发票号或本地截图产物。

### 样例 1：成功弹层不再误重试

- 某真实电子发票样本在旧逻辑里曾经出现“结果截图已是成功弹层，但最终仍继续重试并落成 `captcha_error`”的问题
- 修复后，同类样本在命中 `发票查验明细` 后会直接判为 `success`
- 本轮回归中，成功信号会同步写入 `result_text`，例如 `matched_status_signal: success 发票查验明细`

### 样例 2：当日查验次数超限会直接终止

- 某真实样本在页面第一次返回时就命中了“超过该张发票当日查验次数(请于次日再次查验)”
- 当前逻辑会直接判为 `daily_limit_exceeded` 并终止，不再继续执行验证码重试

### 样例 3：税站系统异常不再归类成验证码错误

- 对于页面弹窗文本为“系统异常，请重试！(02)”之类的终态
- 当前版本会将其识别为 `website_system_error`
- 这类系统异常不再被统一压成 `captcha_error`

## 发布安全边界

- 公开仓库中只保留 `.env.example`，不要提交真实 `.env`
- `output/`、`tmp/`、截图和本地运行产物不应进入 git
- README 和示例 JSON 应使用脱敏或合成样本，不应包含真实发票号、买卖方名称、纳税人识别号或本机绝对路径

## 本轮修正

这次对仓库做了几项确定性修复：

1. 补齐 `.env.example`，加入 `QWEN_API_KEY` 和可选 `CHROME_USER_DATA_DIR`
2. 将“页面没有发票”从错误改为 `no_invoice_detected`
3. 修正 `--max-captcha-attempts` 的实际行为，使页面级重试真正生效
4. 将验证码 OCR provider 保持为 OpenRouter，并支持通过 `OPENROUTER_CAPTCHA_MODEL` 切换模型
5. 重做提交后的查验结果识别，加入可见弹层优先、短轮询和统一截图兜底
6. 新增 `website_system_error` 终态，避免税站系统异常被误记为 `captcha_error`
7. 新增仓库级 `README.md`

## 已知限制

- 目前只处理增值税发票，不覆盖机票、火车票、出租车票等票种
- 抽取和验证码识别都依赖外部模型服务，准确率受模型和图片质量影响
- 税务网站页面结构如果变化，Playwright 选择器和结果分类规则可能需要同步更新

## 建议后续优化

1. 增加 `README` 之外的操作手册和故障排查文档
2. 把查验脚本中的页面解析和表单逻辑继续拆成更细的模块
3. 如果后续要长期使用，建议补充 CI 和示例数据集
