import '../models/connection.dart';

/// Selkies 预设注入脚本生成器。
///
/// Selkies 网页客户端（selkies-web-core + selkies-dashboard）把全部串流设置
/// 存在 `localStorage`，键 = `<origin+path 清洗>_<key>`（见上游
/// `lib/util.js#getStorageAppName`），core 在连接建立时从这些键组装首个
/// `SETTINGS` 负载发给服务端（见 `selkies-ws-core.js` / `selkies-wr-core.js`）。
///
/// 本生成器把首页链接前配置的 [StreamPreset] 翻译成一段文档起始（document-start）
/// 注入脚本：在 Selkies 脚本运行前预写这些键，使服务端按预设建立会话，
/// 打破“设置不匹配→不停重连→页内设置打不开→改不了”的死循环。
/// 链接后页内修改不受影响：脚本只覆盖预设有值的键，无值键保持不动。
///
/// 反向同步：退出 WebView 时通过 [readbackScript] 读回页内 localStorage，
/// 经 [mergeReadback] 合并进预设，使链接后修改在首页持久化。
class SelkiesPresetScript {
  SelkiesPresetScript._();

  /// 需要追踪回读的 Selkies 键（去命名空间前缀）。
  ///
  /// 子集原则：只回读“用户在页内亲手改过”的键。Selkies 的 core/dashboard
  /// 会自发写很多派生键（如 sanitize 回填、HiDPI 派生、rememberCcStart），
  /// 全量回读会把派生值误认为用户选择。追踪做法见 [build]：注入脚本监听
  /// `message` 事件，只记录 dashboard 发出的用户意图消息携带的键。
  static const trackedKeys = <String>{
    'stream_mode',
    'encoder',
    'encoder_rtc',
    'webcam_encoder',
    'video_fullcolor',
    'h264_fullcolor',
    'video_10bit',
    'framerate',
    'rate_control_mode',
    'video_bitrate',
    'video_crf',
    'h264_crf',
    'video_streaming_mode',
    'h264_streaming_mode',
    'jpeg_quality',
    'use_paint_over_quality',
    'video_paintover_crf',
    'h264_paintover_crf',
    'video_paintover_burst_frames',
    'paint_over_jpeg_quality',
    'use_cpu',
    'cpu_encode_threading',
    'audio_bitrate',
    'manual_resolution',
    'is_manual_resolution_mode',
    'isManualResolutionMode',
    'manual_width',
    'manualWidth',
    'manual_height',
    'manualHeight',
    'scaleLocallyManual',
    'useCssScaling',
    'force_aligned_resolution',
    'scaling_dpi',
    'antiAliasingEnabled',
    'use_browser_cursors',
    'raw_pointer_motion',
    'mac_cmd_as_ctrl',
    'isGamepadEnabled',
    'gamepad_rumble',
    'clipboard_in_enabled',
    'clipboard_out_enabled',
    'clipboard_seamless',
    'enable_binary_clipboard',
    'keyboard_shortcuts',
    'trackpadMode',
    'trackpad_speed',
    'print_auto',
    'stats_strip',
  };

  static String? _tri(TriState v) =>
      v == TriState.serverDefault ? null : (v == TriState.on ? 'true' : 'false');

