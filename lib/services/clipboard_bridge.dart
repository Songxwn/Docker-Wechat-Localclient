import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// 生成把文本送进 Selkies 页面剪贴板通道的脚本。
///
/// 页面内的 core 监听同源 `window.postMessage`：
/// `{type: 'clipboardUpdateFromUI', text: <string>}`，收到后通过
/// `cw,<base64>` 写入服务端 X 剪贴板。旧版（当前 wechat-selkies）与
/// 新版 Selkies 都保留该消息名。
///
/// 不走 `navigator.clipboard.readText()`，因此不依赖浏览器
/// `clipboard-read` 权限，也不受 WKWebView 的 focus 手势限制。
String buildClipboardUpdateScript(String text) {
  // jsonEncode 负责引号、反斜杠、换行、控制字符的转义；
  // 页面自己取 location.origin，避免把 origin 硬编码进脚本。
  final literal = jsonEncode(text);
  return '(function(){try{'
      // 记录本次自推送的文本签名：服务端把它广播回来时 hook 忽略，
      // 避免「刚推上去的内容又被回推覆盖本机剪贴板」。
      'window.__selkiesClipSelfPush=$literal;'
      'window.postMessage({type:"clipboardUpdateFromUI",text:$literal},'
      'window.location.origin);'
      'return "ok";'
      '}catch(e){return "err:"+e;}})();';
}

const String kClipboardTextHandler = 'selkiesClipboardText';
const String kClipboardImageHandler = 'selkiesClipboardImage';

