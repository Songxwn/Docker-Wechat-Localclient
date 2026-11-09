import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/connection.dart';
import '../services/clipboard_bridge.dart';
import '../services/platform_service.dart';
import '../services/selkies_preset.dart';

/// 应用内 WebView 页面：加载 wechat-selkies 网页版微信。
/// 支持忽略 SSL 证书错误、HTTP Basic 认证注入。
/// 退出时把页内用户修改同步回预设（pop 返回合并后的 StreamPreset，
/// 无修改返回 null）。
class WebViewScreen extends StatefulWidget {
  final Connection connection;

  /// 最近一次同步诊断结论，供首页无同步时展示原因。
  static String lastSyncDiag = '未执行';

  const WebViewScreen({super.key, required this.connection});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  bool _imeInjected = false;
  UserScript? _presetScript;
  late final UserScript _trackerScript;
  late final UserScript _clipboardSocketHook;
  late final UserScript _resolutionClampScript;
  bool _syncing = false;
  bool _pulling = false;
  bool _fileBrowserReachable = false;
  DateTime? _lastAutoImageAt;
  DateTime? _suppressAutoImageUntil;
  String? _lastAutoImageSig;
  static bool _clipboardHintShown = false;

  Connection get conn => widget.connection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeFileBrowser();
    // 追踪脚本常驻：记录页内用户意图修改的键，供退出时回读。
    _trackerScript = UserScript(
      source: SelkiesPresetScript.trackerScript(),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    );
    // 图片剪贴板需要直接向 Selkies 数据 socket 发 cb 协议；
    // 在页面创建 WebSocket 前挂观察器，暴露 __selkiesSocket。
    _clipboardSocketHook = UserScript(
      source: clipboardSocketHookScript(),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    );
    // 分辨率请求钳制常驻：页面跟随窗口的 r,WxH 请求超服务端上限时等比
    // 缩小后再放行（上限来自连接配置，默认 1280x720），防超限断连循环。
    final cap = conn.maxResolutionWH;
    _resolutionClampScript = UserScript(
      source: SelkiesPresetScript.resolutionClampScript(
        maxWidth: cap.$1,
        maxHeight: cap.$2,
      ),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户从其它应用复制图片后切回客户端：自动把图片推到远端。
    if (state == AppLifecycleState.resumed) {
      _autoPushClipboardImage();
    }
  }

  /// 自动同步图片；文本不自动推，避免覆盖远端剪贴板。
  Future<void> _autoPushClipboardImage() async {
    final c = _controller;
    if (c == null || !mounted) return;
    final now = DateTime.now();
    if (_suppressAutoImageUntil != null &&
        now.isBefore(_suppressAutoImageUntil!)) {
      return;
    }
    if (_lastAutoImageAt != null &&
        now.difference(_lastAutoImageAt!).inMilliseconds < 1200) {
      return;
    }
    _lastAutoImageAt = now;

    ClipboardImage? image;
    try {
      image = await readClipboardImage();
    } catch (e) {
      debugPrint('[clipboard] auto image read failed: $e');
      return;
    }
    if (image == null) return;
    final sig = _imageSignature(image);
    if (sig == _lastAutoImageSig) return;
    try {
      await pushClipboardImageToRemote(
        image: image,
        evaluateJavascript: (source) => c.evaluateJavascript(source: source),
      );
      _lastAutoImageSig = sig;
      debugPrint('[clipboard] auto pushed image ${image.bytes.length} bytes');
      _showSnack('已自动同步图片（${_formatBytes(image.bytes.length)}）到远端剪贴板');
    } catch (e) {
      debugPrint('[clipboard] auto image push failed: $e');
    }
  }

  String _imageSignature(ClipboardImage image) {
    final b = image.bytes;
    final head = b.isEmpty ? 0 : b.first;
    final tail = b.isEmpty ? 0 : b.last;
    return '${b.length}:$head:$tail';
  }