  /// 把 [preset] 翻译为 `{selkiesKey: value}`（不含命名空间前缀）。
  ///
  /// 返回空 map 表示无显式预设，调用方应跳过注入。
  /// 键名前缀与 `_pick` 覆盖、`_explicit_choice` 标记由注入脚本统一处理。
  /// 旧版 Selkies（linuxserver 下发包）键名不同（`h264_*`、`encoder_rtc`、
  /// `is_manual_resolution_mode`），此处同时写新旧两套键，注入脚本双命名
  /// 空间双写，保证新旧前端都命中。
  static Map<String, String> toEntries(StreamPreset preset) {
    final m = <String, String>{};
    void tri(String k, TriState v) {
      final s = _tri(v);
      if (s != null) m[k] = s;
    }

    switch (preset.transport) {
      case StreamTransport.websockets:
        m['stream_mode'] = 'websockets';
        break;
      case StreamTransport.webrtc:
        m['stream_mode'] = 'webrtc';
        break;
      case StreamTransport.serverDefault:
        break;
    }
    switch (preset.encoder) {
      case SelkiesEncoder.serverDefault:
        break;
      case SelkiesEncoder.h264encStriped:
        m['encoder'] = 'h264enc-striped';
        break;
      default:
        m['encoder'] = preset.encoder.name;
    }
    // 旧版别名：RTC 编码器键为 encoder_rtc（x264enc/nvh264enc/vp8enc）
    final enc = m['encoder'];
    if (enc != null) {
      m['encoder_rtc'] = switch (enc) {
        'h264enc' => 'x264enc',
        'h264enc-striped' => 'x264enc-striped',
        'vp8enc' => 'vp8enc',
        // 旧版无 h265/vp9/av1/jpeg RTC 键，退回 x264enc
        _ => 'x264enc',
      };
    }
    if (preset.webcamEncoder != WebcamEncoder.serverDefault) {
      m['webcam_encoder'] = preset.webcamEncoder.name;
    }
    tri('video_fullcolor', preset.fullColor);
    // 旧版别名：h264_fullcolor
    tri('h264_fullcolor', preset.fullColor);
    tri('video_10bit', preset.tenBit);
    if (preset.framerate != null) {
      // -1 = 跟随显示器刷新率（Selkies 约定 'display'）
      m['framerate'] =
          preset.framerate! < 0 ? 'display' : preset.framerate.toString();
    }
    switch (preset.rateControl) {
      case RateControl.cbr:
        m['rate_control_mode'] = 'cbr';
        break;
      case RateControl.crf:
        m['rate_control_mode'] = 'crf';
        break;
      case RateControl.serverDefault:
        break;
    }
    if (preset.videoBitrate != null) {
      m['video_bitrate'] = preset.videoBitrate.toString();
    }
    if (preset.videoCrf != null) m['video_crf'] = preset.videoCrf.toString();
    // 旧版别名：h264_crf / h264_streaming_mode / h264_paintover_crf
    if (preset.videoCrf != null) m['h264_crf'] = preset.videoCrf.toString();
    tri('video_streaming_mode', preset.turbo);
    tri('h264_streaming_mode', preset.turbo);
    if (preset.jpegQuality != null) {
      m['jpeg_quality'] = preset.jpegQuality.toString();
    }
    tri('use_paint_over_quality', preset.paintOver);
    if (preset.paintoverCrf != null) {
      m['video_paintover_crf'] = preset.paintoverCrf.toString();
      m['h264_paintover_crf'] = preset.paintoverCrf.toString();
    }
    if (preset.paintoverBurst != null) {
      m['video_paintover_burst_frames'] = preset.paintoverBurst.toString();
    }
    if (preset.paintoverJpeg != null) {
      m['paint_over_jpeg_quality'] = preset.paintoverJpeg.toString();
    }
    tri('use_cpu', preset.useCpu);
    tri('cpu_encode_threading', preset.cpuThreading);
    if (preset.audioBitrate != null) {
      m['audio_bitrate'] = preset.audioBitrate.toString();
    }

    // 分辨率：开 + 宽高有效 → 锁定；关 → 清掉手动键（跟随窗口）；
    // 跟随默认 → 不动。宽高向下取偶（Selkies 要求偶数）。
    if (preset.manualResolution == TriState.on) {
      final w = preset.manualWidth;
      final h = preset.manualHeight;
      if (w != null && w > 0 && h != null && h > 0) {
        m['manual_resolution'] = 'true';
        // 旧版别名（下划线 + 驼峰两套）
        m['is_manual_resolution_mode'] = 'true';
        m['isManualResolutionMode'] = 'true';
        m['manual_width'] = (w ~/ 2 * 2).toString();
        m['manual_height'] = (h ~/ 2 * 2).toString();
        m['manualWidth'] = (w ~/ 2 * 2).toString();
        m['manualHeight'] = (h ~/ 2 * 2).toString();
      }
    }
    tri('scaleLocallyManual', preset.scaleLocally);
    // HiDPI 与 useCssScaling 互为取反（conditional-settings HIDPI_SPEC）。
    if (preset.hidpi != TriState.serverDefault) {
      m['useCssScaling'] = preset.hidpi == TriState.on ? 'false' : 'true';
    }
    tri('force_aligned_resolution', preset.forceAligned);
    switch (preset.uiScaling) {
      case UiScaling.serverDefault:
        break;
      case UiScaling.p100:
        m['scaling_dpi'] = '96';
        break;
      case UiScaling.p125:
        m['scaling_dpi'] = '120';
        break;
      case UiScaling.p150:
        m['scaling_dpi'] = '144';
        break;
      case UiScaling.p175:
        m['scaling_dpi'] = '168';
        break;
      case UiScaling.p200:
        m['scaling_dpi'] = '192';
        break;
      case UiScaling.p225:
        m['scaling_dpi'] = '216';
        break;
      case UiScaling.p250:
        m['scaling_dpi'] = '240';
        break;
      case UiScaling.p275:
        m['scaling_dpi'] = '264';
        break;
      case UiScaling.p300:
        m['scaling_dpi'] = '288';
        break;
    }
    tri('antiAliasingEnabled', preset.antiAliasing);
    tri('use_browser_cursors', preset.nativeCursor);
    tri('raw_pointer_motion', preset.rawPointer);
    tri('mac_cmd_as_ctrl', preset.macCmdAsCtrl);

    // 流开关：video/audio/microphone/webcam 无持久化键，攒成一条内部键，
    // 由脚本在 core 就绪后 postMessage(pipelineControl) 应用。
    final pipes = <String>[];
    void pipe(String k, TriState v) {
      final s = _tri(v);
      if (s != null) pipes.add('$k:${s == 'true' ? 1 : 0}');
    }

    pipe('video', preset.video);
    pipe('audio', preset.audio);
    pipe('microphone', preset.microphone);
    pipe('webcam', preset.webcam);
    if (pipes.isNotEmpty) m['__selkies_preset_pipeline'] = pipes.join(',');

    tri('isGamepadEnabled', preset.gamepad);
    tri('gamepad_rumble', preset.gamepadRumble);
    tri('clipboard_in_enabled', preset.clipboardUp);
    tri('clipboard_out_enabled', preset.clipboardDown);
    tri('clipboard_seamless', preset.clipboardSeamless);
    tri('enable_binary_clipboard', preset.clipboardBinary);
    tri('keyboard_shortcuts', preset.shortcuts);
    tri('trackpadMode', preset.trackpad);
    if (preset.trackpadSpeed != null) {
      m['trackpad_speed'] = preset.trackpadSpeed.toString();
    }
    tri('print_auto', preset.printAuto);
    tri('stats_strip', preset.statsStrip);
    return m;
  }