/// 在页面文档起始挂 WebSocket 观察器：
/// 1. 暴露 Selkies 数据 socket（图片上行需要直接发 `cb`）。
/// 2. 监听服务端推来的剪贴板消息，交给 Flutter 写本机剪贴板。
/// 3. 把最近一次收到的剪贴板缓存进 `window.__selkiesClip`（带递增序号
///    `__selkiesClipSeq`），供「拉取远端剪贴板」按钮超时回退。
///
/// 服务端消息：`clipboard,<b64>`（文本）、`clipboard_binary,<mime>,<b64>`，
/// 以及大内容的 `clipboard_start,<mime>,<total>` / `clipboard_data,<b64>`
/// / `clipboard_finish` 分片。旧版页面自己也会写剪贴板，我们只是额外
/// 通过 `flutter_inappwebview.callHandler` 走原生兜底（WKWebView 下更可靠）。
String clipboardSocketHookScript() => '''
(function(){
  if (window.__selkiesSocketHookInstalled) return;
  window.__selkiesSocketHookInstalled = true;

  function call(name, a, b) {
    try {
      if (window.flutter_inappwebview &&
          window.flutter_inappwebview.callHandler) {
        if (b === undefined) {
          window.flutter_inappwebview.callHandler(name, a);
        } else {
          window.flutter_inappwebview.callHandler(name, a, b);
        }
      }
    } catch (e) {}
  }
  function bytesFromB64(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function textFromBytes(bytes) {
    return new TextDecoder('utf-8').decode(bytes);
  }
  function b64FromBytes(bytes) {
    var s = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(s);
  }
  function joinBytes(a, b) {
    var out = new Uint8Array(a.length + b.length);
    out.set(a);
    out.set(b, a.length);
    return out;
  }
  // 记录最近一次服务端剪贴板内容（文本/图片二选一），seq 供拉取轮询判新。
  function record(text, mime, b64) {
    try {
      window.__selkiesClipSeq = (window.__selkiesClipSeq || 0) + 1;
      window.__selkiesClip = {
        seq: window.__selkiesClipSeq,
        text: text || null,
        imageMime: mime || null,
        imageB64: b64 || null
      };
    } catch (e) {}
  }

  // 是否把服务端秒推的剪贴板自动写回本机。壳内接管后默认 false:
  // 只有「点拉取按钮」时置 true,让 cr 的应答写回;平时服务端推送只更新
  // 缓存(__selkiesClip),不覆盖本机剪贴板。
  function autoApply() {
    try { return window.__selkiesClipAutoApply === true; } catch (e) { return false; }
  }
  // 服务端广播回来的刚由本机推上去的文本 → 视为回声，不写回本机。
  function isSelfEcho(text) {
    try {
      if (window.__selkiesClipSelfPush &&
          window.__selkiesClipSelfPush === text) return true;
    } catch (e) {}
    return false;
  }
  // 图片回声（签名 = 长度:首字节:尾字节）。
  function isSelfEchoImage(b64) {
    try {
      if (!window.__selkiesClipSelfPushImage) return false;
      var bin = atob(b64);
      var sig = bin.length + ':' +
        (bin.length ? bin.charCodeAt(0) : 0) + ':' +
        (bin.length ? bin.charCodeAt(bin.length - 1) : 0);
      return sig === window.__selkiesClipSelfPushImage;
    } catch (e) { return false; }
  }

  var incoming = null;
  function onServerClipboard(d) {
    if (typeof d !== 'string') return;
    try {
      if (d.indexOf('clipboard,') === 0) {
        var text = textFromBytes(bytesFromB64(d.substring(10)));
        if (text) {
          record(text, null, null);
          if (autoApply() && !isSelfEcho(text)) {
            call('$kClipboardTextHandler', text);
          }
        }
      } else if (d.indexOf('clipboard_binary,') === 0) {
        var p = d.split(',');
        if (p.length >= 3) {
          record(null, p[1], p.slice(2).join(','));
          if (autoApply() && !isSelfEchoImage(p.slice(2).join(','))) {
            call('$kClipboardImageHandler', p[1], p.slice(2).join(','));
          }
        }
      } else if (d.indexOf('clipboard_start,') === 0) {
        var q = d.split(',');
        incoming = {
          mime: q[1] || 'text/plain',
          total: parseInt(q[2], 10) || 0,
          bytes: new Uint8Array(0)
        };
        try {
          window.__selkiesClipXfer = {total: incoming.total, received: 0};
        } catch (e) {}
      } else if (d.indexOf('clipboard_data,') === 0) {
        if (incoming) {
          incoming.bytes =
            joinBytes(incoming.bytes, bytesFromB64(d.substring(15)));
          try {
            if (window.__selkiesClipXfer) {
              window.__selkiesClipXfer.received = incoming.bytes.length;
            }
          } catch (e) {}
          if (incoming.bytes.length > 16 * 1024 * 1024) {
            incoming = null;
            try { delete window.__selkiesClipXfer; } catch (e) {}
          }
        }
      } else if (d === 'clipboard_finish' && incoming) {
        var c = incoming;
        incoming = null;
        try { delete window.__selkiesClipXfer; } catch (e) {}
        if (c.mime === 'text/plain') {
          var t = textFromBytes(c.bytes);
          if (t) {
            record(t, null, null);
            if (autoApply()) call('$kClipboardTextHandler', t);
          }
        } else {
          var b64 = b64FromBytes(c.bytes);
          record(null, c.mime, b64);
          if (autoApply() && !isSelfEchoImage(b64)) {
            call('$kClipboardImageHandler', c.mime, b64);
          }
        }
      }
    } catch (e) {}
  }

  var NativeWebSocket = window.WebSocket;
  function SelkiesWebSocket(url, protocols) {
    var ws = protocols === undefined
      ? new NativeWebSocket(url)
      : new NativeWebSocket(url, protocols);
    try {
      if (String(url).indexOf('websockets') !== -1) {
        window.__selkiesSocket = ws;
        ws.addEventListener('message', function(ev) {
          onServerClipboard(ev.data);
        });
        ws.addEventListener('close', function() {
          incoming = null;
          try { delete window.__selkiesClipXfer; } catch (e) {}
        });
      }
    } catch (e) {}
    return ws;
  }
  SelkiesWebSocket.prototype = NativeWebSocket.prototype;
  SelkiesWebSocket.CONNECTING = 0;
  SelkiesWebSocket.OPEN = 1;
  SelkiesWebSocket.CLOSING = 2;
  SelkiesWebSocket.CLOSED = 3;
  window.WebSocket = SelkiesWebSocket;
})();
''';

