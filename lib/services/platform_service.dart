import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// 平台能力检测与外部浏览器打开。
class PlatformService {
  const PlatformService();

  /// 当前平台是否支持应用内 WebView（flutter_inappwebview）。
  ///
  /// flutter_inappwebview 支持 Android / iOS / macOS / Web，
  /// 以及 Windows（通过 flutter_inappwebview_windows，基于 WebView2）。
  /// Linux 桌面端暂无 endorsed 实现，需回退到系统浏览器。
  static bool get supportsInAppWebView {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static bool get isDesktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// 探测 FileBrowser 地址是否可达（HTTP 状态 < 400 即视为在线）。
  ///
  /// 连接页据此决定文件管理按钮的显隐：未配置或探不通一律不显示，
  /// 避免跳到一个死地址。网络异常/超时/解析失败都算不可达。
  static Future<bool> isFileBrowserReachable(String url,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final s = url.trim();
    if (s.isEmpty) return false;
    final uri = Uri.tryParse(normalizeUrl(s));
    if (uri == null) return false;
    try {
      final resp = await http.get(uri).timeout(timeout);
      return resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// 使用系统默认浏览器打开链接。
  Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

/// 将用户输入规范化为完整 URL（缺省补 https://）。
String normalizeUrl(String value) {
  final s = value.trim();
  if (s.isEmpty) return '';
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
  return 'https://$s';
}