  /// 退出前回读页内修改并合并进预设；失败/无修改返回 null。
  Future<StreamPreset?> _syncBackPreset() async {
    final c = _controller;
    if (c == null) {
      WebViewScreen.lastSyncDiag = 'controller 为空';
      return null;
    }
    if (_syncing) {
      WebViewScreen.lastSyncDiag = '同步重入被拦';
      return null;
    }
    _syncing = true;
    try {
      // Selkies dashboard 的滑杆/下拉经 500ms 防抖才 post 给 core 落盘
      // （settings.ts settingsPoster / Sidebar.jsx DEBOUNCE_DELAY）。
      // 用户改完立刻退出会读到旧值，先等防抖完成。
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final raw =
          await c.evaluateJavascript(source: SelkiesPresetScript.readbackScript());
      // 清理内部追踪键（无论回读成功与否）
      try {
        await c.evaluateJavascript(
            source: SelkiesPresetScript.cleanupScript());
      } catch (_) {}
      // Apple 平台（WKWebView）evaluateJavascript 返回原生对象，
      // JSON 字符串会被自动 decode 成 Map；Android/Windows 返回 String。
      final Map? decoded;
      if (raw is Map) {
        decoded = raw;
      } else if (raw is String && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        decoded = d is Map ? d : null;
      } else {
        decoded = null;
      }
      if (decoded == null) {
        WebViewScreen.lastSyncDiag =
            '回读解析失败（raw 类型 ${raw.runtimeType}）';
        return null;
      }
      final keysRaw = decoded['keys'];
      final pipesRaw = decoded['pipes'];
      final touchedRaw = decoded['touched'];
      if (keysRaw is! Map || touchedRaw is! List) {
        WebViewScreen.lastSyncDiag = '回读结构异常';
        return null;
      }
      final keys = <String, String>{};
      for (final e in keysRaw.entries) {
        if (e.key is String && e.value is String) {
          keys[e.key as String] = e.value as String;
        }
      }
      final pipes = <String, bool>{};
      if (pipesRaw is Map) {
        for (final e in pipesRaw.entries) {
          if (e.key is String && e.value is bool) {
            pipes[e.key as String] = e.value as bool;
          }
        }
      }
      final touched =
          touchedRaw.whereType<String>().toSet();
      if (touched.isEmpty) {
        WebViewScreen.lastSyncDiag = '追踪标记为空（tracker 未抓到修改）';
        return null;
      }
      WebViewScreen.lastSyncDiag =
          'touched=${touched.join(',')} keys=${keys.keys.join(',')}';
      return SelkiesPresetScript.mergeReadback(
        conn.preset,
        keys: keys,
        pipes: pipes,
        touched: touched,
      );
    } catch (e) {
      debugPrint('[preset] sync-back failed: $e');
      WebViewScreen.lastSyncDiag = '异常：$e';
      return null;
    } finally {
      _syncing = false;
    }
  }

  /// 拦截返回：先同步预设再 pop。
  /// `_popping` 防止返回按钮与系统手势并发双 pop。
  /// 注意：手动 pop(preset) 会再次触发 onPopInvokedWithResult(didPop=false)，
  /// 靠守卫避免重入；同步结果只随第一次 pop 返回。
  bool _popping = false;
  Future<void> _popWithSync() async {
    if (_popping) return;
    _popping = true;
    try {
      final preset = await _syncBackPreset();
      if (!mounted) return;
      Navigator.of(context).pop(preset);
    } finally {
      _popping = false;
    }
  }