/// 持续压制 Selkies 页面自带的剪贴板循环（客户端接管）。
///
/// 光注入 localStorage 不够：服务端在设置同步时下发 `settings`（含
/// `clipboard_in_enabled` / `clipboard_out_enabled` / `clipboard_seamless`），
/// 页面 `handleSettingsMessage` 直接用服务端值覆盖并写回 localStorage，
/// 于是「页面自动读本机剪贴板推远端」「服务端推送自动写回本机」又活过来。
///
/// 这里在页面层持续压制：把三个 localStorage 键每秒钉回 `false`，并让
/// `navigator.clipboard.readText/read` 永不 resolve——那是页面自动上行读取的
/// 唯一入口，掐断后它读不到内容也就推不出去。
///
/// 不影响壳内通道：上行走 `postMessage(clipboardUpdateFromUI)` → 页面
/// `sendExplicitClipboard`（不经过 clipboard.read），下行走我们自己的
/// WebSocket 帧捕获 + 按需 `cr` 拉取。
String clipboardTakeoverScript() => '''
(function(){
  if (window.__selkiesClipTakeover) return;
  window.__selkiesClipTakeover = true;

  // 1) 三个开关钉死为 false（服务端 settings 覆盖后会被这里改回来）
  function pin() {
    try {
      var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
      var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
      var keys=['clipboard_in_enabled','clipboard_out_enabled','clipboard_seamless'];
      for (var i=0;i<keys.length;i++) {
        try{localStorage.setItem(ns1+'_'+keys[i],'false');}catch(e){}
        try{localStorage.setItem(ns2+'_'+keys[i],'false');}catch(e){}
      }
    } catch(e) {}
  }
  pin();
  try { setInterval(pin, 1000); } catch(e) {}

  // 2) 掐断页面自动上行读取：readText/read 永不 resolve
  try {
    var never = function(){ return new Promise(function(){}); };
    var cb = navigator.clipboard;
    if (cb) {
      try { Object.defineProperty(cb, 'readText', {value: never, configurable: true, writable: true}); } catch(e) {}
      try { Object.defineProperty(cb, 'read', {value: never, configurable: true, writable: true}); } catch(e) {}
    }
  } catch(e) {}
})();
''';

/// 本机剪贴板图片（PNG 字节）。`pasteboard` 在 macOS/iOS/Windows/
/// Linux/Android/Web 上返回 PNG；Web 也走浏览器 Clipboard API。
class ClipboardImage {
  final String mimeType;
  final Uint8List bytes;

  const ClipboardImage(this.mimeType, this.bytes);
}

/// macOS 原生通道：直接把原始 PNG/JPEG 字节写入 NSPasteboard，
/// 避免 `pasteboard.writeImage` 经 NSImage 转成未压缩 TIFF。
const MethodChannel _imageWriteChannel =
    MethodChannel('wechat_selkies/clipboard_image');

/// 把服务端图片写回本机剪贴板。
///
/// macOS 优先走原生通道，保留原始压缩字节（PNG/JPEG），剪贴板里不再出现
/// 体积更大的 TIFF；其它平台退回 `pasteboard.writeImage`。
/// macOS 上写图失败可能不报错（NSImage 解析失败静默丢弃），写完读回自检，
/// 失败抛 [ClipboardBridgeException]，避免误报成功。
Future<void> writeClipboardImage(Uint8List bytes,
    {String mimeType = 'image/png'}) async {
  if (bytes.isEmpty) return;
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    try {
      await _imageWriteChannel.invokeMethod<void>('writeImage', {
        'data': bytes,
        'mimeType': mimeType,
      });
      debugPrint('[clipboard] native wrote ${bytes.length} bytes $mimeType');
    } on MissingPluginException {
      // 旧构建或纯 Dart 测试环境没有原生通道，退回 pasteboard。
      await Pasteboard.writeImage(bytes);
      debugPrint('[clipboard] pasteboard fallback wrote ${bytes.length} bytes');
    }
    final check = await Pasteboard.image;
    if (check == null || check.isEmpty) {
      throw ClipboardBridgeException(
          '图片写入剪贴板被系统丢弃（${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB $mimeType）');
    }
    return;
  }
  await Pasteboard.writeImage(bytes);
}

/// 单张推送图片上限；base64 后约 1.33 倍整段注入 evaluateJavascript 脚本，
/// 16 MB 图 → 约 21 MB 脚本字符串，再大注入会明显卡顿且有平台失败风险。
/// 超过此上限需走服务端分片上传 verbs（cbs/cbd/cbe），暂未实现。
const int kMaxClipboardImageBytes = 16 * 1024 * 1024;

/// 读取本机剪贴板图片；无图片时返回 null，读取失败时抛异常。
///
/// 读取的是剪贴板里的图片对象（截图、网页/预览复制等）；Finder 里
/// 复制图片文件只带 file URL，沙箱读不到，需要先打开图片再复制内容。
Future<ClipboardImage?> readClipboardImage() async {
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return null;
  return ClipboardImage('image/png', bytes);
}

