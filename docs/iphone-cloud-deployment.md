# iPhone 真机安装与云端后端部署

本文档用于第一版外网真机验证：iPhone 通过 HTTPS 访问云服务器上的 FastAPI 后端。

## 1. 前端 iPhone 真机安装

### 环境要求

- macOS
- Xcode，且已登录 Apple ID
- Flutter SDK
- iPhone 已开启“开发者模式”，并信任当前 Apple ID 开发者证书

### 安装依赖

```bash
cd mobile_app
flutter doctor
flutter pub get
```

### 使用云端 API 地址运行到 iPhone

把 `https://api.your-domain.com` 替换成你的后端 HTTPS 域名：

```bash
flutter devices
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

如果需要用 Xcode 调试：

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中完成：

- 将 `Bundle Identifier` 改成唯一值，例如 `com.yourname.verifyVatInvoicesApp`
- 在 `Signing & Capabilities` 里选择你的 Team
- 连接 iPhone 后点击 Run

> iPhone 真机不能使用 `127.0.0.1:8000` 访问电脑或服务器。真机环境必须使用 `--dart-define=API_BASE_URL=...` 指向云端 HTTPS 地址。

## 2. 云服务器后端部署

以下示例以 Ubuntu 22.04/24.04 为准。

### 安装系统依赖

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx git curl
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

### 安装项目依赖

```bash
cd /opt/verify-vat-invoices
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
npm install
npx playwright install --with-deps
```

### 配置环境变量

```bash
cp .env.example .env
```

`.env` 至少配置：

```bash
QWEN_API_KEY=你的千问key
QWEN_INVOICE_MODEL=qwen3.6-plus
OPENROUTER_API_KEY=你的openrouter_key
OPENROUTER_CAPTCHA_MODEL=google/gemini-3-flash-preview
API_SECRET_KEY=一段长随机密钥
APP_ADMIN_USERNAME=admin
APP_ADMIN_PASSWORD=强密码
```

可选配置：

```bash
APP_DATA_DIR=/opt/verify-vat-invoices/app_data
APP_DATABASE_URL=sqlite:////opt/verify-vat-invoices/app_data/app.db
```

### 本机验证后端

```bash
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

健康检查：

```bash
curl http://127.0.0.1:8000/api/health
```

预期返回：

```json
{"status":"ok","database":"ok","worker":"running"}
```

## 3. systemd 与 Nginx

仓库提供两个模板：

- `docs/deploy/verify-vat-invoices.service.example`
- `docs/deploy/nginx.verify-vat-invoices.conf.example`

部署时需要替换模板中的：

- `/opt/verify-vat-invoices`
- `api.your-domain.com`
- `www-data` 或你的运行用户

安装服务示例：

```bash
sudo cp docs/deploy/verify-vat-invoices.service.example /etc/systemd/system/verify-vat-invoices.service
sudo systemctl daemon-reload
sudo systemctl enable --now verify-vat-invoices
sudo systemctl status verify-vat-invoices
```

安装 Nginx 示例：

```bash
sudo cp docs/deploy/nginx.verify-vat-invoices.conf.example /etc/nginx/sites-available/verify-vat-invoices
sudo ln -s /etc/nginx/sites-available/verify-vat-invoices /etc/nginx/sites-enabled/verify-vat-invoices
sudo nginx -t
sudo systemctl reload nginx
```

HTTPS 推荐用 Let’s Encrypt：

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.your-domain.com
```

## 4. 联调验证

1. 浏览器或终端访问：

   ```bash
   curl https://api.your-domain.com/api/health
   ```

2. iPhone 安装 App：

   ```bash
   cd mobile_app
   flutter run -d <你的iPhone设备ID> \
     --dart-define=API_BASE_URL=https://api.your-domain.com
   ```

3. 在 iPhone 上验证：

   - 登录管理员账号
   - 任务页能加载
   - 上传 PDF 能创建任务
   - 任务详情能展示进度和结果
   - 台账页能看到核验成功记录
   - 导出记录页能看到导出任务

4. 查看服务日志：

   ```bash
   journalctl -u verify-vat-invoices -f
   tail -f app_data/logs/app.log
   ```

## 5. 注意事项

- Nginx 需要允许上传大文件，模板已配置 `client_max_body_size 60m`。
- iPhone 真机建议只连接 HTTPS API，不建议在 iOS 里放开 HTTP 明文访问。
- 云服务器上的 Playwright headless 可能被税站网络或风控影响；如果核验不稳定，可以保留 API 在云端、把核验 worker 放在内网机器作为后续方案。
- SQLite 适合第一版单人或小规模使用；多人并发上传时建议升级 PostgreSQL。
