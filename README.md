# WeChat Selkies - Windows 客户端

[wechat-selkies](https://github.com/nickrunning/wechat-selkies) 的 Windows 桌面客户端，用于连接 wechat-selkies 服务并在本机以桌面应用形式使用网页版微信/QQ。

## 功能

- **多连接管理**：保存多个 wechat-selkies 连接（名称、地址、SSL/浏览器选项），支持添加、编辑、删除、设为默认
- 在应用内新窗口打开微信页面，或按连接配置使用系统默认浏览器打开
- 每个连接可单独设置：忽略 SSL 证书错误、是否用系统浏览器打开
- 设置持久化保存
- 可选系统托盘（需放置 `assets/tray.png`）

## 环境要求

- Windows 10/11
- Node.js 18+（仅开发/构建时需要）
- 已部署的 wechat-selkies 服务（Docker/Linux 等），且本机可访问其 HTTPS 端口（通常 3001）

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

## 使用说明

1. 确保 wechat-selkies 已在 Docker 或远程服务器上运行，并记下访问地址（如 `https://localhost:3001` 或 `https://服务器IP:3001`）。
2. 启动本客户端，点击「添加连接」填写名称与服务地址，并设置是否忽略 SSL、是否用系统浏览器打开，保存。
3. 在列表中点击某连接的「连接」即可打开该 wechat-selkies 页面；可「编辑」「删除」或「设为默认」。
4. 首次使用若无任何连接，会有一个默认的「本地微信」连接（`https://localhost:3001`），可直接编辑或新增其他连接。

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
└── README.md
```

## 图标（可选）

在 `assets/` 下可放置：

- `icon.png`：主窗口与微信窗口图标
- `tray.png`：系统托盘图标（存在时启用托盘）
- 打包时若需自定义安装包图标，可在 `package.json` 的 `build.win` 中设置 `"icon": "assets/icon.ico"`

## 相关链接

- [wechat-selkies](https://github.com/nickrunning/wechat-selkies) - 基于 Selkies 的 Linux 网页版微信/QQ

## 许可证

MIT
