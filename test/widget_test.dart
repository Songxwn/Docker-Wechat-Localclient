import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wechat_selkies_client/models/connection.dart';
import 'package:wechat_selkies_client/providers/connection_store.dart';
import 'package:wechat_selkies_client/screens/home_screen.dart';
import 'package:wechat_selkies_client/services/storage_service.dart';

void main() {
  testWidgets('首次启动创建默认连接并显示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.create();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ConnectionStore(storage),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('本地微信'), findsOneWidget);
    expect(find.text('添加连接'), findsWidgets);
  });

  test('Connection 序列化往返', () {
    final c = Connection.create(
      name: 't',
      url: 'https://x:3001',
      username: 'u',
      password: 'p',
    );
    final back = Connection.fromJson(c.toJson());
    expect(back.name, 't');
    expect(back.url, 'https://x:3001');
    expect(back.hasBasicAuth, true);
  });
}
