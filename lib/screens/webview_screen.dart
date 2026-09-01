import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/connection.dart';

/// 应用内 WebView 页面：加载 wechat-selkies 网页版微信。
/// 支持忽略 SSL 证书错误、HTTP Basic 认证注入。
class WebViewScreen extends StatefulWidget {
  final Connection connection;

  const WebViewScreen({super.key, required this.connection});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _loading = true;

  Connection get conn => widget.connection;

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
    return Scaffold(
      appBar: AppBar(
        title: Text(conn.name.isEmpty ? '微信' : conn.name),
        actions: [
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
    );
  }

  Widget _buildWebView() {
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
      onWebViewCreated: (controller) => _controller = controller,
      onProgressChanged: (controller, progress) {
        setState(() => _progress = progress / 100.0);
      },
      onLoadStart: (controller, url) {
        setState(() => _loading = true);
      },
      onLoadStop: (controller, url) {
        setState(() => _loading = false);
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


