# WeChat Selkies - 本地远程客户端

[wechat-selkies](https://github.com/nickrunning/wechat-selkies) 的本地远程客户端，用于连接 wechat-selkies 服务并在本机以桌面应用形式使用网页版微信/QQ。

## 功能

- **多连接管理**：保存多个 wechat-selkies 连接（名称、地址、SSL/浏览器选项），支持添加、编辑、删除、设为默认
- 在应用内新窗口打开微信页面，或按连接配置使用系统默认浏览器打开
- **剪贴板共享**：支持与 Docker 内 wechat-selkies 共享剪贴板，文字和图片可在本机复制后于网页版微信中粘贴发送
- **文件拖入上传**：支持将本机文件拖入窗口，自动上传到 Docker 内部，便于在微信中发送文件
- **账号密码认证（可选）**：连接时可配置登录用户名与密码，打开网页时自动使用 HTTP Basic 认证（适用于 wechat-selkies 配置了 PASSWORD 等鉴权时）
- 每个连接可单独设置：忽略 SSL 证书错误、是否用系统浏览器打开
- 设置持久化保存
- 可选系统托盘（需放置 `assets/tray.png`）

## 环境要求

- **系统**（任选其一）：
  - **Windows**：Windows 10 或 Windows 11（x64）
  - **macOS**：macOS 10.15 (Catalina) 及以上，支持 Intel 与 Apple Silicon (ARM64)
  - **Linux**：主流发行版（如 Ubuntu 20.04+、Debian 11+、Fedora 36+ 等），x64 或 ARM64；使用 AppImage 时部分系统需安装 `libfuse2`
- **Node.js**：18 及以上（仅从源码运行或本地构建时需要）
- **wechat-selkies 服务**：已在 Docker 或 Linux 服务器上运行，且本机可访问其 HTTPS 地址（通常为 `https://IP或域名:3001`）

## 快速开始

### 方式一：安装依赖后运行（开发）

```bash
npm install
npm start
```

### 方式二：打包为安装包

```bash
npm install
npm run build
```

安装包输出在 `dist/` 目录，可分发安装。

## 全平台安装包构建说明

需先安装依赖：`npm install`。以下命令在对应系统上执行，生成的安装包在 `dist/` 目录。

| 平台 | 命令 | 产出说明 |
|------|------|----------|
| **Windows** | `npm run build` 或 `npm run build:win` | `dist/` 下生成 NSIS 安装包（.exe），支持选择安装路径。 |
| **macOS** | `npm run build:mac` | 在 macOS 上执行，生成 `.dmg` 镜像；需 Xcode 命令行工具（`xcode-select --install`）。 |
| **Linux** | `npm run build:linux` | 在 Linux 上执行，生成 `.AppImage` 单文件可执行；部分发行版需安装 `libfuse2`（如 Ubuntu：`sudo apt install libfuse2`）。 |
| **当前平台** | `npm run build:dir` | 仅生成未打包的可运行目录（如 Windows 的 `win-unpacked`），便于本地调试。 |

**一次性构建多平台（需在各自系统上分别执行）**：

- 在 Windows 上：`npm run build:win`
- 在 macOS 上：`npm run build:mac`
- 在 Linux 上：`npm run build:linux`

若在 **同一台机器** 上希望一条命令打出多平台包，可执行：

```bash
npm run build:all
```

`build:all` 会根据当前操作系统生成当前平台安装包；要得到 Windows / macOS / Linux 三种安装包，仍需在各自系统（或 CI 中对应环境）下分别执行上述 `build:win` / `build:mac` / `build:linux`。

### GitHub Actions 自动构建

仓库内已配置 GitHub Actions（`.github/workflows/build.yml`），在以下情况会自动构建全平台安装包：

- **push** 到 `main` 或 `master` 分支
- **pull_request** 指向 `main` / `master`
- 发布 **Release**（发布新版本时）

每次运行会在 Windows / macOS / Linux 三个 runner 上并行执行，生成对应平台的安装包并上传为 Artifacts（`installers-win`、`installers-mac`、`installers-linux`）。在 Actions 页面对应 run 的摘要页可下载各平台产物。

## 界面展示

主界面包含：**已保存的连接** 列表（名称、地址、默认标签及「连接」「编辑」「删除」等操作）、右上角 **「+ 添加连接」**、**使用说明** 区域（含部署说明链接、剪贴板与文件拖入说明）、页脚 **版本号** 与相关链接。点击「连接」可在应用内或系统浏览器打开 wechat-selkies 网页；添加/编辑连接在弹窗中配置名称、服务地址、可选账号密码及 SSL/浏览器选项。详见 [使用说明](使用说明.md)。

## 使用说明

1. 确保 wechat-selkies 已在 Docker 或远程服务器上运行，并记下访问地址（如 `https://localhost:3001` 或 `https://服务器IP:3001`）。
2. 启动本客户端，点击「添加连接」填写名称与服务地址，并设置是否忽略 SSL、是否用系统浏览器打开，保存。
3. 在列表中点击某连接的「连接」即可打开该 wechat-selkies 页面；可「编辑」「删除」或「设为默认」。
4. 首次使用若无任何连接，会有一个默认的「本地微信」连接（`https://localhost:3001`），可直接编辑或新增其他连接。

## 项目架构说明

本客户端基于 **Electron** 构建，采用典型的主进程 + 渲染进程架构。

| 层级 | 说明 |
|------|------|
| **主进程 (main.js)** | Node 环境，负责创建窗口、系统托盘、IPC 处理；连接数据的增删改查（通过 electron-store 持久化）；打开 wechat-selkies 网页时创建新 BrowserWindow、注入 SSL 忽略与 HTTP Basic 认证。 |
| **预加载脚本 (preload.js)** | 在渲染进程内运行，通过 `contextBridge` 向页面暴露有限的 `wechatClient` API（如 `getConnections`、`saveConnection`、`openWechat`），避免渲染进程直接访问 Node/Electron，保证安全与兼容。 |
| **渲染进程** | 浏览器环境，由 `index.html` + `styles.css` + `renderer.js` 组成；负责连接列表展示、添加/编辑弹窗、与主进程通过 IPC 通信。 |

**技术栈**：Electron、electron-store（本地配置存储）、原生 HTML/CSS/JS（无前端框架）。打包使用 electron-builder，支持 Windows / macOS / Linux 安装包。

## 项目结构

```
wechat-C/
├── main.js          # Electron 主进程
├── preload.js       # 预加载脚本（暴露安全 API）
├── index.html       # 启动页
├── styles.css       # 样式
├── renderer.js      # 启动页逻辑
├── assets/          # 可选图标（icon.png、tray.png）
├── package.json
├── README.md
└── 使用说明.md
```

## 图标（可选）

在 `assets/` 下可放置：

- `icon.png`：主窗口与微信窗口图标
- `tray.png`：系统托盘图标（存在时启用托盘）
- 打包时若需自定义安装包图标，可在 `package.json` 的 `build.win` 中设置 `"icon": "assets/icon.ico"`

## 相关链接

- [部署说明](https://songxwn.com/cloud-wechat/) - 云端微信在服务器持久化存储和运行
- [wechat-selkies](https://github.com/nickrunning/wechat-selkies) - 基于 Selkies 的 Linux 网页版微信/QQ

## 许可证

MIT