  /// 存储诊断：dump 页面 localStorage 全键、命名空间与帧率值，
  /// 用于排查预设未生效（键名/命名空间不一致）。
  Future<void> _dumpStorage() async {
    final c = _controller;
    if (c == null || !mounted) return;
    const src = '''
(function(){
try{
var o={};
for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);o[k]=localStorage.getItem(k);}
var keys=Object.keys(o).sort();
var ns1=(window.location.origin+window.location.pathname).replace(/[^a-zA-Z0-9._-]/g,'_');
var ns2=window.location.href.split('#')[0].replace(/[^a-zA-Z0-9.-_]/g,'_');
var fr={};
try{fr.ns1=localStorage.getItem(ns1+'_framerate');}catch(e){}
try{fr.ns2=localStorage.getItem(ns2+'_framerate');}catch(e){}
try{fr.tk1=localStorage.getItem(ns1+'___selkies_touched');}catch(e){}
try{fr.tk2=localStorage.getItem(ns2+'___selkies_touched');}catch(e){}
return JSON.stringify({url:window.location.href,ns1:ns1,ns2:ns2,framerate:fr,count:keys.length,vals:o});
}catch(e){return JSON.stringify({error:String(e)});}
})();
''';
    dynamic raw;
    try {
      raw = await c.evaluateJavascript(source: src);
    } catch (e) {
      raw = 'EVAL-ERROR: $e';
    }
    if (!mounted) return;
    final text = raw is Map
        ? const JsonEncoder.withIndent('  ').convert(raw)
        : raw.toString();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('localStorage 诊断'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    debugPrint('[preset] storage dump: $text');
  }

  /// 服务端剪贴板消息经页面 hook 转发到 Flutter，写回本机剪贴板。
  void _registerRemoteClipboardHandlers(InAppWebViewController controller) {
    try {
      controller.addJavaScriptHandler(
        handlerName: kClipboardTextHandler,
        callback: (args) async {
          final text = args.isNotEmpty ? (args.first?.toString() ?? '') : '';
          if (text.isEmpty) return null;
          try {
            await Clipboard.setData(ClipboardData(text: text));
            debugPrint('[clipboard] remote text -> local ${text.length} chars');
          } catch (e) {
            debugPrint('[clipboard] write remote text failed: $e');
          }
          return null;
        },
      );
      controller.addJavaScriptHandler(
        handlerName: kClipboardImageHandler,
        callback: (args) async {
          if (args.length < 2) return null;
          final mime = args[0]?.toString() ?? 'image/png';
          final b64 = args[1]?.toString() ?? '';
          if (b64.isEmpty) return null;
          try {
            final bytes = base64Decode(b64);
            if (bytes.length > kMaxPullClipboardImageBytes) {
              debugPrint('[clipboard] remote image too large: ${bytes.length}');
              return null;
            }
            await writeClipboardImage(bytes, mimeType: mime);
            _suppressAutoImageUntil =
                DateTime.now().add(const Duration(seconds: 8));
            try {
              final local = await readClipboardImage();
              if (local != null) {
                _lastAutoImageSig = _imageSignature(local);
              }
            } catch (_) {}
            debugPrint(
                '[clipboard] remote image -> local ${bytes.length} bytes $mime');
          } catch (e) {
            debugPrint('[clipboard] write remote image failed: $e');
          }
          return null;
        },
      );
    } catch (e) {
      debugPrint('[clipboard] register handlers failed: $e');
    }
  }

  /// 探测 FileBrowser 地址；可达才显示文件管理按钮。
  Future<void> _probeFileBrowser() async {
    final ok = await PlatformService.isFileBrowserReachable(conn.fileBrowserUrl);
    if (!mounted) return;
    setState(() => _fileBrowserReachable = ok);
  }

  /// 在系统默认浏览器打开该连接配置的 FileBrowser（文件管理）。
  Future<void> _openFileBrowserExternal() async {
    final ok = await const PlatformService().openExternal(normalizeUrl(conn.fileBrowserUrl));
    if (!ok) _showSnack('无法打开系统浏览器');
  }

  /// 主动拉取远端剪贴板到本机（发 Selkies `cr` 帧请求）。
  ///
  /// 与被动 hook 的区别：hook 只在服务端剪贴板变化时推送；按钮随叫随到，
  /// 大图分片传输时显示进度条，且超时还能回退最近一次收到的缓存。
  Future<void> _pullRemoteClipboard() async {
    final c = _controller;
    if (c == null) {
      _showSnack('页面尚未加载完成');
      return;
    }
    if (_pulling) return;
    _pulling = true;
    final messenger = ScaffoldMessenger.of(context);
    // 进度条 SnackBar：null = 传输未开始（不定态），有进度显示百分比。
    final progress = ValueNotifier<double?>(null);
    try {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(minutes: 5),
            content: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, value, __) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value == null
                      ? '正在拉取远端剪贴板…'
                      : '正在拉取图片… ${(value * 100).toStringAsFixed(0)}%'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: value, minHeight: 3),
                ],
              ),
            ),
          ),
        );
      final snap = await pullRemoteClipboard(
        evaluateJavascript: (source) => c.evaluateJavascript(source: source),
        onProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );
      if (!mounted) return;
      if (snap == null) {
        _showSnack('远端未返回剪贴板内容（服务端可能未开启剪贴板同步）');
        return;
      }
      if (snap.imageBytes != null) {
        final mime = snap.imageMime ?? 'image/png';
        await writeClipboardImage(snap.imageBytes!, mimeType: mime);
        // 防止切回窗口时把刚拉下来的图片又自动推回远端。
        _suppressAutoImageUntil = DateTime.now().add(const Duration(seconds: 8));
        _lastAutoImageSig = _imageSignature(ClipboardImage(mime, snap.imageBytes!));
        final mimeShort = mime.replaceAll('image/', '');
        _showSnack(snap.fresh
            ? '已拉取图片（$mimeShort，${_formatBytes(snap.imageBytes!.length)}）到本机剪贴板'
            : '已恢复最近收到的图片（$mimeShort，${_formatBytes(snap.imageBytes!.length)}）');
      } else {
        final text = snap.text ?? '';
        await Clipboard.setData(ClipboardData(text: text));
        _showSnack(snap.fresh
            ? '已拉取 ${text.length} 个字符到本机剪贴板'
            : '已恢复最近收到的文本（${text.length} 个字符）');
      }
    } catch (e) {
      _showSnack('拉取失败：$e');
    } finally {
      _pulling = false;
      progress.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      } else {
        messenger.hideCurrentSnackBar();
      }
    }
  }

  /// 读取本机剪贴板并注入 Selkies：图片优先，其次文本。
  /// 绕过浏览器 Clipboard API：WKWebView/未授权浏览器无法在 focus 时读剪贴板。
  Future<void> _pushLocalClipboard() async {
    final c = _controller;
    if (c == null) {
      _showSnack('页面尚未加载完成');
      return;
    }

    ClipboardImage? image;
    try {
      image = await readClipboardImage();
    } catch (e) {
      _showSnack('读取本机图片失败：$e');
    }
    if (image != null) {
      try {
        await pushClipboardImageToRemote(
          image: image,
          evaluateJavascript: (source) =>
              c.evaluateJavascript(source: source),
        );
        _lastAutoImageSig = _imageSignature(image);
        debugPrint('[clipboard] pushed image ${image.bytes.length} bytes');
        _showSnack('已同步图片（${_formatBytes(image.bytes.length)}）到远端剪贴板');
      } catch (e) {
        debugPrint('[clipboard] image push failed: $e');
        _showSnack('同步图片失败：$e');
      }
      return;
    }

    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (e) {
      _showSnack('读取本机剪贴板失败：$e');
      return;
    }
    final text = data?.text ?? '';
    if (text.isEmpty) {
      _showSnack('本机剪贴板没有可同步的图片或文本（Finder 复制文件请先打开图片再复制内容）');
      return;
    }
    try {
      await pushClipboardToRemote(
        text: text,
        evaluateJavascript: (source) => c.evaluateJavascript(source: source),
      );
      debugPrint('[clipboard] pushed ${text.length} chars to remote');
      _showSnack('已同步 ${text.length} 个字符到远端剪贴板');
    } catch (e) {
      debugPrint('[clipboard] push failed: $e');
      _showSnack('同步失败：$e');
    }
  }

  String _formatBytes(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// 注入 IME 整段提交脚本（fork 自修：修复中文输入吃字）。
  Future<void> _injectImeFix() async {
    final c = _controller;
    if (c == null || _imeInjected || !conn.imeFix) return;
    try {
      final js = await rootBundle.loadString('assets/ime-inject.js');
      await c.evaluateJavascript(source: js);
      _imeInjected = true;
      debugPrint('[IME] inject ok (${js.length} chars)');
    } catch (e) {
      debugPrint('[IME] inject failed: $e');
    }
  }

  String get _basicAuthHeader {
    final raw = '${conn.username.trim()}:${conn.password}';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  Map<String, String> get _customHeaders {
    if (!conn.hasBasicAuth) return {};
    return {'Authorization': _basicAuthHeader};
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _popWithSync();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(conn.name.isEmpty ? '微信' : conn.name),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: _popWithSync,
          ),
          actions: [
            IconButton(
              tooltip: '拉取远端剪贴板到本机',
              icon: const Icon(Icons.content_copy),
              onPressed: _pullRemoteClipboard,
            ),
            IconButton(
              tooltip: '同步本机剪贴板（文本/图片）到远端',
              icon: const Icon(Icons.content_paste),
              onPressed: _pushLocalClipboard,
            ),
            if (_fileBrowserReachable)
              IconButton(
                tooltip: '在系统浏览器打开 FileBrowser（文件管理/批量下载删除）',
                icon: const Icon(Icons.folder_open),
                onPressed: _openFileBrowserExternal,
              ),
            IconButton(
              tooltip: '存储诊断',
              icon: const Icon(Icons.bug_report),
              onPressed: _dumpStorage,
            ),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
          ],
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: _buildWebView(),
      ),
    );
  }

  Widget _buildWebView() {
    // 链接前预设：在文档起始预写 Selkies localStorage，使服务端按预设建连。
    final presetSrc = SelkiesPresetScript.build(
      conn.preset,
      manualOff: conn.preset.manualResolution == TriState.off,
    );
    _presetScript = presetSrc == null
        ? null
        : UserScript(
            source: presetSrc,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: true,
          );
    final scripts = <UserScript>[
      _clipboardSocketHook,
      _resolutionClampScript,
      if (_presetScript != null) _presetScript!,
      _trackerScript,
    ];
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(conn.url),
        headers: _customHeaders,
      ),
      initialSettings: InAppWebViewSettings(
        // 允许自签名/无效证书（配合 onReceivedServerTrustAuthRequest）
        allowsBackForwardNavigationGestures: true,
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportZoom: false,
        mediaPlaybackRequiresUserGesture: false,
        // 桌面/移动均启用剪贴板与文件相关能力
        clearCache: false,
        useOnDownloadStart: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
      initialUserScripts: UnmodifiableListView(scripts),
      onWebViewCreated: (controller) {
        _controller = controller;
        _registerRemoteClipboardHandlers(controller);
      },
      onProgressChanged: (controller, progress) {
        setState(() => _progress = progress / 100.0);
      },
      onLoadStart: (controller, url) {
        setState(() => _loading = true);
      },
      onLoadStop: (controller, url) {
        setState(() => _loading = false);
        _imeInjected = false;
        _injectImeFix();
        if (!_clipboardHintShown) {
          _clipboardHintShown = true;
          _showSnack('右上角按钮双向同步剪贴板：粘贴=本机→远端，复制=远端→本机');
        }
      },
      // 忽略 SSL 证书错误（仅当连接配置开启时）
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        if (conn.ignoreSsl) {
          return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED,
          );
        }
        return ServerTrustAuthResponse(
          action: ServerTrustAuthResponseAction.CANCEL,
        );
      },
      // HTTP Basic 认证：优先使用配置的账号密码
      onReceivedHttpAuthRequest: (controller, challenge) async {
        if (conn.hasBasicAuth) {
          return HttpAuthResponse(
            username: conn.username.trim(),
            password: conn.password,
            action: HttpAuthResponseAction.PROCEED,
          );
        }
        return HttpAuthResponse(
          action: HttpAuthResponseAction.CANCEL,
        );
      },
    );
  }
}


