import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_selkies_client/services/clipboard_bridge.dart';

void main() {
  test('剪贴板脚本正确转义引号、换行、中文与 emoji', () {
    const text = 'line1\n"quoted" \\ slash 中文 😀 </script>';
    final script = buildClipboardUpdateScript(text);

    expect(script, contains('clipboardUpdateFromUI'));
    expect(script, contains('window.location.origin'));

    // 取出 text 后的 JSON 字面量，确认能原样还原，且换行没有破坏脚本。
    final literal = RegExp(r'text:("(?:[^"\\]|\\.)*")').firstMatch(script);
    expect(literal, isNotNull);
    expect(jsonDecode(literal!.group(1)!), text);
    expect(script, isNot(contains('\n')));
  });

  test('pushClipboardToRemote 注入脚本并接受 null 返回值', () async {
    String? captured;
    await pushClipboardToRemote(
      text: 'hello-测试',
      evaluateJavascript: (source) async {
        captured = source;
        return null;
      },
    );
    expect(captured, isNotNull);
    expect(captured, contains('"hello-测试"'));
  });

  test('页面返回 err: 时抛出', () async {
    expect(
      () => pushClipboardToRemote(
        text: 'x',
        evaluateJavascript: (_) async => 'err:boom',
      ),
      throwsA(isA<ClipboardBridgeException>()),
    );
  });

  test('空文本直接拒绝', () async {
    var called = false;
    expect(
      () => pushClipboardToRemote(
        text: '',
        evaluateJavascript: (_) async {
          called = true;
          return 'ok';
        },
      ),
      throwsA(isA<ClipboardBridgeException>()),
    );
    expect(called, isFalse);
  });

  test('图片脚本走 cb 协议并带 PNG base64', () {
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
    final script = buildClipboardImageScript('image/png', bytes);
    expect(script, contains('__selkiesSocket'));
    expect(script, contains('cb,'));
    expect(script, contains('iVBORw=='));
  });

  test('pushClipboardImageToRemote 注入并接受 null 返回值', () async {
    String? captured;
    await pushClipboardImageToRemote(
      image: ClipboardImage(
        'image/png',
        Uint8List.fromList([1, 2, 3]),
      ),
      evaluateJavascript: (source) async {
        captured = source;
        return null;
      },
    );
    expect(captured, contains('cb,'));
  });

  test('超过 16 MB 的图片直接拒绝', () async {
    expect(
      () => pushClipboardImageToRemote(
        image: ClipboardImage(
          'image/png',
          Uint8List(kMaxClipboardImageBytes + 1),
        ),
        evaluateJavascript: (_) async => 'ok',
      ),
      throwsA(isA<ClipboardBridgeException>()),
    );
  });

  test('socket hook 暴露 WebSocket 且不丢常量', () {
    final script = clipboardSocketHookScript();
    expect(script, contains('__selkiesSocket'));
    expect(script, contains('CLOSED = 3'));
    expect(script, contains('NativeWebSocket.prototype'));
  });

  test('socket hook 同时处理服务端剪贴板消息', () {
    final script = clipboardSocketHookScript();
    expect(script, contains(kClipboardTextHandler));
    expect(script, contains(kClipboardImageHandler));
    expect(script, contains('clipboard_binary'));
    expect(script, contains('clipboard_start'));
    expect(script, contains('clipboard_finish'));
    expect(script, contains('TextDecoder'));
  });

  test('socket hook 把远端剪贴板缓存进 __selkiesClip', () {
    final script = clipboardSocketHookScript();
    expect(script, contains('__selkiesClipSeq'));
    expect(script, contains('__selkiesClip'));
  });

  test('hook 默认不自动写回本机（客户端接管），仅拉取时开', () {
    final script = clipboardSocketHookScript();
    // 三处写回都被 autoApply() 门控
    expect(RegExp(r'autoApply\(\)').allMatches(script).length, greaterThanOrEqualTo(4));
    expect(script, contains('__selkiesClipAutoApply === true'));
    // 默认值不是 true（只在拉取脚本里置 true）
    expect(clipboardSocketHookScript(), isNot(contains('__selkiesClipAutoApply=true')));
    expect(buildClipboardPullRequestScript(), contains('__selkiesClipAutoApply=true'));
    expect(buildClipboardPullDoneScript(), contains('__selkiesClipAutoApply=false'));
  });

  test('自推送回声被抑制（文本/图片）', () {
    final script = clipboardSocketHookScript();
    expect(script, contains('isSelfEcho'));
    expect(script, contains('isSelfEchoImage'));
    expect(script, contains('__selkiesClipSelfPush'));
    // 推送脚本写入签名
    expect(buildClipboardUpdateScript('abc'), contains('__selkiesClipSelfPush'));
    expect(
      buildClipboardImageScript('image/png', Uint8List.fromList([1, 2, 3])),
      contains('__selkiesClipSelfPushImage'),
    );
  });

  test('pull 请求脚本发送 cr 并回读缓存序号', () {
    final script = buildClipboardPullRequestScript();
    expect(script, contains('__selkiesSocket'));
    expect(script, contains('ws.send("cr")'));
    expect(script, contains('__selkiesClipSeq'));
  });

  test('缓存读取脚本 JSON 序列化 __selkiesClip', () {
    expect(readRemoteClipboardCacheScript(), contains('JSON.stringify'));
    expect(readRemoteClipboardCacheScript(), contains('__selkiesClip'));
  });

  test('decode 解析 JSON 缓存（文本）', () {
    final snap = decodeRemoteClipboardSnapshot(
      '{"seq":3,"text":"远端文字","imageMime":null,"imageB64":null}',
    );
    expect(snap, isNotNull);
    expect(snap!.seq, 3);
    expect(snap.text, '远端文字');
    expect(snap.imageBytes, isNull);
    expect(snap.fresh, isTrue);
  });

  test('decode 解析图片缓存并还原字节', () {
    final snap = decodeRemoteClipboardSnapshot(
      jsonEncode({
        'seq': 1,
        'text': null,
        'imageMime': 'image/png',
        'imageB64': base64Encode([1, 2, 3, 4]),
      }),
    );
    expect(snap, isNotNull);
    expect(snap!.imageMime, 'image/png');
    expect(snap.imageBytes, orderedEquals([1, 2, 3, 4]));
  });

  test('decode 接受 Apple 端已解码的 Map', () {
    final snap = decodeRemoteClipboardSnapshot(
      {'seq': 2, 'text': 'x', 'imageMime': null, 'imageB64': null},
    );
    expect(snap!.text, 'x');
  });

  test('decode 空缓存 / 空内容返回 null', () {
    expect(decodeRemoteClipboardSnapshot('null'), isNull);
    expect(decodeRemoteClipboardSnapshot(''), isNull);
    expect(
      decodeRemoteClipboardSnapshot(
        '{"seq":1,"text":null,"imageMime":null,"imageB64":null}',
      ),
      isNull,
    );
  });

  test('pullRemoteClipboard 收到新帧返回文本', () async {
    Future<dynamic> eval(String source) async {
      if (source.contains('ws.send("cr")')) return '5';
      return jsonEncode(
        {'seq': 6, 'text': '远端文字', 'imageMime': null, 'imageB64': null},
      );
    }

    final snap = await pullRemoteClipboard(evaluateJavascript: eval);
    expect(snap, isNotNull);
    expect(snap!.fresh, isTrue);
    expect(snap.text, '远端文字');
  });

  test('pullRemoteClipboard 超时回退旧缓存并标记非新帧', () async {
    Future<dynamic> eval(String source) async {
      if (source.contains('ws.send("cr")')) return '9';
      return jsonEncode(
        {'seq': 3, 'text': '旧内容', 'imageMime': null, 'imageB64': null},
      );
    }

    final snap = await pullRemoteClipboard(
      evaluateJavascript: eval,
      timeout: const Duration(milliseconds: 250),
    );
    expect(snap, isNotNull);
    expect(snap!.fresh, isFalse);
    expect(snap.text, '旧内容');
  });

  test('pullRemoteClipboard 无任何缓存时返回 null', () async {
    Future<dynamic> eval(String source) async {
      if (source.contains('ws.send("cr")')) return '0';
      return 'null';
    }

    final snap = await pullRemoteClipboard(
      evaluateJavascript: eval,
      timeout: const Duration(milliseconds: 250),
    );
    expect(snap, isNull);
  });

  test('pullRemoteClipboard 数据通道未就绪时抛异常', () async {
    Future<dynamic> eval(String source) async => 'err:websocket not open';
    expect(
      () => pullRemoteClipboard(evaluateJavascript: eval),
      throwsA(isA<ClipboardBridgeException>()),
    );
  });

  test('进度读取脚本读取 __selkiesClipXfer', () {
    expect(readRemoteClipboardProgressScript(), contains('__selkiesClipXfer'));
    expect(readRemoteClipboardProgressScript(), contains('JSON.stringify'));
  });

  test('hook 传输进度进 __selkiesClipXfer 且 finish 清理', () {
    final script = clipboardSocketHookScript();
    expect(script, contains('__selkiesClipXfer'));
    expect(script, contains('delete window.__selkiesClipXfer'));
  });

  test('transfer 进度解码与非法值', () {
    expect(ClipboardTransferProgress.decode('null'), isNull);
    expect(ClipboardTransferProgress.decode('{"received":1,"total":0}'), isNull);
    final p = ClipboardTransferProgress.decode('{"received":3,"total":9}');
    expect(p, isNotNull);
    expect(p!.received, 3);
    expect(p.total, 9);
  });

  test('pullRemoteClipboard 传输中回调进度，卡死报中断', () async {
    final calls = <int>[];
    Future<dynamic> eval(String source) async {
      if (source.contains('ws.send("cr")')) return '0';
      if (source.contains('__selkiesClipXfer')) {
        return '{"received":5,"total":10}';
      }
      return jsonEncode(
          {'seq': 0, 'text': null, 'imageMime': null, 'imageB64': null});
    }

    await expectLater(
      () => pullRemoteClipboard(
        evaluateJavascript: eval,
        timeout: const Duration(milliseconds: 250),
        stallTimeout: const Duration(milliseconds: 250),
        onProgress: (received, total) => calls.add(received),
      ),
      throwsA(isA<ClipboardBridgeException>()),
    );
    expect(calls, contains(5));
  });

  test('pullRemoteClipboard 传输完成后返回新帧', () async {
    var progressPolls = 0;
    Future<dynamic> eval(String source) async {
      if (source.contains('ws.send("cr")')) return '0';
      if (source.contains('__selkiesClipXfer')) {
        progressPolls++;
        return progressPolls >= 2 ? 'null' : '{"received":5,"total":10}';
      }
      return jsonEncode(
          {'seq': 1, 'text': 'done', 'imageMime': null, 'imageB64': null});
    }

    final snap = await pullRemoteClipboard(
      evaluateJavascript: eval,
      timeout: const Duration(seconds: 3),
    );
    expect(snap, isNotNull);
    expect(snap!.fresh, isTrue);
    expect(snap.text, 'done');
  });

  test('接管脚本: 钉三键 + 掐断页面自动读', () {
    final script = clipboardTakeoverScript();
    expect(script, contains('__selkiesClipTakeover'));
    expect(script, contains('clipboard_in_enabled'));
    expect(script, contains('clipboard_out_enabled'));
    expect(script, contains('clipboard_seamless'));
    expect(script, contains("'false'"));
    expect(script, contains('setInterval(pin, 1000)'));
    expect(script, contains('readText'));
    expect(script, contains('defineProperty'));
  });

  test('大图走老版分片协议 cbs/cbd/cbe(无 tid)', () {
    final bytes = Uint8List(kClipboardImageChunkBytes * 2 + 10);
    final begin = buildClipboardImageBeginScript(
        mimeType: 'image/png', totalBytes: bytes.length, bytes: bytes);
    expect(begin, contains('ws.send("cbs,"'));
    expect(begin, contains('"image/png"'));
    expect(begin, isNot(contains('a17'))); // 无 tid

    final chunk = buildClipboardImageChunkScript(
        chunk: Uint8List.fromList([1, 2, 3]));
    expect(chunk, contains('ws.send("cbd,"'));

    expect(buildClipboardImageEndScript(), contains('ws.send("cbe")'));
  });

  test('512 KB 以下仍走单帧 cb', () {
    final small = Uint8List(1024);
    expect(buildClipboardImageScript('image/png', small), contains('ws.send("cb,"'));
    expect(kClipboardImageChunkBytes, 256 * 1024);
  });

  test('切回唤醒脚本: 强制 visible + 派发 visibilitychange', () {
    final js = buildStreamAwakeScript();
    expect(js, contains("document.hidden"));
    expect(js, contains("visibilitychange"));
    expect(js, contains("'visible'"));
  });
}