  /// 生成 document-start 注入脚本；[preset] 无显式值时返回 null（跳过注入）。
  ///
  /// 脚本行为：
  /// 1. 按 Selkies 规则派生命名空间并预写每个键，同时删除同键 `_pick`
  ///    残留（held-settings fallback/tab 残留会覆盖用户选择）；
  /// 2. 给条件设置写 `<key>_explicit_choice=true`（conditional-settings 梯子）；
  /// 3. `manualResolution=off` 时删手动分辨率三键（回到跟随窗口）；
  /// 4. `__selkies_preset_pipeline` 在 core 就绪后转为 pipelineControl 消息，
  ///    覆盖服务端 `*_on_start` 默认。
  /// 生成注入脚本。
  ///
  /// [clientOwnsClipboard] = 客户端完全接管剪贴板：强制关闭页面自带同步
  /// （`clipboard_in_enabled` 页面读本机推远端、`clipboard_out_enabled` +
  /// `clipboard_seamless` 服务端推送写回本机），改由壳内 hook/按钮独占。
  /// 这两个开关在上游是纯前端行为（见 served bundle `canRead` /
  /// `canWriteLocal`），关掉不影响服务端 `cw`/`cr` 帧能力，壳内通道照常工作。
  static String? build(
    StreamPreset preset, {
    required bool manualOff,
    bool clientOwnsClipboard = false,
  }) {
    final entries = toEntries(preset);
    if (clientOwnsClipboard) {
      // 接管键优先级最高：覆盖用户预设里可能存在的值。
      // clipboard_in_enabled 必须保持 true——上游 sendClipboardData 用它门控
      // 上行发送，置 false 会让壳内推送被静默丢弃；页面的「自动上行读取」
      // 改由 clipboardTakeoverScript() 掐断 navigator.clipboard.read* 来阻止。
      entries['clipboard_in_enabled'] = 'true';
      entries['clipboard_out_enabled'] = 'false';
      entries['clipboard_seamless'] = 'false';
    }
    if (entries.isEmpty && !manualOff) return null;
    final buf = StringBuffer()
      ..writeln('(function(){')
      ..writeln('try{')
      // 双命名空间：新版 Selkies 用 origin+pathname，旧版（linuxserver
      // 下发包，见 served bundle `ua=`/`P0=`）用 href.split('#')[0]。
      // 有 ?token= 等 query 时两者不一致，双写保证两边都命中。
      ..writeln(
          "var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');")
      ..writeln(
          "var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');")
      ..writeln('function K1(k){return ns1+"_"+k;}')
      ..writeln('function K2(k){return ns2+"_"+k;}')
      ..writeln('function W(k,v){')
      ..writeln('try{localStorage.setItem(K1(k),v);}catch(e){}')
      ..writeln('try{localStorage.setItem(K2(k),v);}catch(e){}')
      // 覆盖 fallback/tab 残留：held-settings 把被 hold 的旧值存 `<key>_pick`，
      // 有残留时 core 会读旧值而非预设。
      ..writeln('try{localStorage.removeItem(K1(k)+"_pick");}catch(e){}')
      ..writeln('try{localStorage.removeItem(K2(k)+"_pick");}catch(e){}')
      ..writeln('}')
      // 条件设置显式标记：conditional-settings 梯子只认带标记的存储值。
      ..writeln('function X(k){try{localStorage.setItem(K1(k)+"_explicit_choice","true");}catch(e){}try{localStorage.setItem(K2(k)+"_explicit_choice","true");}catch(e){}}');
    for (final e in entries.entries) {
      if (e.key == '__selkies_preset_pipeline') continue;
      buf.writeln("W('${e.key}','${e.value}');X('${e.key}');");
    }
    if (manualOff) {
      buf
        ..writeln("try{localStorage.removeItem(K1('manual_resolution'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('manual_resolution'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K1('manual_width'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('manual_width'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K1('manual_height'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('manual_height'));}catch(e){}")
        // 旧版键名同步清理（下划线 + 驼峰）
        ..writeln("try{localStorage.removeItem(K1('is_manual_resolution_mode'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('is_manual_resolution_mode'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K1('isManualResolutionMode'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('isManualResolutionMode'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K1('manualWidth'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('manualWidth'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K1('manualHeight'));}catch(e){}")
        ..writeln("try{localStorage.removeItem(K2('manualHeight'));}catch(e){}");
    }
    final pipes = entries['__selkies_preset_pipeline'];
    if (pipes != null) {
      buf
        ..writeln("var P='$pipes'.split(',');")
        ..writeln('function applyPipes(){')
        ..writeln('for(var i=0;i<P.length;i++){')
        ..writeln('var kv=P[i].split(":");if(kv.length<2)continue;')
        ..writeln(
            "window.postMessage({type:'pipelineControl',pipeline:kv[0],enabled:kv[1]==='1'},window.location.origin);")
        ..writeln('}}')
        ..writeln('var n=0;')
        // core 在 DOMContentLoaded 后才监听消息；轮询到 dashboard 回执或超时。
        ..writeln('var t=setInterval(function(){')
        ..writeln('n++;applyPipes();')
        ..writeln('if(n>=20){clearInterval(t);}')
        ..writeln('},500);')
        ..writeln(
            "window.addEventListener('message',function(ev){if(!ev||!ev.data)return;var ty=ev.data.type;if(ty==='sidebarButtonStatusUpdate'||ty==='pipelineStatusUpdate'){clearInterval(t);}});");
    }
    buf
      ..writeln('}catch(e){}')
      ..writeln('})();');
    return buf.toString();
  }

