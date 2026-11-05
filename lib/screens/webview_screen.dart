import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/connection.dart';
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

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  bool _imeInjected = false;
  UserScript? _presetScript;
  late final UserScript _trackerScript;
  bool _syncing = false;

  Connection get conn => widget.connection;

  @override
  void initState() {
    super.initState();
    // 追踪脚本常驻：记录页内用户意图修改的键，供退出时回读。
    _trackerScript = UserScript(
      source: SelkiesPresetScript.trackerScript(),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: true,
    );
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
    final scripts = _presetScript == null
        ? [_trackerScript]
        : [_presetScript!, _trackerScript];
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
      onWebViewCreated: (controller) => _controller = controller,
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


