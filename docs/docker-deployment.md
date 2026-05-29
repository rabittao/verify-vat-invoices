# Docker 部署完整指南

本文档覆盖两部分：

- 后端：使用 Docker 部署 `FastAPI + SQLite + Node/Playwright` 服务。
- 前端：iPhone App 使用 Flutter/Xcode 安装；Docker 不负责 iOS 签名打包。可选地，也可以用 Flutter Web 做浏览器预览。

## 1. 部署结构

推荐第一版结构：

```text
iPhone App
  -> https://api.your-domain.com
     -> Nginx / HTTPS
        -> Docker container: FastAPI / Uvicorn
           -> SQLite: ./app_data/app.db
           -> uploads/jobs/exports/logs: ./app_data/
           -> Python extraction + Node Playwright verification
```

关键原则：

- API Key 不写进镜像，只放在服务器 `.env`。
- SQLite 和任务文件挂载到宿主机 `./app_data`，容器重建不丢数据。
- iPhone 真机必须访问 HTTPS API，不使用 `127.0.0.1`。

## 2. 服务器准备

以下示例以 Ubuntu 22.04/24.04 为准。

如果先在本机 Mac 验证 Docker 构建，请先启动 Docker Desktop，再执行 `docker build` 或 `docker compose` 命令。

### 安装 Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl git nginx
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

重新登录 SSH 后确认：

```bash
docker version
docker compose version
```

### 拉取项目

```bash
sudo mkdir -p /opt/verify-vat-invoices
sudo chown -R $USER:$USER /opt/verify-vat-invoices
cd /opt/verify-vat-invoices
git clone <你的仓库地址> .
```

如果你是手工上传代码，也确保目录结构中包含：

- `Dockerfile`
- `docker-compose.yml`
- `app/`
- `scripts/`
- `requirements.txt`
- `package.json`
- `package-lock.json`

## 3. 配置后端环境变量

复制模板：

```bash
cp .env.example .env
```

编辑 `.env`：

```bash
QWEN_API_KEY=你的千问key
QWEN_INVOICE_MODEL=qwen3.6-plus
QWEN_CAPTCHA_MODEL=qwen3.6-plus
API_SECRET_KEY=一段长随机密钥
APP_ADMIN_USERNAME=admin
APP_ADMIN_PASSWORD=强密码
```

Docker Compose 已默认注入：

```bash
APP_DATA_DIR=/app/app_data
APP_DATABASE_URL=sqlite:////app/app_data/app.db
```

不建议在云服务器里配置 `CHROME_USER_DATA_DIR`，除非你明确知道税站核验需要复用某个浏览器用户目录。

## 4. 构建并启动后端

```bash
docker compose build
docker compose up -d
```

查看状态：

```bash
docker compose ps
docker compose logs -f api
```

健康检查：

```bash
curl http://127.0.0.1:8000/api/health
```

预期：

```json
{"status":"ok","database":"ok","worker":"running"}
```

数据会保存在宿主机：

```text
app_data/
├── app.db
├── uploads/
├── jobs/
├── exports/
└── logs/
```

## 5. Nginx 与 HTTPS

复制 Docker 反代模板：

```bash
sudo cp docs/deploy/nginx.docker.verify-vat-invoices.conf.example \
  /etc/nginx/sites-available/verify-vat-invoices
```

编辑 `/etc/nginx/sites-available/verify-vat-invoices`，替换：

```text
api.your-domain.com
```

启用站点：

```bash
sudo ln -s /etc/nginx/sites-available/verify-vat-invoices \
  /etc/nginx/sites-enabled/verify-vat-invoices
sudo nginx -t
sudo systemctl reload nginx
```

申请 HTTPS 证书：

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.your-domain.com
```

外网验证：

```bash
curl https://api.your-domain.com/api/health
```

## 6. iPhone 前端安装

iPhone App 不通过 Docker 安装。iOS 真机安装需要 macOS、Xcode 和 Apple 签名。

在 Mac 上执行：

```bash
cd mobile_app
flutter doctor
flutter pub get
flutter devices
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

如果用 Xcode：

```bash
cd mobile_app
open ios/Runner.xcworkspace
```

在 Xcode 中完成：

- 设置唯一 `Bundle Identifier`
- 选择你的 Apple Developer Team
- 连接 iPhone 后点击 Run

注意：

- 不传 `API_BASE_URL` 时，iOS 默认会访问 `http://127.0.0.1:8000`，这在 iPhone 上是手机自己，不是服务器。
- 真机建议只连接 HTTPS 地址，不建议为 iOS 放开 HTTP 明文访问。

## 7. 可选：Flutter Web 预览

如果需要在浏览器里预览前端，可在 Mac 或 CI 环境构建 Web：

```bash
cd mobile_app
flutter build web --dart-define=API_BASE_URL=https://api.your-domain.com
```

生成目录：

```text
mobile_app/build/web/
```

可以把该目录部署到任意静态站点服务，例如 Nginx、对象存储或 CDN。

注意：当前产品主目标是移动端/iPhone，Web 预览只用于辅助查看界面。

## 8. 常用运维命令

重启后端：

```bash
docker compose restart api
```

查看日志：

```bash
docker compose logs -f api
tail -f app_data/logs/app.log
```

查看单个任务日志：

```bash
ls app_data/jobs
tail -f app_data/jobs/<job_id>/pipeline.log
```

升级部署：

```bash
git pull
docker compose build
docker compose up -d
```

备份 SQLite 和任务文件：

```bash
tar -czf verify-vat-invoices-backup-$(date +%F).tar.gz app_data
```

## 9. 联调验收清单

- `curl https://api.your-domain.com/api/health` 返回 `status=ok`。
- iPhone App 使用 `--dart-define=API_BASE_URL=https://api.your-domain.com` 安装。
- 管理员账号能登录。
- 任务页能加载，没有 `127.0.0.1` 连接错误。
- 能上传 PDF，且任务进入处理中。
- `app_data/jobs/<job_id>/pipeline.log` 能看到抽取与核验日志。
- 成功核验的数据进入台账。
- 台账详情能打开核验截图。
- 导出记录页能看到导出任务。

## 10. 风险与建议

- 云服务器运行 Playwright 访问税站可能受网络、风控或证书环境影响；如果核验不稳定，建议后续改为“API 上云 + 核验 worker 留在内网机器”的混合方案。
- SQLite 适合第一版单人或小规模使用；多人并发上传时建议升级 PostgreSQL。
- `.env` 不要提交 Git，尤其是 `QWEN_API_KEY`、`API_SECRET_KEY`、`APP_ADMIN_PASSWORD`。
- Nginx 必须配置 `client_max_body_size 60m`，否则批量上传可能被网关拒绝。