/// 生成图片写入脚本：直接向数据 socket 发 `cb,image/png,<base64>`。
String buildClipboardImageScript(String mimeType, Uint8List bytes) {
  final mime = jsonEncode(mimeType);
  final data = jsonEncode(base64Encode(bytes));
  // 与 Dart 端 _imageSignature 同算法的签名（长度:首字节:尾字节），
  // 服务端把同一张图广播回来时据此忽略，避免自推送回灌。
  final sig = jsonEncode(
      '${bytes.length}:${bytes.isEmpty ? 0 : bytes.first}:${bytes.isEmpty ? 0 : bytes.last}');
  return '(function(){try{'
      'var ws=window.__selkiesSocket;'
      'if(!ws||ws.readyState!==1)return "err:websocket not open";'
      'window.__selkiesClipSelfPushImage=$sig;'
      'ws.send("cb,"+$mime+","+$data);'
      'return "ok";'
      '}catch(e){return "err:"+e;}})();';
}

/// 单个分片的原始字节数。
///
/// 单次 `evaluateJavascript` 塞整张大图的 base64（4 MB 图 → 5.6 MB 脚本）
/// 会被 WKWebView 拒绝或静默返回 nil，所以大图必须分片发送。
const int kClipboardImageChunkBytes = 256 * 1024;

/// 生成「开始分片传输」脚本。
///
/// ⚠️ wechat-selkies 0.0.17 的服务端是**老版协议，没有 transfer id**：
/// `cbs,<mime>,<total>` / `cbd,<b64>` / `cbe`（上游新版才是带 tid 的形式）。
/// 按老版发，否则服务端会拿 mime 去 `int()` 并报
/// "invalid literal for int() with base 10: 'image/png'"。
String buildClipboardImageBeginScript({
  required String mimeType,
  required int totalBytes,
  required Uint8List bytes,
}) {
  final mime = jsonEncode(mimeType);
  final sig = jsonEncode(
      '${bytes.length}:${bytes.isEmpty ? 0 : bytes.first}:${bytes.isEmpty ? 0 : bytes.last}');
  return '(function(){try{'
      'var ws=window.__selkiesSocket;'
      'if(!ws||ws.readyState!==1)return "err:websocket not open";'
      'window.__selkiesClipSelfPushImage=$sig;'
      'ws.send("cbs,"+$mime+","+$totalBytes);'
      'return "ok";'
      '}catch(e){return "err:"+e;}})();';
}

/// 生成「发送一个分片」脚本：老版 `cbd,<b64>`（无 tid）。
String buildClipboardImageChunkScript({required Uint8List chunk}) {
  final data = jsonEncode(base64Encode(chunk));
  return '(function(){try{'
      'var ws=window.__selkiesSocket;'
      'if(!ws||ws.readyState!==1)return "err:websocket not open";'
      'ws.send("cbd,"+$data);'
      'return "ok";'
      '}catch(e){return "err:"+e;}})();';
}

/// 生成「结束分片传输」脚本：老版 `cbe`（无 tid）。
String buildClipboardImageEndScript() => '(function(){try{'
      'var ws=window.__selkiesSocket;'
      'if(!ws||ws.readyState!==1)return "err:websocket not open";'
      'ws.send("cbe");'
      'return "ok";'
      '}catch(e){return "err:"+e;}})();';

typedef JavascriptEvaluator = Future<dynamic> Function(String source);

/// 把 [text] 注入远端页面。页面返回 `err:` 前缀时抛异常。
///
/// `evaluateJavascript` 在 Apple 平台可能返回 Map/List，在其它平台返回
/// String/null；除显式的 `err:` 外都不视为失败。
Future<void> pushClipboardToRemote({
  required String text,
  required JavascriptEvaluator evaluateJavascript,
}) async {
  if (text.isEmpty) {
    throw const ClipboardBridgeException('剪贴板文本为空');
  }
  final result = await evaluateJavascript(buildClipboardUpdateScript(text));
  if (result is String && result.startsWith('err:')) {
    throw ClipboardBridgeException('远端页面拒绝同步：$result');
  }
}

