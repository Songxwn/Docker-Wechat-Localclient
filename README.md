# WeChat Selkies - 本地远程客户端（Flutter 全平台版）

[wechat-selkies](https://github.com/nickrunning/wechat-selkies) 的本地远程客户端，用于连接 wechat-selkies 服务并以原生应用形式使用网页版微信/QQ。

本项目是原 [Electron 版本](https://github.com/Songxwn/Docker-Wechat-Localclient) 的 **Flutter 重构**，覆盖 **全平台**：Android、iOS、Windows、macOS、Linux、Web。

## 功能

- **链接前串流预设**：首页每条连接下直接展开设置分辨率、编码、帧率、码率、音视频开关等全部串流设置，改完即保存，连接时自动生效；打破“设置不匹配→不停重连→页内设置打不开”的死循环（默认全部跟随服务端，不动原有行为）。退出连接时页内修改自动同步回首页预设，下次连接沿用；连接页标题栏 🐞 按钮可查看存储诊断，排查预设未生效
- **分辨率请求自动钳制**：页面跟随窗口发出的 `r,宽x高` 分辨率请求若超过「服务端最大分辨率」（连接表单可选字段，留空 = 1280x720），注入脚本自动等比缩小（宽高取偶）后再放行——服务端 MAX_RES 钉死时，最大化窗口/Retina 高倍率产生的超限请求会导致串流管线反复重建失败、WS 断连循环，此功能免配置根治（跟随窗口行为保留，小窗口请求不受影响）
- **应用内 WebView**：在应用内直接打开网页版微信（Android / iOS / macOS / Web）
- **剪贴板双向同步（客户端接管）**：注入脚本强制关闭 Selkies 页面自带的三项同步（`clipboard_in_enabled` / `clipboard_out_enabled` / `clipboard_seamless`），避免网页层与本客户端互相覆盖——否则页面会自动读取本机剪贴板推送远端、并把服务端推送写回本机，「本机→远端」刚推的内容会被远端回推覆盖。接管后：**上行**用连接页标题栏粘贴按钮（图片经 `pasteboard` 转 PNG，上限 16 MB），文本走 `clipboardUpdateFromUI`，图片走 `cb,<mime>,<base64>`；**下行**只在点击「拉取」按钮（复制图标）时经 `cr` 请求取回，大图分片显示进度条，平时服务端推送只更新缓存不覆盖本机剪贴板。自推送回声（文本/图片签名）会被忽略，不回灌本机。不依赖浏览器 `clipboard-read` 权限，WKWebView / Safari 下同样可用；图片需开启二进制剪贴板
- **后台解码器释放（macOS 内存保护）**：WebCodecs 在页面隐藏/停止绘制时不释放 VideoToolbox/CoreMedia 资源；客户端在页面不可见时关闭 `VideoDecoder` 并丢弃隐藏期间的 decode，回到前台再重建，避免长期挂机后 WebContent 内存涨到数 GB
- **远端文件批量管理**：由部署侧 [filebrowser](https://hub.docker.com/r/filebrowser/filebrowser) 侧车承担（挂同一 `wechat` 数据卷），客户端不内置文件面板；连接可配置 FileBrowser 地址，连接页标题栏文件夹按钮一键跳系统浏览器（已配置且探测可达才显示该按钮）；上游 Selkies file-manager API 无 delete 端点，删除（永久）类操作集中在 filebrowser
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
| Windows | ✅ | ✅ | `flutter_inappwebview_windows`（WebView2，需 WebView2 运行时） |
| Linux | ➖ | ✅ | 暂无 endorsed 实现，自动回退系统浏览器 |

> Windows 应用内浏览器基于 WebView2 运行时：Windows 11 已内置；Windows 10 通常随 Edge 一同安装。安装包会在缺失时自动静默安装 WebView2 运行时。
>
> Linux 上连接时会自动使用系统默认浏览器打开 wechat-selkies 网页。

## 项目结构

```
lib/
├── main.dart                     # 应用入口、主题、Provider 注入
├── models/
│   └── connection.dart           # 连接数据模型 + 串流预设模型 + 序列化
├── services/
│   ├── storage_service.dart      # shared_preferences 持久化
│   ├── platform_service.dart     # 平台能力检测 / 外部浏览器 / URL 规范化
│   ├── clipboard_bridge.dart     # 本机剪贴板 → Selkies 页面注入脚本
│   └── selkies_preset.dart       # 预设→Selkies localStorage 注入脚本生成
├── providers/
│   └── connection_store.dart     # 连接状态管理（增删改 / 默认）
└── screens/
    ├── home_screen.dart          # 首页：连接列表（含串流预设直改）+ 使用说明 + 页脚
    ├── connection_form_dialog.dart  # 添加 / 编辑连接弹窗
    ├── stream_preset_editor.dart # 串流预设编辑器（视频/音频/显示/输入/剪贴板）
    └── webview_screen.dart       # 应用内 WebView（SSL 忽略 + Basic Auth + 预设注入）
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
ISCC.exe /DAppVersion=5.3.0 windows_installer.iss
# 安装包输出在 installer\ 目录
```

## GitHub Actions 自动构建

`.github/workflows/build.yml` 会在 push / PR / 打 tag 时并行构建 **Android、iOS（未签名）、Web、Windows（安装包 + 便携版）、macOS、Linux**，产物上传为 Artifacts。工作流会先执行 `flutter create --platforms=<平台> .` 生成脚手架，再构建。

## 使用说明

1. 确保 wechat-selkies 已在 Docker 或远程服务器上运行，记下访问地址（如 `https://localhost:3001` 或 `https://服务器IP:3001`）。
2. 启动本客户端，点击「添加连接」填写名称与服务地址，按需设置忽略 SSL、系统浏览器打开、账号密码，保存。
3. 在列表中点击「连接」打开该 wechat-selkies 页面；可「编辑」「删除」或「设为默认」。
4. 要把本机内容粘进远端微信：本机复制文字或图片 → 点连接页标题栏的剪贴板按钮（图片优先；上限 16 MB）→ 在远端微信按 Ctrl+V。图片需复制“图片内容”（截图、预览/浏览器里复制）；Finder 里直接复制图片文件只带文件路径，请先打开图片再复制。切回客户端窗口时也会自动同步图片。反向：在远端微信复制文字/图片后，会写回本机剪贴板（图片需在 Selkies 侧栏开启 Image Support，或在预设把“二进制剪贴板”设为开）；若被动同步未生效，点标题栏的「复制」图标主动拉取远端剪贴板到本机。也可在 Selkies 侧栏 Clipboard 文本框粘贴文字后点击框外发送（自动同步依赖浏览器剪贴板权限，失败时用这两条路径）。
5. 要把远端微信收到的文件批量下载/删除：先在连接配置里填 FileBrowser 地址（如 `http://<NAS>:13085`，与微信容器挂同一数据卷），连接页标题栏的文件夹按钮即跳系统浏览器打开；勾选多选即可，删除为永久删除。
6. 首次启动会自动创建默认连接「本地微信」（`https://localhost:3001`），可直接编辑或新增。
7. 若连接后画面不停刷新/重连（多为分辨率、编码等设置与服务端不匹配）：断开回到首页 → 在该连接下展开「串流预设」→ 把可疑项改成与服务端一致的值（如手动分辨率 1280x720，改完即保存）→ 点「连接」重连。链接后仍可在 Selkies 页内继续调整，退出时页内修改会自动同步回首页预设。分辨率类不匹配已被「服务端最大分辨率」自动钳制根治（编辑连接里可改，默认 1280x720），无需再手动锁预设

## 相关链接

- [部署说明](https://songxwn.com/cloud-wechat/) - 云端微信在服务器持久化存储和运行
- [wechat-selkies](https://github.com/nickrunning/wechat-selkies) - 基于 Selkies 的 Linux 网页版微信/QQ
- [原 Electron 版本](https://github.com/Songxwn/Docker-Wechat-Localclient)

## 许可证

MIT
