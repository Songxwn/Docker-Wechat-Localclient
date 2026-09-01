import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 平台能力检测与外部浏览器打开。
class PlatformService {
  const PlatformService();

  /// 当前平台是否支持应用内 WebView（flutter_inappwebview）。
  ///
  /// flutter_inappwebview 支持 Android / iOS / macOS / Web。
  /// Windows / Linux 桌面端目前不支持，需回退到系统浏览器。
  static bool get supportsInAppWebView {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
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
