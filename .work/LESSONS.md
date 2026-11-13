# LESSONS — Docker-Wechat-Localclient 工作区踩坑台账

> 条目格式:`日期 | 现象 → 根因 → 对策/应用条件`。长篇证据链与部署实锤在思源笔记「wechat-selkies 部署笔记」踩坑记录节(20261104084756-iscp0o2),本台账只留可复用结论。

## 2026-11-13

- **localStorage 残留导致「Waiting for stream...」永久黑屏**:客户端 5.6.7 连上后卡在等待流,同一 URL 真浏览器(camoufox,干净 localStorage)画面正常、容器日志 `START_VIDEO`→`Capture started` 全通、无背压告警。app 的 WKWebView localStorage 里积了 107 个键(跨版本迭代 + 页内改设置 + 服务端 settings 下发覆盖),其中 `_encoder='jpeg'`、`framerate=60`、`___selkies_pipesnap={"video":false,...}` 污染建流参数。**清空后立即恢复**(微信画面正常渲染)。**对策**:连接页加「重置页面状态」按钮(`SelkiesPresetScript.resetStorageScript`,按两个命名空间前缀清键后 reload);排查用 `--dart-define=SELKIES_NO_INJECT=1` 二分注入脚本。**铁律**:客户端类"黑屏但服务端健康"问题,先做「真浏览器同 URL 对照」+「清 localStorage 对照」两步,能省掉大半排查;WKWebView 的持久化状态比浏览器脏得多,跨版本更甚。
- **只做页内 `hidden`/rAF 判断不够**:5.6.6 装后 10h,WebContent 仍涨到 1.59GB(1.79M `CMSampleBuffer`/`CMBlockBuffer`,约 50fps)。WKWebView 在应用失焦/被其它窗口遮挡时可能保持 `document.hidden=false` 且 rAF 继续跑,页内 guard 不触发,Selkies 继续 decode。**对策**:Dart `didChangeAppLifecycleState` 非 `resumed` 30s 后调 `window.__selkiesDecoderGuardSetActive(false)`(强制后台:close 全部 decoder + 丢弃 decode),回前台 `true` 再 close 一次让页面重建。**铁律**:macOS WebCodecs 资源回收不能只信 page visibility,应用生命周期信号必须并上;只用 `ps rss`/页内脚本验证会漏掉这条路径。

## 2026-11-12

- **客户端 WebContent 26h 涨到 2.7GB**:Activity Monitor 里进程名是页面 URL(`https://<host>:13001`),不是 Flutter 主进程;`footprint -p <pid>` 显示 `Malloc Small` 1.9GB + `WebKit Malloc` 723MB,`heap` 显示 3,091,157 个 `CMSampleBuffer`/`CMBlockBuffer`(约 26h×30fps),`WebCodecsVideoFrame` 仅 283 个。**根因**:macOS WebCodecs 在页面隐藏/停止 rAF 时不释放 VideoToolbox/CoreMedia 资源;Selkies 页面(`selkies-core.js`)只停止绘制,仍持续 `VideoDecoder.decode`,decoder 也未在 visibilitychange 时 close。**对策**:document-start 注入 `videoDecoderVisibilityGuardScript`(2026-11-12 已实现),后台关闭全部 `VideoDecoder` 并丢弃 decode,回前台再关一次让页面按自身 `decoder closed → initializeDecoder` 路径重建;Node mock 已验开关/丢弃逻辑,长时间挂机待复测。排查关键:先 `footprint`/`heap` 看归属,别把 WebContent 当成 Flutter 主进程。

## 2026-11-09

- **最大化窗口→WS 反复断开**:Selkies 页面监听 resize 发 `r,<宽>x<高>`(宽高=逻辑尺寸×DPR,Retina ×2),服务端 `MAX_RES=1280x720` 钉死 → 超限请求触发管线反复重建失败,WS 断连循环;非最大化窗口尺寸小,不触发。**对策**:应急=客户端首页「串流预设」手动分辨率=开+1280x720+HiDPI=关(已实测修复);根治=客户端注入钳制脚本(2026-11-09 已实现,`resolutionClampScript` patch WebSocket/RTCDataChannel 的 send,超连接配置上限等比缩小后放行,默认上限 1280x720,零配置)。诊断关键:对照 camoufox 真浏览器同 URL 存活(排除服务端)+ localStorage 回放(排除设置污染)+ 裸 WS 重放 `r,3840x2100`(无视频流时不崩,说明崩因在流式会话中的超限请求)。
- **「用户说调过 X」≠「X 生效」**:两次复测失败皆因 720p 从未进预设——用户在页内/服务端调,而客户端预设只存了 framerate;页内 `is_manual_resolution_mode=false` 与预设 JSON 才是存储态实锤。**铁律**:排查配置类问题先读持久层(plist/localStorage),再听口述;UI 三态开关「开+值」缺一不可(代码路径 `manualResolution == TriState.on` 才写宽高键)。
- **flutter 进程名≠app 显示名**:进程是 `wechat_selkies_client`,pgrep 按显示名搜扑空;App 运行时禁止 `defaults write` 其 domain(NSUserDefaults 内存态退出时覆盖外部写入,且 flutter JSON 值 defaults 解析易失败)。

## 2026-11-10

- **`clipboard_in_enabled=false` 会连自家推送一起杀掉**:上游 `sendClipboardData` 用它门控全部上行(`skip('clipboardSkipInDisabled')`),关掉后壳内显式推送在到达 socket 前就被丢弃,表现像"被远端覆盖"。**对策**:保持 `true`,用 `navigator.clipboard.readText/read` 永不 resolve 来阻止页面**自动**读;只关 `clipboard_out_enabled`/`clipboard_seamless` 阻止下行回写。
- **服务端 settings 会覆盖 document-start 注入**:页面 `handleSettingsMessage` 用服务端下发的值覆盖 localStorage 并回写,所以一次性注入关不掉。**对策**:每秒 pin 一次(`setInterval`)+ 函数级拦截(`clipboard.read*`)。
- **wechat-selkies 0.0.17 是"无 transfer id"的老版剪贴板协议**:`cbs,<mime>,<total>` / `cbd,<b64>` / `cbe`;上游新版才是 `cbs,<tid>,<mime>,<total>`。按新版发 → 服务端 `int('image/png')` 崩 → 整段丢弃。**对策**:照容器内实际源码写协议,别照上游 main。
- **`enable_binary_clipboard` 默认 false**:容器启动未传该参数时,服务端丢弃一切图片剪贴板帧。**对策**:stack 加 `SELKIES_ENABLE_BINARY_CLIPBOARD=true`(settings.py 支持 `SELKIES_` 前缀)。
- **WKWebView 单次 `evaluateJavascript` 塞大 base64 会静默失败**:返回 nil 且不抛错,只看 `err:` 前缀会造成"假成功"。**对策**:>256 KB 一律分片注入,每片检查返回值。
- **版本 bump 要用精确断言**:`sed s/5.5.1+1/5.6.0+1/` 在文件已是 5.5.2+1 时静默无操作,导致 tag 版本与产物不符、装的还是旧构建。**对策**:bump 后 `grep '^version'` 确认,并用 `python` 断言原值存在。
- **诊断优先于推断**:剪贴板图片排查绕了三轮(猜 gating / 猜大小 / 猜协议),最后靠 `docker logs` 一行 `Invalid cbs message` 定位。**对策**:协议类问题第一时间抓服务端日志与容器内实际源码。

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
