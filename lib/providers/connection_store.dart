import 'package:flutter/foundation.dart';

import '../models/connection.dart';
import '../services/storage_service.dart';

/// 连接配置状态管理：加载、增删改、设默认，并持久化。
class ConnectionStore extends ChangeNotifier {
  final StorageService _storage;

  List<Connection> _connections = [];
  String? _defaultId;

  ConnectionStore(this._storage) {
    _load();
  }

  List<Connection> get connections => List.unmodifiable(_connections);
  String? get defaultId => _defaultId;
  bool get isEmpty => _connections.isEmpty;

  void _load() {
    _connections = _storage.loadConnections();
    if (_connections.isEmpty) {
      // 首次启动创建默认连接
      final first = Connection.defaultConnection();
      _connections = [first];
      _defaultId = first.id;
      _storage.saveConnections(_connections);
      _storage.saveDefaultId(_defaultId);
    } else {
      _defaultId = _storage.loadDefaultId() ?? _connections.first.id;
    }
    notifyListeners();
  }

  bool isDefault(Connection c) => c.id == _defaultId;

  Connection? get defaultConnection {
    if (_connections.isEmpty) return null;
    return _connections.firstWhere(
      (c) => c.id == _defaultId,
      orElse: () => _connections.first,
    );
  }

  Future<void> save(Connection conn) async {
    final idx = _connections.indexWhere((c) => c.id == conn.id);
    if (idx >= 0) {
      _connections[idx] = conn;
    } else {
      _connections.add(conn);
    }
    await _storage.saveConnections(_connections);
    _defaultId ??= _connections.first.id;
    await _storage.saveDefaultId(_defaultId);
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _connections.removeWhere((c) => c.id == id);
    if (_defaultId == id) {
      _defaultId = _connections.isNotEmpty ? _connections.first.id : null;
      await _storage.saveDefaultId(_defaultId);
    }
    await _storage.saveConnections(_connections);
    notifyListeners();
  }

  Future<void> setDefault(String id) async {
    _defaultId = id;
    await _storage.saveDefaultId(id);
    notifyListeners();
  }
}
