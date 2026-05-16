# verify_vat_invoices_app

发票核验财务工作台移动端，支持任务上传、任务进度、台账、导出记录和系统配置。

## iPhone 真机运行

真机连接云端后端时，必须通过 `--dart-define=API_BASE_URL=...` 指定 HTTPS API 地址：

```bash
flutter pub get
flutter devices
flutter run -d <你的iPhone设备ID> \
  --dart-define=API_BASE_URL=https://api.your-domain.com
```

如果没有传入 `API_BASE_URL`：

- Android 模拟器默认访问 `http://10.0.2.2:8000`
- macOS / iOS / 其他平台默认访问 `http://127.0.0.1:8000`

iPhone 真机上的 `127.0.0.1` 是手机本机，不是电脑或云服务器，因此真机调试建议始终传入云端 HTTPS 地址。

## Xcode 打开

```bash
open ios/Runner.xcworkspace
```

在 Xcode 中设置唯一 `Bundle Identifier`，选择你的 Apple Developer Team 后运行到 iPhone。
