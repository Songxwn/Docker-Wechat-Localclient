import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_selkies_client/models/connection.dart';

void main() {
  test('fileBrowserUrl 默认空且 JSON 往返保真', () {
    final c = Connection.create(name: 'n', url: 'https://x:3001');
    expect(c.fileBrowserUrl, '');

    final round = Connection.fromJson(c.copyWith(fileBrowserUrl: '').toJson());
    expect(round.fileBrowserUrl, '');

    final withUrl = c.copyWith(fileBrowserUrl: 'https://nas:13085');
    final round2 = Connection.fromJson(withUrl.toJson());
    expect(round2.fileBrowserUrl, 'https://nas:13085');
  });

  test('旧版 JSON 无 fileBrowserUrl 字段时兼容', () {
    final c = Connection.fromJson({
      'id': 'x',
      'name': 'n',
      'url': 'https://x:3001',
    });
    expect(c.fileBrowserUrl, '');
  });
}
