import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_selkies_client/services/platform_service.dart';

void main() {
  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      req.response.statusCode = req.uri.path == '/ok' ? 200 : 404;
      await req.response.close();
    });
  });
  tearDownAll(() async => server.close(force: true));

  test('200 视为可达', () async {
    expect(
      await PlatformService.isFileBrowserReachable(
          'http://127.0.0.1:${server.port}/ok'),
      isTrue,
    );
  });

  test('404 视为不可达', () async {
    expect(
      await PlatformService.isFileBrowserReachable(
          'http://127.0.0.1:${server.port}/missing'),
      isFalse,
    );
  });

  test('拒连/超时视为不可达', () async {
    expect(
      await PlatformService.isFileBrowserReachable('http://127.0.0.1:1/x',
          timeout: const Duration(milliseconds: 800)),
      isFalse,
    );
  });

  test('空串/缺 scheme 自动补 https 后按不可达处理', () async {
    expect(await PlatformService.isFileBrowserReachable(''), isFalse);
    expect(
      await PlatformService.isFileBrowserReachable('127.0.0.1:1/x',
          timeout: const Duration(milliseconds: 800)),
      isFalse,
    );
  });
}
