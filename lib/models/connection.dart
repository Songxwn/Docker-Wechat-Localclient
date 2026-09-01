import 'package:uuid/uuid.dart';

const String kDefaultUrl = 'https://localhost:3001';

/// 表示一个 wechat-selkies 连接配置。
class Connection {
  final String id;
  final String name;
  final String url;

  /// 是否忽略 SSL 证书错误（自签名证书场景）。
  final bool ignoreSsl;

  /// 是否使用系统默认浏览器打开（而非应用内 WebView）。
  final bool openExternal;

  /// 可选的 HTTP Basic 认证用户名。
  final String username;

  /// 可选的 HTTP Basic 认证密码。
  final String password;

  const Connection({
    required this.id,
    required this.name,
    required this.url,
    this.ignoreSsl = true,
    this.openExternal = false,
    this.username = '',
    this.password = '',
  });

  /// 创建一个带新 ID 的连接。
  factory Connection.create({
    String name = '未命名',
    String url = kDefaultUrl,
    bool ignoreSsl = true,
    bool openExternal = false,
    String username = '',
    String password = '',
  }) {
    return Connection(
      id: const Uuid().v4(),
      name: name,
      url: url,
      ignoreSsl: ignoreSsl,
      openExternal: openExternal,
      username: username,
      password: password,
    );
  }

  /// 默认连接（首次启动时自动创建）。
  factory Connection.defaultConnection() {
    return Connection.create(
      name: '本地微信',
      url: kDefaultUrl,
      ignoreSsl: true,
    );
  }

  bool get hasBasicAuth => username.trim().isNotEmpty || password.isNotEmpty;

  Connection copyWith({
    String? id,
    String? name,
    String? url,
    bool? ignoreSsl,
    bool? openExternal,
    String? username,
    String? password,
  }) {
    return Connection(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      ignoreSsl: ignoreSsl ?? this.ignoreSsl,
      openExternal: openExternal ?? this.openExternal,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'ignoreSsl': ignoreSsl,
        'openExternal': openExternal,
        'username': username,
        'password': password,
      };

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      name: (json['name'] as String?) ?? '未命名',
      url: (json['url'] as String?) ?? kDefaultUrl,
      ignoreSsl: json['ignoreSsl'] != false,
      openExternal: json['openExternal'] == true,
      username: (json['username'] as String?) ?? '',
      password: json['password'] == null ? '' : json['password'].toString(),
    );
  }
}
