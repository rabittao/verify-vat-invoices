# verify_vat_invoices_app

发票核验财务工作台移动端，支持任务上传、任务进度、台账、导出记录和系统配置。

## iPhone 真机运行

真机连接云端后端时，默认访问 `https://api.carfilmmo.com`。如需切换到其他后端，可通过 `--dart-define=API_BASE_URL=...` 指定 HTTPS API 地址：

```bash
flutter pub get
flutter devices
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

如果没有传入 `API_BASE_URL`：

- Android 模拟器默认访问 `http://10.0.2.2:8000`
- iOS 默认访问 `https://api.carfilmmo.com`
- macOS / 其他平台默认访问 `http://127.0.0.1:8000`

iPhone 真机上的 `127.0.0.1` 是手机本机，不是电脑或云服务器，因此 iOS 默认指向云端 HTTPS 地址。

如果域名 HTTPS 临时被网络或备案链路拦截，但 `https://124.221.241.208/api/health` 可以访问，可用 IP 地址做 debug 调试：

```bash
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=https://124.221.241.208 \
  --dart-define=ALLOW_INSECURE_API_CERT=true
```

`ALLOW_INSECURE_API_CERT` 只用于 debug 临时排障，正式打包不要开启。

如果需要完全绕过 HTTPS，先在服务器把 Nginx 的 `80` 端口改成反代后端，再用 HTTP 调试：

```nginx
server {
    listen 80;
    server_name api.carfilmmo.com 124.221.241.208;

    client_max_body_size 60m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

```bash
sudo nginx -t
sudo systemctl reload nginx
```

然后运行：

```bash
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=http://124.221.241.208
```

HTTP 和 `NSAllowsArbitraryLoads` 只用于临时调试，正式发布前应恢复 HTTPS。

## Xcode 打开

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中设置唯一 `Bundle Identifier`，选择你的 Apple Developer Team 后运行到 iPhone。
