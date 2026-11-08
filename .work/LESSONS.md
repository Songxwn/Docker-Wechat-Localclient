# LESSONS — Docker-Wechat-Localclient 工作区踩坑台账

> 条目格式:`日期 | 现象 → 根因 → 对策/应用条件`。长篇证据链与部署实锤在思源笔记「wechat-selkies 部署笔记」踩坑记录节(20261104084756-iscp0o2),本台账只留可复用结论。

## 2026-11-08

- **NSPasteboard MIME≠UTI 静默假成功**:`setData(data, forType: "image/png")` 返回 true 但存成无人识别的自定义类型,任何应用粘不出;`Pasteboard.writeImage` 兜底里 NSImage 解析失败同样静默丢 → snackbar 报成功、剪贴板实为旧图。**对策**:MIME→UTI 映射(public.png/public.jpeg/tiff/gif/bmp/webp)+ 写后读回自检(已实现于 `macos/Runner/MainFlutterWindow.swift` + `writeClipboardImage`)。铁律:剪贴板写入必须读回验证。
- **flutter_inappwebview evaluateJavascript 不 resolve 页内 Promise**:async IIFE 返回值拿回 null(同步返回正常)。**对策**:页脚本把结果写 `window` 变量 + 完成标志,Dart 200ms 轮询取回(三段式:启动/轮询/读结果),不赌 Promise。长任务二进制走 `callHandler` 事件流(如剪贴板分片)。
- **WKWebView 下永远别碰 `navigator.clipboard`**:`permissions.query({name:'clipboard-read'})` 永不 resolve(WebKit 老 bug),Selkies 前端剪贴板栈连带挂死。**对策**:壳内剪贴板全走页外通道——`cw,`/`cb,`/`clipboardUpdateFromUI` 注入、`cr,` 拉取、WebSocket 帧写回(`lib/services/clipboard_bridge.dart`)。
- **fork 仓库 CI 的 push/tag 触发彻底不生效**(build.yml 配置正确、workflow active、重推 tag 无效,历史全靠手动 dispatch)。**对策**:发版 = bump pubspec → tag → `gh workflow run build.yml --ref vX.Y.Z`(dispatch 以 tag 为 ref 时 release job 的 `if: refs/tags/v*` 照样命中);macOS 资产被 CI 重命名为无版本号 `WeChat-Selkies-macos.zip`。
- **Selkies file-manager API 无 delete**(仅 browse/mkdir/zip/upload,dashboard 亦无删除 UI)→ 壳内做不了永久删除,壳内文件面板已摘除。**对策**:文件批量管理唯一入口 = filebrowser 侧车(:13085,挂 wechat 卷);上游项目已归档,留意社区续作镜像。
- **Selkies 页内 fetch 是干净的鉴权通道**:同源自动带 cookie,token 存在时补 `Authorization: Bearer`(与 dashboard 同凭据),Dart 侧无需拼鉴权。
- **SiYuan MCP block insert 报「缺 parentID」时可能已落块**:重试前先查块,否则翻倍;blocks 表对 list 容器/条目/内层段落各记一行(同文多 ID 非重复);嵌套子列表要 `move` 拍平到父级。

## 2026-11-05 及以前

- 服务端碎屏黑底 = Xvfb 超大虚拟屏长跑损坏,`MAX_RES=1280x720` 钉死根治;判服务端 vs 客户端用「两个不同引擎看同一 URL」对照法(详见思源笔记踩坑6/7)。
- 中文输入吃字主犯 = 前端逐键传输,IME 整段提交脚本已内置 fork(踩坑4/跟踪3)。
- 微信缩托盘≠黑屏:先点托盘图标唤回,别急着重启(踩坑7)。