  /// 分辨率请求钳制脚本（document-start，常驻）。
  ///
  /// Selkies 页面监听窗口 resize，向服务端发 `r,<宽>x<高>` 请求改分辨率
  /// （宽高 = 窗口逻辑尺寸 × devicePixelRatio，仅客户端侧 4080 钳制）。
  /// 服务端 MAX_RES 钉死时，超限请求会导致串流管线反复重建失败、WS 断连
  /// 循环（2026-11-09 最大化窗口断连根因）。
  ///
  /// 本脚本 patch `WebSocket.prototype.send` 与 `RTCDataChannel.prototype.send`
  /// （bundle 实锤两条 `r,` 发送路径均在主世界），拦截 `r,` 前缀消息：
  /// 超上限则等比缩小（宽高取偶）后再放行，未超限原样通过——跟随窗口
  /// 行为保留，最大化安全。`__rclamp` 标记防重复 patch。
  ///
  /// 只认 `p[1]` 为 `整数x整数` 结构的消息；同前缀异构消息原样放行。
  static String resolutionClampScript({
    required int maxWidth,
    required int maxHeight,
  }) {
    return '''
(function(){
try{
var MW=$maxWidth,MH=$maxHeight;
function cl(m){
var p=m.split(',');if(p.length<2)return m;
var wh=p[1].split('x');var w=parseInt(wh[0],10),h=parseInt(wh[1],10);
if(!(w>0&&h>0))return m;
if(w<=MW&&h<=MH)return m;
var s=Math.min(MW/w,MH/h);
var nw=Math.max(2,Math.floor(w*s/2)*2),nh=Math.max(2,Math.floor(h*s/2)*2);
p[1]=nw+'x'+nh;return p.join(',');
}
function pt(pr){
if(!pr)return;var os=pr.send;
if(!os||os.__rclamp)return;
pr.send=function(d){
try{if(typeof d==='string'&&d.length>2&&d.charCodeAt(0)===114&&d.charCodeAt(1)===44){d=cl(d);}}catch(e){}
return os.call(this,d);
};
pr.send.__rclamp=1;
}
pt(window.WebSocket&&window.WebSocket.prototype);
pt(window.RTCDataChannel&&window.RTCDataChannel.prototype);
}catch(e){}
})();
''';
  }