/// 把图片写入远端剪贴板。
///
/// 小于 [kClipboardImageChunkBytes] 走单帧 `cb,<mime>,<b64>`；更大的图按
/// 服务端老版协议分片（`cbs,<mime>,<total>` → `cbd,<b64>` ×N → `cbe`），
/// 避免超长脚本注入失败。
Future<void> pushClipboardImageToRemote({
  required ClipboardImage image,
  required JavascriptEvaluator evaluateJavascript,
}) async {
  if (image.bytes.isEmpty) {
    throw const ClipboardBridgeException('剪贴板图片为空');
  }
  if (image.bytes.length > kMaxClipboardImageBytes) {
    throw ClipboardBridgeException(
        '图片过大（${(image.bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB），上限 ${(kMaxClipboardImageBytes / (1024 * 1024)).round()} MB');
  }

  if (image.bytes.length < kClipboardImageChunkBytes) {
    final result = await evaluateJavascript(
      buildClipboardImageScript(image.mimeType, image.bytes),
    );
    if (result is String && result.startsWith('err:')) {
      throw ClipboardBridgeException('远端页面拒绝同步：$result');
    }
    return;
  }

  final begin = await evaluateJavascript(buildClipboardImageBeginScript(
    mimeType: image.mimeType,
    totalBytes: image.bytes.length,
    bytes: image.bytes,
  ));
  if (begin is String && begin.startsWith('err:')) {
    throw ClipboardBridgeException('远端页面拒绝分片传输：$begin');
  }
  for (var off = 0; off < image.bytes.length; off += kClipboardImageChunkBytes) {
    final end = off + kClipboardImageChunkBytes;
    final chunk = image.bytes.sublist(
        off, end > image.bytes.length ? image.bytes.length : end);
    final r =
        await evaluateJavascript(buildClipboardImageChunkScript(chunk: chunk));
    if (r is String && r.startsWith('err:')) {
      throw ClipboardBridgeException('分片发送失败（偏移 $off）：$r');
    }
  }
  final finish = await evaluateJavascript(buildClipboardImageEndScript());
  if (finish is String && finish.startsWith('err:')) {
    throw ClipboardBridgeException('结束分片传输失败：$finish');
  }
}

/// 拉取回写本机时接受的图片上限（大于推送上限，防止异常大图撑爆内存）。
const int kMaxPullClipboardImageBytes = 16 * 1024 * 1024;

/// 生成发送 Selkies `cr`（剪贴板读取请求）的脚本。
///
/// 服务端收到后回 `clipboard_reply,cr` + payload 帧（`clipboard,` /
/// `clipboard_binary,` / 分片），由常驻 hook 捕获。返回请求发出前的缓存
/// 序号，供 [pullRemoteClipboard] 轮询判断是否收到了新帧。
String buildClipboardPullRequestScript() =>
    '(function(){try{'
    'var ws=window.__selkiesSocket;'
    'if(!ws||ws.readyState!==1)return "err:websocket not open";'
    // cr 的应答由 hook 写回本机：请求期间开自动写回。
    'window.__selkiesClipAutoApply=true;'
    'ws.send("cr");'
    'return String(window.__selkiesClipSeq||0);'
    '}catch(e){return "err:"+e;}})();';

/// 结束一次拉取：恢复「不自动写回」的接管状态。
String buildClipboardPullDoneScript() =>
    '(function(){try{window.__selkiesClipAutoApply=false;}catch(e){}})()';

/// 读取页面缓存的最近一次服务端剪贴板（JSON 字符串，无则 "null"）。
String readRemoteClipboardCacheScript() =>
    '(function(){try{'
    'return JSON.stringify(window.__selkiesClip||null);'
    '}catch(e){return "null";}})();';

/// 读取分片传输进度（JSON `{received,total}`，无进行中的传输则 "null"）。
String readRemoteClipboardProgressScript() =>
    '(function(){try{'
    'var x=window.__selkiesClipXfer;'
    'return x?JSON.stringify({received:x.received||0,total:x.total||0}):"null";'
    '}catch(e){return "null";}})();';

/// 页面缓存的一次远端剪贴板内容（文本/图片二选一）。
class RemoteClipboardSnapshot {
  final int seq;
  final String? text;
  final String? imageMime;
  final Uint8List? imageBytes;

  /// true = 本次 `cr` 请求新收到的帧；false = 超时回退的旧缓存。
  final bool fresh;

  const RemoteClipboardSnapshot({
    required this.seq,
    this.text,
    this.imageMime,
    this.imageBytes,
    this.fresh = true,
  });

  RemoteClipboardSnapshot copyWith({bool? fresh}) => RemoteClipboardSnapshot(
        seq: seq,
        text: text,
        imageMime: imageMime,
        imageBytes: imageBytes,
        fresh: fresh ?? this.fresh,
      );
}

