import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_store.dart';
import 'screens/home_screen.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await StorageService.create();
  runApp(WeChatSelkiesApp(storage: storage));
}

class WeChatSelkiesApp extends StatelessWidget {
  final StorageService storage;

  const WeChatSelkiesApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF07C983);
    return ChangeNotifierProvider(
      create: (_) => ConnectionStore(storage),
      child: MaterialApp(
        title: 'WeChat Selkies - 本地远程客户端',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