  /// 链路吞吐采样脚本（page-context）。
  ///
  /// 背景（2026-11-13）：画面卡在 “Waiting for stream...” 的另一类原因是
  /// 链路吞吐崩塌（Tailscale 直连大包丢包 → 视频大帧传不动），服务端日志
  /// 表现为 `Backpressure TRIGGERED S:707, C:1`。这类问题 ping 延迟正常，
  /// 用户难以自查，因此在页内采样吞吐并据此提示。
  ///
  /// 同源 GET 采样：`fetch` 带 `cache: 'no-store'`，读 [url] 前 [maxBytes]
  /// 字节即中止（AbortController），避免真把大文件下完。返回
  /// `{"ok":bool,"bps":number,"elapsedMs":number,"bytes":number,"rounds":n}`。
  ///
  /// 放在页内而非 Dart 侧：同源请求自动带已有的证书信任与 cookie，且测的
  /// 正是页面实际使用的这条链路（Dart HTTP 走自己的证书栈，结果会偏）。
  static String throughputProbeScript({
    required String url,
    int maxBytes = 262144,
    int rounds = 3,
    int timeoutMs = 6000,
  }) {
    final safeUrl = url.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return '''
(async function(){
try{
var url='$safeUrl',MAX=$maxBytes,ROUNDS=$rounds,TMO=$timeoutMs;
var bytes=0,okCount=0;
var t0=(window.performance||Date).now();
for(var i=0;i<ROUNDS;i++){
var ctl=null,to=null;
try{
ctl=new AbortController();
to=setTimeout(function(){try{ctl.abort();}catch(e){}},TMO);
var r=await fetch(url,{cache:'no-store',credentials:'same-origin',signal:ctl.signal});
if(!r.ok){throw new Error('HTTP '+r.status);}
var rd=r.body&&r.body.getReader?r.body.getReader():null;
if(rd){
var got=0;
while(got<MAX){
var step=await rd.read();
if(step.done)break;
got+=step.value.length;
if(got>=MAX){try{rd.cancel();}catch(e){}break;}
}
bytes+=got;
}else{
var buf=await r.arrayBuffer();
var n=Math.min(buf.byteLength,MAX);
bytes+=n;
}
okCount++;
}catch(e){
}finally{ if(to)clearTimeout(to); }
}
var ms=(window.performance||Date).now()-t0;
if(okCount===0||ms<=0){return JSON.stringify({ok:false,bps:0,elapsedMs:ms,bytes:bytes,rounds:ROUNDS});}
return JSON.stringify({ok:true,bps:Math.round(bytes/(ms/1000)),elapsedMs:Math.round(ms),bytes:bytes,rounds:okCount});
}catch(e){return JSON.stringify({ok:false,bps:0,elapsedMs:0,bytes:0,rounds:0,error:String(e)});}
})();
''';
  }

  /// 重置页面状态脚本：清除当前 origin+path 命名空间下的全部 Selkies 键。
  ///
  /// 背景（2026-11-13）：WKWebView 的 localStorage 跨版本累积残留键
  /// （如 `_encoder=jpeg`、`_pipesnap.video=false`、旧 `_crash_count`），
  /// 会污染页面启动参数，导致建流失败、画面停在 “Waiting for stream...”。
  /// 真浏览器（干净 localStorage）同 URL 正常；清空后客户端也恢复正常。
  ///
  /// 只删两个命名空间前缀下的键（新版 origin+pathname / 旧版 href），
  /// 不碰其它来源的数据。删完由调用方 reload，预设注入会重新写入。
  ///
  /// 返回 `{"removed":N,"ns1":...,"ns2":...}` JSON 字符串。
  static String resetStorageScript() {
    return '''
(function(){
try{
var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
var p1=ns1+'_',p2=ns2+'_';
var kill=[];
for(var i=0;i<localStorage.length;i++){
var k=localStorage.key(i);
if(k&&(k.indexOf(p1)===0||k.indexOf(p2)===0))kill.push(k);
}
for(var j=0;j<kill.length;j++){try{localStorage.removeItem(kill[j]);}catch(e){}}
return JSON.stringify({removed:kill.length,ns1:ns1,ns2:ns2});
}catch(e){return JSON.stringify({removed:0,error:String(e)});}
})();
''';
  }

  /// 追踪脚本（document-start，常驻）：记录页内用户意图修改的键。
  ///
  /// Selkies dashboard 经 `window.postMessage` 把用户操作发给 core
  /// （`settings` 批量、`setManualResolution`、`resetResolutionToWindow`、
  /// `setScaleLocally`、`setUseCssScaling`、`setAntiAliasing` 等）。
  /// 本脚本监听同源消息，把用户意图键记入内部键
  /// `<ns>___selkies_touched`（逗号分隔），回读时只取被触碰过的键。
  /// 流开关 `pipelineControl` 单独记为 `video/audio/microphone/webcam`
  /// 触碰标记，回读时从 `sidebarButtonStatusUpdate` 快照取值。
  static String trackerScript() {
    return '''
(function(){
try{
var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
var TK1=ns1+'___selkies_touched';
var TK2=ns2+'___selkies_touched';
var SNAP1=ns1+'___selkies_pipesnap';
var SNAP2=ns2+'___selkies_pipesnap';
function touched(){try{var a=(localStorage.getItem(TK1)||'').split(',');var b=(localStorage.getItem(TK2)||'').split(',');return a.concat(b).filter(Boolean);}catch(e){return [];}}
function mark(keys){try{var s={};touched().concat(keys).forEach(function(k){if(k)s[k]=1;});var v=Object.keys(s).join(',');localStorage.setItem(TK1,v);localStorage.setItem(TK2,v);}catch(e){}}
window.addEventListener('message',function(ev){
if(!ev||ev.origin!==window.location.origin||!ev.data||typeof ev.data!=='object')return;
var m=ev.data,t=m.type;
if(t==='settings'&&m.settings&&typeof m.settings==='object'){mark(Object.keys(m.settings));}
else if(t==='setManualResolution'){mark(['manual_resolution','is_manual_resolution_mode','isManualResolutionMode','manual_width','manualWidth','manual_height','manualHeight']);}
else if(t==='resetResolutionToWindow'){mark(['manual_resolution','is_manual_resolution_mode','isManualResolutionMode','manual_width','manualWidth','manual_height','manualHeight']);}
else if(t==='setScaleLocally'){mark(['scaleLocallyManual']);}
else if(t==='setUseCssScaling'){mark(['useCssScaling']);}
else if(t==='setAntiAliasing'){mark(['antiAliasingEnabled']);}
else if(t==='setUseBrowserCursors'){mark(['use_browser_cursors']);}
else if(t==='setRawPointerMotion'){mark(['raw_pointer_motion']);}
else if(t==='setMacCmdAsCtrl'){mark(['mac_cmd_as_ctrl']);}
else if(t==='setTrackpadSpeed'){mark(['trackpad_speed']);}
else if(t==='setGamepadRumble'){mark(['gamepad_rumble']);}
else if(t==='gamepadControl'){mark(['isGamepadEnabled']);}
else if(t==='pipelineControl'&&m.pipeline){mark([m.pipeline]);}
else if(t==='audioDeviceSelected'){mark(['__selkies_audio_device']);}
else if(t==='sidebarButtonStatusUpdate'||t==='pipelineStatusUpdate'){
try{var snap=JSON.stringify({video:!!m.video,audio:!!m.audio,microphone:!!m.microphone,webcam:!!m.webcam,gamepad:!!m.gamepad});localStorage.setItem(SNAP1,snap);localStorage.setItem(SNAP2,snap);}catch(e){}
}
});
}catch(e){}
})();
''';
  }

