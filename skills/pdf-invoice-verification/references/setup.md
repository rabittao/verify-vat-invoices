# 跨电脑环境准备

## 安装与定位

将仓库 `skills/pdf-invoice-verification` 整个目录复制到当前 Codex 的技能目录，例如 `~/.codex/skills/pdf-invoice-verification`。技能安装位置与项目位置可以不同。调用时提供本地仓库、PDF目录和输出目标；先检查现有项目及状态，避免误操作另一份同名仓库。

在实际仓库目录安装依赖：

```bash
npm ci
npx playwright install chromium
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt Pillow
```

优先项目锁文件；无锁文件时使用 `npm install`。根据现有 `.env.example` 和代码配置本地凭据，不把真实密钥写进技能。Qwen提取需要 `QWEN_API_KEY`，DeepSeek验证码需要 `DEEPSEEK_API_KEY`；端点和模型名称以当前代码、实际服务能力为准。配置文件必须被Git忽略。

## 工作区归档前提

通用 `run_pipeline.py` 支持指定输入输出目录；带 manifest 的 `resume_pending.js` / `archive_resume_result.py` 使用固定相对布局，详见 [workflow.md](workflow.md)。标准布局为资料根目录内包含名为 `verify-vat-invoices` 的仓库、`.核对工作`、PDF及其同名结果文件夹。

归档器另要求资料根目录的 `.核对工作/.venv/bin/python` 含 Pillow；可在该位置创建独立虚拟环境。不要复制另一台电脑的虚拟环境，应重建。新批次先生成并校核 manifest 和该布局所需坐标OCR，通用提取器目前不会自动产出这两项。

现有锁使用 `fcntl`，队列依赖 `ps`，路径使用 `.venv/bin/python`，适用于macOS/Linux。Windows原生环境需先适配锁、进程检查与解释器路径，或使用WSL并在WSL内重建依赖。当前流程不能宣称原生Windows已验证。

若目录名、票种或票面布局不同，先适配真实代码并测试，再运行一张完成“详情→截图→清单→SHA256”验收。不要通过建立指向错误资料根目录的链接掩盖路径问题。

## 验证和数据边界

安装后先运行项目离线测试，归档环境准备完成后执行 `archive_resume_result.py --check`。只有用户授权实际查验时才做平台单票测试；配置验证不应自动提交票据。

业务文件放在资料根目录或忽略的输出目录。提交Git前检查暂存文件白名单，排除PDF、截图、OCR、manifest、CSV清单、运行日志、补跑计划、浏览器配置和密钥；只提交可复用代码、测试和脱敏文档。
