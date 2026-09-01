import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection.dart';

/// 负责连接配置的本地持久化（跨平台，基于 shared_preferences）。
class StorageService {
  static const String _kConnections = 'connections';
  static const String _kDefaultId = 'defaultConnectionId';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  List<Connection> loadConnections() {
    final raw = _prefs.getString(_kConnections);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Connection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConnections(List<Connection> connections) async {
    final raw = jsonEncode(connections.map((c) => c.toJson()).toList());
    await _prefs.setString(_kConnections, raw);
  }

  String? loadDefaultId() => _prefs.getString(_kDefaultId);

  Future<void> saveDefaultId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kDefaultId);
    } else {
      await _prefs.setString(_kDefaultId, id);
    }
  }
}