  /// 回读脚本（退出 WebView 前执行一次）：返回 JSON 字符串。
  ///
  /// 只回读被 [trackerScript] 标记为用户触碰过的键（`___selkies_touched`），
  /// 每个键读当前 localStorage 值；流开关从 `___selkies_pipesnap` 快照读。
  /// 返回形如 `{"keys":{"encoder":"h265enc",...},"pipes":{...}}`，
  /// 无触碰时返回 `{"keys":{},"pipes":{}}`。
  static String readbackScript() {
    return '''
(function(){
try{
var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
var keys={};
var touched=[];
try{var a=(localStorage.getItem(ns1+'___selkies_touched')||'').split(',');var b=(localStorage.getItem(ns2+'___selkies_touched')||'').split(',');var s={};a.concat(b).filter(Boolean).forEach(function(k){s[k]=1;});touched=Object.keys(s);}catch(e){}
function get(k){try{var v=localStorage.getItem(ns2+'_'+k);if(v!==null)return v;}catch(e){}try{var v2=localStorage.getItem(ns1+'_'+k);if(v2!==null)return v2;}catch(e){}return null;}
for(var i=0;i<touched.length;i++){
var k=touched[i];
if(k==='video'||k==='audio'||k==='microphone'||k==='webcam'||k==='gamepad')continue;
var v=get(k);if(v!==null)keys[k]=v;
}
var pipes={};
try{pipes=JSON.parse(localStorage.getItem(ns2+'___selkies_pipesnap')||localStorage.getItem(ns1+'___selkies_pipesnap')||'{}');}catch(e){pipes={};}
return JSON.stringify({keys:keys,pipes:pipes,touched:touched});
}catch(e){return JSON.stringify({keys:{},pipes:{},touched:[]});}
})();
''';
  }

  /// 清理脚本（回读成功后执行）：删除内部追踪键。
  static String cleanupScript() {
    return '''
(function(){
try{
var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
localStorage.removeItem(ns1+'___selkies_touched');
localStorage.removeItem(ns2+'___selkies_touched');
localStorage.removeItem(ns1+'___selkies_pipesnap');
localStorage.removeItem(ns2+'___selkies_pipesnap');
}catch(e){}
})();
''';
  }

