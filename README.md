# WeChat Selkies - 本地远程客户端（Flutter 全平台版）

[wechat-selkies](https://github.com/nickrunning/wechat-selkies) 的本地远程客户端，用于连接 wechat-selkies 服务并以原生应用形式使用网页版微信/QQ。

本项目是原 [Electron 版本](https://github.com/Songxwn/Docker-Wechat-Localclient) 的 **Flutter 重构**，覆盖 **全平台**：Android、iOS、Windows、macOS、Linux、Web。

## 功能

- **多连接管理**：保存多个 wechat-selkies 连接（名称、地址、SSL / 浏览器选项、可选账号密码），支持添加、编辑、删除、设为默认
- **应用内 WebView**：在应用内直接打开网页版微信（Android / iOS / macOS / Web）
- **系统浏览器打开**：可按连接配置使用系统默认浏览器打开（全平台，Windows / Linux 桌面默认使用此方式）
- **忽略 SSL 证书错误**：适配 wechat-selkies 常见的自签名 HTTPS
- **HTTP Basic 认证**：连接时可配置用户名 / 密码，自动完成鉴权（适用于 wechat-selkies 配置了 PASSWORD 等鉴权时）
- **设置持久化**：基于 `shared_preferences`，跨平台本地保存
- **明暗主题**：跟随系统

## 平台能力说明

| 平台 | 应用内 WebView | 系统浏览器 | 说明 |
| --- | --- | --- | --- |
| Android | ✅ | ✅ | `flutter_inappwebview` |
| iOS | ✅ | ✅ | `flutter_inappwebview` |
| macOS | ✅ | ✅ | `flutter_inappwebview`（WKWebView） |
| Web | ✅ | ✅ | 受浏览器同源策略限制，跨域鉴权可能需服务端配合 |
| Windows | ➖ | ✅ | 桌面端 WebView 暂不支持，自动回退系统浏览器 |
| Linux | ➖ | ✅ | 同上 |

> Windows / Linux 上连接时会自动使用系统默认浏览器打开 wechat-selkies 网页。

## 项目结构

```
lib/
├── main.dart                     # 应用入口、主题、Provider 注入
├── models/
│   └── connection.dart           # 连接数据模型 + 序列化
├── services/
│   ├── storage_service.dart      # shared_preferences 持久化
│   └── platform_service.dart     # 平台能力检测 / 外部浏览器 / URL 规范化
├── providers/
│   └── connection_store.dart     # 连接状态管理（增删改 / 默认）
└── screens/
    ├── home_screen.dart          # 首页：连接列表 + 使用说明 + 页脚
    ├── connection_form_dialog.dart  # 添加 / 编辑连接弹窗
    └── webview_screen.dart       # 应用内 WebView（SSL 忽略 + Basic Auth）
```

## 环境要求

- **Flutter**：3.19 及以上（建议 3.24+）
- **Dart**：3.3 及以上
- **wechat-selkies 服务**：已在 Docker 或 Linux 服务器上运行，本机可访问其地址（通常为 `https://IP或域名:3001`）

## 快速开始

首次克隆本仓库后，由于仅提交了源码与关键平台配置，需先生成各平台的运行脚手架：

```bash
# 生成缺失的平台目录（会保留已存在的 lib/、AndroidManifest.xml 等）
flutter create .

# 拉取依赖
flutter pub get

# 运行（示例：Chrome / Windows / Android）
flutter run -d chrome
flutter run -d windows
flutter run -d <设备ID>
```

> `flutter create .` 不会覆盖已存在的 `lib/`、`pubspec.yaml`、`android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`、`macos/Runner/*.entitlements` 等文件，仅补齐缺失的原生工程文件。

## 构建各平台

```bash
flutter build apk --release        # Android APK
flutter build appbundle --release  # Android AAB（上架 Google Play）
flutter build ios --release        # iOS（需在 macOS + Xcode 签名）
flutter build web --release        # Web
flutter build windows --release    # Windows
flutter build macos --release      # macOS
flutter build linux --release      # Linux（需 GTK 依赖）
```

Linux 构建依赖：

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

### Windows 安装包

CI 会在 `flutter build windows` 之后，使用 [Inno Setup](https://jrsoftware.org/isinfo.php)（脚本 `windows_installer.iss`）编译生成安装程序 `WeChat-Selkies-Client-<版本>-windows-x64-setup.exe`，同时保留便携版 ZIP。本地生成：

```bash
flutter build windows --release
# 需安装 Inno Setup 6，然后：
ISCC.exe /DAppVersion=5.0.0 windows_installer.iss
# 安装包输出在 installer\ 目录
```

## GitHub Actions 自动构建

`.github/workflows/build.yml` 会在 push / PR / 打 tag 时并行构建 **Android、iOS（未签名）、Web、Windows（安装包 + 便携版）、macOS、Linux**，产物上传为 Artifacts。工作流会先执行 `flutter create --platforms=<平台> .` 生成脚手架，再构建。

## 使用说明

1. 确保 wechat-selkies 已在 Docker 或远程服务器上运行，记下访问地址（如 `https://localhost:3001` 或 `https://服务器IP:3001`）。
2. 启动本客户端，点击「添加连接」填写名称与服务地址，按需设置忽略 SSL、系统浏览器打开、账号密码，保存。
3. 在列表中点击「连接」打开该 wechat-selkies 页面；可「编辑」「删除」或「设为默认」。
4. 首次启动会自动创建默认连接「本地微信」（`https://localhost:3001`），可直接编辑或新增。

## 相关链接

- [部署说明](https://songxwn.com/cloud-wechat/) - 云端微信在服务器持久化存储和运行
- [wechat-selkies](https://github.com/nickrunning/wechat-selkies) - 基于 Selkies 的 Linux 网页版微信/QQ
- [原 Electron 版本](https://github.com/Songxwn/Docker-Wechat-Localclient)

## 许可证

MIT