/// 解析 hook 缓存的 JSON（Apple 端可能已被解码为 Map）。
/// 内容为空（既无文本也无图片）时返回 null。
RemoteClipboardSnapshot? decodeRemoteClipboardSnapshot(dynamic raw) {
  dynamic d = raw;
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty || s == 'null') return null;
    try {
      d = jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  if (d is! Map) return null;
  final seq = (d['seq'] as num?)?.toInt() ?? 0;
  final text = d['text'] is String ? d['text'] as String : null;
  final mime = d['imageMime'] is String ? d['imageMime'] as String : null;
  final b64 = d['imageB64'] is String ? d['imageB64'] as String : null;
  Uint8List? bytes;
  if (b64 != null && b64.isNotEmpty) {
    try {
      final decoded = base64Decode(b64);
      if (decoded.length <= kMaxPullClipboardImageBytes) bytes = decoded;
    } catch (_) {}
  }
  if ((text == null || text.isEmpty) && bytes == null) return null;
  return RemoteClipboardSnapshot(
    seq: seq,
    text: text,
    imageMime: mime,
    imageBytes: bytes,
  );
}

/// 分片传输进度（字节）。
class ClipboardTransferProgress {
  final int received;
  final int total;
  const ClipboardTransferProgress(this.received, this.total);

  static ClipboardTransferProgress? decode(dynamic raw) {
    dynamic d = raw;
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty || s == 'null') return null;
      try {
        d = jsonDecode(s);
      } catch (_) {
        return null;
      }
    }
    if (d is! Map) return null;
    final received = (d['received'] as num?)?.toInt() ?? 0;
    final total = (d['total'] as num?)?.toInt() ?? 0;
    if (total <= 0) return null;
    return ClipboardTransferProgress(received, total);
  }
}

/// 拉取远端剪贴板：发 `cr` 请求后轮询页面缓存等新帧。
///
/// - 大内容经 `clipboard_start/.../clipboard_finish` 分片传输时，进度经
///   [onProgress]（received/total 字节）回报；传输进行中不按 [timeout]
///   判超时，只在字节停止增长超过 [stallTimeout] 时报中断。
/// - 超时仍无新帧且无传输时回退最近一次缓存（legacy 服务端不识别 `cr`
///   时仍能拿到之前被动推送过的内容，标记 `fresh: false`）。
/// - 页面从未收到任何剪贴板帧时返回 null。数据 socket 未就绪或传输中断
///   抛 [ClipboardBridgeException]。
Future<RemoteClipboardSnapshot?> pullRemoteClipboard({
  required JavascriptEvaluator evaluateJavascript,
  Duration timeout = const Duration(milliseconds: 3000),
  Duration stallTimeout = const Duration(seconds: 15),
  void Function(int received, int total)? onProgress,
}) async {
  final reqRaw = await evaluateJavascript(buildClipboardPullRequestScript());
  if (reqRaw is String && reqRaw.startsWith('err:')) {
    throw ClipboardBridgeException('远端数据通道未就绪：$reqRaw');
  }
  final baseSeq = int.tryParse(reqRaw?.toString() ?? '') ?? 0;
  final started = DateTime.now();
  final hardDeadline = started.add(const Duration(seconds: 120));
  var idleDeadline = started.add(timeout);
  var lastReceived = -1;
  try {
    while (true) {
      final snap = decodeRemoteClipboardSnapshot(
        await evaluateJavascript(readRemoteClipboardCacheScript()),
      );
      if (snap != null && snap.seq > baseSeq) return snap;
      final now = DateTime.now();
      final progress = onProgress == null
          ? null
          : ClipboardTransferProgress.decode(
              await evaluateJavascript(readRemoteClipboardProgressScript()),
            );
      if (progress != null) {
        onProgress!(progress.received, progress.total);
        if (progress.received > lastReceived) {
          // 有新字节落地，续期；停止增长超过 stallTimeout 视为传输中断。
          lastReceived = progress.received;
          idleDeadline = now.add(stallTimeout);
        }
        if (now.isAfter(idleDeadline)) {
          throw ClipboardBridgeException(
              '远端剪贴板传输中断（${(progress.received / (1024 * 1024)).toStringAsFixed(1)}'
              '/${(progress.total / (1024 * 1024)).toStringAsFixed(1)} MB），可稍后重试');
        }
      } else if (now.isAfter(idleDeadline)) {
        return snap?.copyWith(fresh: false);
      }
      if (now.isAfter(hardDeadline)) {
        throw const ClipboardBridgeException('拉取超时');
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  } finally {
    // 无论成功/超时/异常，都回到「不自动写回」的接管状态。
    try {
      await evaluateJavascript(buildClipboardPullDoneScript());
    } catch (_) {}
  }
}

class ClipboardBridgeException implements Exception {
  final String message;
  const ClipboardBridgeException(this.message);

  @override
  String toString() => message;
}