  /// 把回读结果合并进 [base]，返回新预设。
  ///
  /// [keys] 为 `{selkiesKey: stringValue}`（仅用户触碰过的键），
  /// [pipes] 为 `{video/audio/microphone/webcam/gamepad: bool}` 快照，
  /// [touched] 为触碰标记全集（含流开关名）。
  /// 合并规则：触碰过的键按当前值覆盖；`resetResolutionToWindow` 会删掉
  /// manual 三键（回读无值）→ 此时 manualResolution 记为 off（跟随窗口）。
  static StreamPreset mergeReadback(
    StreamPreset base, {
    required Map<String, String> keys,
    required Map<String, bool> pipes,
    required Set<String> touched,
  }) {
    var p = base;
    TriState tri(String? v) {
      if (v == 'true') return TriState.on;
      if (v == 'false') return TriState.off;
      return TriState.serverDefault;
    }

    int? intOf(String? v) => v == null ? null : int.tryParse(v);
    String? s(String k) => keys[k];

    if (touched.contains('stream_mode')) {
      final v = s('stream_mode');
      p = p.copyWith(
          transport: v == 'webrtc'
              ? StreamTransport.webrtc
              : v == 'websockets'
                  ? StreamTransport.websockets
                  : StreamTransport.serverDefault);
    }
    if (touched.contains('encoder')) {
      p = p.copyWith(encoder: switch (s('encoder')) {
        'h264enc' => SelkiesEncoder.h264enc,
        'h265enc' => SelkiesEncoder.h265enc,
        'vp8enc' => SelkiesEncoder.vp8enc,
        'vp9enc' => SelkiesEncoder.vp9enc,
        'av1enc' => SelkiesEncoder.av1enc,
        'h264enc-striped' => SelkiesEncoder.h264encStriped,
        'jpeg' => SelkiesEncoder.jpeg,
        _ => SelkiesEncoder.serverDefault,
      });
    }
    // 旧版：encoder_rtc（x264enc/nvh264enc/vp8enc）
    if (touched.contains('encoder_rtc')) {
      p = p.copyWith(encoder: switch (s('encoder_rtc')) {
        'x264enc' || 'nvh264enc' => SelkiesEncoder.h264enc,
        'vp8enc' => SelkiesEncoder.vp8enc,
        'x264enc-striped' => SelkiesEncoder.h264encStriped,
        _ => SelkiesEncoder.serverDefault,
      });
    }
    if (touched.contains('webcam_encoder')) {
      p = p.copyWith(webcamEncoder: switch (s('webcam_encoder')) {
        'auto' => WebcamEncoder.auto,
        'h264' => WebcamEncoder.h264,
        'h265' => WebcamEncoder.h265,
        'vp8' => WebcamEncoder.vp8,
        'vp9' => WebcamEncoder.vp9,
        'av1' => WebcamEncoder.av1,
        'mjpeg' => WebcamEncoder.mjpeg,
        _ => WebcamEncoder.serverDefault,
      });
    }
    if (touched.contains('video_fullcolor')) {
      p = p.copyWith(fullColor: tri(s('video_fullcolor')));
    }
    // 旧版：h264_fullcolor
    if (touched.contains('h264_fullcolor')) {
      p = p.copyWith(fullColor: tri(s('h264_fullcolor')));
    }
    if (touched.contains('video_10bit')) {
      p = p.copyWith(tenBit: tri(s('video_10bit')));
    }
    if (touched.contains('framerate')) {
      final v = s('framerate');
      p = p.copyWith(
          framerate: () =>
              v == 'display' ? -1 : (v == null ? null : int.tryParse(v)));
    }
    if (touched.contains('rate_control_mode')) {
      p = p.copyWith(
          rateControl: s('rate_control_mode') == 'crf'
              ? RateControl.crf
              : s('rate_control_mode') == 'cbr'
                  ? RateControl.cbr
                  : RateControl.serverDefault);
    }
    if (touched.contains('video_bitrate')) {
      p = p.copyWith(videoBitrate: () => intOf(s('video_bitrate')));
    }
    if (touched.contains('video_crf')) {
      p = p.copyWith(videoCrf: () => intOf(s('video_crf')));
    }
    if (touched.contains('h264_crf')) {
      p = p.copyWith(videoCrf: () => intOf(s('h264_crf')));
    }
    if (touched.contains('video_streaming_mode')) {
      p = p.copyWith(turbo: tri(s('video_streaming_mode')));
    }
    if (touched.contains('h264_streaming_mode')) {
      p = p.copyWith(turbo: tri(s('h264_streaming_mode')));
    }
    if (touched.contains('jpeg_quality')) {
      p = p.copyWith(jpegQuality: () => intOf(s('jpeg_quality')));
    }
    if (touched.contains('use_paint_over_quality')) {
      p = p.copyWith(paintOver: tri(s('use_paint_over_quality')));
    }
    if (touched.contains('video_paintover_crf')) {
      p = p.copyWith(paintoverCrf: () => intOf(s('video_paintover_crf')));
    }
    if (touched.contains('h264_paintover_crf')) {
      p = p.copyWith(paintoverCrf: () => intOf(s('h264_paintover_crf')));
    }
    if (touched.contains('video_paintover_burst_frames')) {
      p = p.copyWith(
          paintoverBurst: () => intOf(s('video_paintover_burst_frames')));
    }
    if (touched.contains('paint_over_jpeg_quality')) {
      p = p.copyWith(
          paintoverJpeg: () => intOf(s('paint_over_jpeg_quality')));
    }
    if (touched.contains('use_cpu')) {
      p = p.copyWith(useCpu: tri(s('use_cpu')));
    }
    if (touched.contains('cpu_encode_threading')) {
      p = p.copyWith(cpuThreading: tri(s('cpu_encode_threading')));
    }
    if (touched.contains('audio_bitrate')) {
      p = p.copyWith(audioBitrate: () => intOf(s('audio_bitrate')));
    }
    // 分辨率：页内“设为手动”写三键；“恢复跟随窗口”删三键。
    // 回读有宽高 → on + 宽高；触碰过但无宽高 → off（跟随窗口）。
    // 旧版键为驼峰 manualWidth/manualHeight/isManualResolutionMode。
    if (touched.contains('manual_width') ||
        touched.contains('manualWidth') ||
        touched.contains('manual_height') ||
        touched.contains('manualHeight') ||
        touched.contains('manual_resolution') ||
        touched.contains('isManualResolutionMode') ||
        touched.contains('is_manual_resolution_mode')) {
      final w = intOf(s('manual_width')) ?? intOf(s('manualWidth'));
      final h = intOf(s('manual_height')) ?? intOf(s('manualHeight'));
      if (w != null && w > 0 && h != null && h > 0) {
        p = p.copyWith(
            manualResolution: TriState.on,
            manualWidth: () => w,
            manualHeight: () => h);
      } else {
        p = p.copyWith(
            manualResolution: TriState.off,
            manualWidth: () => null,
            manualHeight: () => null);
      }
    }
    if (touched.contains('scaleLocallyManual')) {
      p = p.copyWith(scaleLocally: tri(s('scaleLocallyManual')));
    }
    if (touched.contains('useCssScaling')) {
      // HiDPI 与 useCssScaling 互为取反
      final v = s('useCssScaling');
      p = p.copyWith(
          hidpi: v == 'true'
              ? TriState.off
              : v == 'false'
                  ? TriState.on
                  : TriState.serverDefault);
    }
    if (touched.contains('force_aligned_resolution')) {
      p = p.copyWith(forceAligned: tri(s('force_aligned_resolution')));
    }
    if (touched.contains('scaling_dpi')) {
      p = p.copyWith(uiScaling: switch (s('scaling_dpi')) {
        '96' => UiScaling.p100,
        '120' => UiScaling.p125,
        '144' => UiScaling.p150,
        '168' => UiScaling.p175,
        '192' => UiScaling.p200,
        '216' => UiScaling.p225,
        '240' => UiScaling.p250,
        '264' => UiScaling.p275,
        '288' => UiScaling.p300,
        _ => UiScaling.serverDefault,
      });
    }
    if (touched.contains('antiAliasingEnabled')) {
      p = p.copyWith(antiAliasing: tri(s('antiAliasingEnabled')));
    }
    if (touched.contains('use_browser_cursors')) {
      p = p.copyWith(nativeCursor: tri(s('use_browser_cursors')));
    }
    if (touched.contains('raw_pointer_motion')) {
      p = p.copyWith(rawPointer: tri(s('raw_pointer_motion')));
    }
    if (touched.contains('mac_cmd_as_ctrl')) {
      p = p.copyWith(macCmdAsCtrl: tri(s('mac_cmd_as_ctrl')));
    }
    // 流开关：只回读用户触碰过的，从快照取值
    if (touched.contains('video') && pipes.containsKey('video')) {
      p = p.copyWith(video: pipes['video']! ? TriState.on : TriState.off);
    }
    if (touched.contains('audio') && pipes.containsKey('audio')) {
      p = p.copyWith(audio: pipes['audio']! ? TriState.on : TriState.off);
    }
    if (touched.contains('microphone') && pipes.containsKey('microphone')) {
      p = p.copyWith(
          microphone: pipes['microphone']! ? TriState.on : TriState.off);
    }
    if (touched.contains('webcam') && pipes.containsKey('webcam')) {
      p = p.copyWith(webcam: pipes['webcam']! ? TriState.on : TriState.off);
    }
    if (touched.contains('isGamepadEnabled')) {
      // 手柄开关：快照优先（反映 gamepadControl 即时态），存储值兜底
      final v = pipes.containsKey('gamepad')
          ? (pipes['gamepad']! ? TriState.on : TriState.off)
          : tri(s('isGamepadEnabled'));
      p = p.copyWith(gamepad: v);
    }
    if (touched.contains('gamepad_rumble')) {
      p = p.copyWith(gamepadRumble: tri(s('gamepad_rumble')));
    }
    if (touched.contains('clipboard_in_enabled')) {
      p = p.copyWith(clipboardUp: tri(s('clipboard_in_enabled')));
    }
    if (touched.contains('clipboard_out_enabled')) {
      p = p.copyWith(clipboardDown: tri(s('clipboard_out_enabled')));
    }
    if (touched.contains('clipboard_seamless')) {
      p = p.copyWith(clipboardSeamless: tri(s('clipboard_seamless')));
    }
    if (touched.contains('enable_binary_clipboard')) {
      p = p.copyWith(clipboardBinary: tri(s('enable_binary_clipboard')));
    }
    if (touched.contains('keyboard_shortcuts')) {
      p = p.copyWith(shortcuts: tri(s('keyboard_shortcuts')));
    }
    if (touched.contains('trackpadMode')) {
      p = p.copyWith(trackpad: tri(s('trackpadMode')));
    }
    if (touched.contains('trackpad_speed')) {
      final v = s('trackpad_speed');
      p = p.copyWith(
          trackpadSpeed: () => v == null ? null : double.tryParse(v));
    }
    if (touched.contains('print_auto')) {
      p = p.copyWith(printAuto: tri(s('print_auto')));
    }
    if (touched.contains('stats_strip')) {
      p = p.copyWith(statsStrip: tri(s('stats_strip')));
    }
    return p;
  }
}
