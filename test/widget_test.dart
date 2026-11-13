import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wechat_selkies_client/models/connection.dart';
import 'package:wechat_selkies_client/providers/connection_store.dart';
import 'package:wechat_selkies_client/screens/home_screen.dart';
import 'package:wechat_selkies_client/services/selkies_preset.dart';
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

  test('maxResolution 存取往返 + 缺键兼容', () {
    final c = Connection.create(name: 't', url: 'https://x:3001')
        .copyWith(maxResolution: '1920x1080');
    final back = Connection.fromJson(c.toJson());
    expect(back.maxResolution, '1920x1080');
    expect(back.maxResolutionWH, (1920, 1080));
    // 老配置无 maxResolution 键 → 空串
    final legacy = Connection.fromJson({
      'id': 'x',
      'name': 't',
      'url': 'https://x:3001',
    });
    expect(legacy.maxResolution, '');
    expect(legacy.maxResolutionWH, (1280, 720));
  });

  test('maxResolutionWH 解析兜底', () {
    final base = Connection.create(name: 't', url: 'https://x:3001');
    expect(base.copyWith(maxResolution: '2560x1440').maxResolutionWH,
        (2560, 1440));
    expect(base.copyWith(maxResolution: '').maxResolutionWH, (1280, 720));
    expect(base.copyWith(maxResolution: 'abc').maxResolutionWH, (1280, 720));
    expect(base.copyWith(maxResolution: '0x0').maxResolutionWH, (1280, 720));
    expect(base.copyWith(maxResolution: '1280x').maxResolutionWH, (1280, 720));
    expect(
        base.copyWith(maxResolution: ' 1280x720 ').maxResolutionWH,
        (1280, 720));
  });

  test('分辨率钳制脚本：patch 双通道 + 钳制上限 + 幂等标记', () {
    final src = SelkiesPresetScript.resolutionClampScript(
      maxWidth: 1280,
      maxHeight: 720,
    );
    expect(src, contains('var MW=1280,MH=720;'));
    expect(src, contains('__rclamp'));
    expect(src, contains('window.WebSocket&&window.WebSocket.prototype'));
    expect(
        src, contains('window.RTCDataChannel&&window.RTCDataChannel.prototype'));
    // charCode 114,44 = 'r,'（避免源码里出现裸 r, 字面量被误改）
    expect(src, contains('charCodeAt(0)===114&&d.charCodeAt(1)===44'));
  });

  test('重置页面状态脚本：双命名空间前缀过滤 + 只删命中键', () {
    final src = SelkiesPresetScript.resetStorageScript();
    // 两套命名空间派生规则都要有
    expect(src, contains("location.origin+window.location.pathname"));
    expect(src, contains("href.split('#')[0]"));
    // 前缀匹配后 removeItem，不动其它来源
    expect(src, contains("ns1+'_'"));
    expect(src, contains("ns2+'_'"));
    expect(src, contains('indexOf(p1)===0||k.indexOf(p2)===0'));
    expect(src, contains('localStorage.removeItem(kill[j])'));
    // 返回删除计数供 Dart 报告
    expect(src, contains('removed:kill.length'));
  });

  test('StreamPreset 默认全跟随、无显式值', () {
    const p = StreamPreset();
    expect(p.hasExplicit, false);
    expect(p.toJson(), isEmpty);
    expect(SelkiesPresetScript.toEntries(p), isEmpty);
    expect(
        SelkiesPresetScript.build(p, manualOff: false), isNull);
  });

  test('StreamPreset 序列化往返', () {
    const p = StreamPreset(
      transport: StreamTransport.webrtc,
      encoder: SelkiesEncoder.h264enc,
      fullColor: TriState.off,
      framerate: 60,
      videoBitrate: 8000,
      manualResolution: TriState.on,
      manualWidth: 1281,
      manualHeight: 720,
      hidpi: TriState.on,
      video: TriState.off,
      microphone: TriState.on,
    );
    final back = StreamPreset.fromJson(p.toJson());
    expect(back.transport, StreamTransport.webrtc);
    expect(back.encoder, SelkiesEncoder.h264enc);
    expect(back.fullColor, TriState.off);
    expect(back.framerate, 60);
    expect(back.videoBitrate, 8000);
    expect(back.manualResolution, TriState.on);
    expect(back.manualWidth, 1281);
    expect(back.manualHeight, 720);
    expect(back.hidpi, TriState.on);
    expect(back.video, TriState.off);
    expect(back.microphone, TriState.on);
    // 未设置的字段保持跟随
    expect(back.tenBit, TriState.serverDefault);
    expect(back.audioBitrate, isNull);
  });

  test('预设转 Selkies 键：分辨率取偶 + HiDPI 取反 + 流开关聚合', () {
    const p = StreamPreset(
      framerate: -1,
      manualResolution: TriState.on,
      manualWidth: 1281,
      manualHeight: 721,
      hidpi: TriState.on,
      turbo: TriState.off,
      video: TriState.off,
      audio: TriState.on,
    );
    final entries = SelkiesPresetScript.toEntries(p);
    expect(entries['framerate'], 'display');
    expect(entries['manual_resolution'], 'true');
    expect(entries['manual_width'], '1280');
    expect(entries['manual_height'], '720');
    // HiDPI 开 = useCssScaling 关
    expect(entries['useCssScaling'], 'false');
    expect(entries['video_streaming_mode'], 'false');
    expect(entries['__selkies_preset_pipeline'], 'video:0,audio:1');
  });

  test('注入脚本含命名空间派生与 explicit 标记', () {
    const p = StreamPreset(encoder: SelkiesEncoder.h265enc);
    final src =
        SelkiesPresetScript.build(p, manualOff: false)!;
    // 与上游 getStorageAppName 同规则：origin+path，非法字符下划线
    expect(src, contains("location.origin+window.location.pathname"));
    expect(src, contains("W('encoder','h265enc')"));
    expect(src, contains('_explicit_choice'));
    expect(src, contains('_pick'));
  });

  test('manualResolution=off 时脚本删除手动键', () {
    const p = StreamPreset(manualResolution: TriState.off);
    final src = SelkiesPresetScript.build(p, manualOff: true)!;
    expect(src, contains("removeItem(K1('manual_width'))"));
    expect(src, contains("removeItem(K2('manual_width'))"));
    expect(src, contains("removeItem(K1('manual_height'))"));
    expect(src, contains("removeItem(K1('is_manual_resolution_mode'))"));
  });
  test('追踪/回读/清理脚本含关键词汇', () {
    final tracker = SelkiesPresetScript.trackerScript();
    expect(tracker, contains('___selkies_touched'));
    expect(tracker, contains('setManualResolution'));
    expect(tracker, contains('resetResolutionToWindow'));
    expect(tracker, contains('pipelineControl'));
    expect(tracker, contains('sidebarButtonStatusUpdate'));
    final readback = SelkiesPresetScript.readbackScript();
    expect(readback, contains('___selkies_touched'));
    expect(readback, contains('___selkies_pipesnap'));
    final cleanup = SelkiesPresetScript.cleanupScript();
    expect(cleanup, contains('removeItem'));
  });

  test('mergeReadback 只合并触碰过的键', () {
    const base = StreamPreset(
      encoder: SelkiesEncoder.h264enc,
      framerate: 30,
    );
    final merged = SelkiesPresetScript.mergeReadback(
      base,
      keys: {'encoder': 'h265enc', 'video_crf': '18'},
      pipes: {},
      // 只触碰了 encoder：video_crf 虽有值也不合并
      touched: {'encoder'},
    );
    expect(merged.encoder, SelkiesEncoder.h265enc);
    expect(merged.videoCrf, isNull);
    expect(merged.framerate, 30);
  });

  test('mergeReadback 分辨率/流开关/HiDPI 往返', () {
    const base = StreamPreset();
    final merged = SelkiesPresetScript.mergeReadback(
      base,
      keys: {
        'manual_resolution': 'true',
        'manual_width': '1280',
        'manual_height': '720',
        'useCssScaling': 'true',
        'framerate': 'display',
      },
      pipes: {'video': false, 'microphone': true},
      touched: {
        'manual_resolution',
        'manual_width',
        'manual_height',
        'useCssScaling',
        'framerate',
        'video',
        'microphone',
      },
    );
    expect(merged.manualResolution, TriState.on);
    expect(merged.manualWidth, 1280);
    expect(merged.manualHeight, 720);
    // useCssScaling=true → HiDPI 关
    expect(merged.hidpi, TriState.off);
    expect(merged.framerate, -1);
    expect(merged.video, TriState.off);
    expect(merged.microphone, TriState.on);
    // 未触碰的保持跟随
    expect(merged.audio, TriState.serverDefault);
  });

  test('mergeReadback 页内恢复跟随窗口记为 off', () {
    const base = StreamPreset(
      manualResolution: TriState.on,
      manualWidth: 1920,
      manualHeight: 1080,
    );
    // resetResolutionToWindow 删掉了三键：触碰过但回读无值
    final merged = SelkiesPresetScript.mergeReadback(
      base,
      keys: {},
      pipes: {},
      touched: {'manual_resolution', 'manual_width', 'manual_height'},
    );
    expect(merged.manualResolution, TriState.off);
    expect(merged.manualWidth, isNull);
    expect(merged.manualHeight, isNull);
  });

  test('mergeReadback 认旧版键名', () {
    const base = StreamPreset();
    final merged = SelkiesPresetScript.mergeReadback(
      base,
      keys: {
        'encoder_rtc': 'x264enc',
        'h264_crf': '22',
        'h264_fullcolor': 'true',
        'h264_streaming_mode': 'false',
        'h264_paintover_crf': '16',
        'is_manual_resolution_mode': 'true',
        'manual_width': '1366',
        'manual_height': '768',
      },
      pipes: {},
      touched: {
        'encoder_rtc',
        'h264_crf',
        'h264_fullcolor',
        'h264_streaming_mode',
        'h264_paintover_crf',
        'is_manual_resolution_mode',
        'manual_width',
        'manual_height',
      },
    );
    expect(merged.encoder, SelkiesEncoder.h264enc);
    expect(merged.videoCrf, 22);
    expect(merged.fullColor, TriState.on);
    expect(merged.turbo, TriState.off);
    expect(merged.paintoverCrf, 16);
    expect(merged.manualResolution, TriState.on);
    expect(merged.manualWidth, 1366);
    expect(merged.manualHeight, 768);
  });

  test('mergeReadback 认旧版驼峰分辨率键', () {
    const base = StreamPreset();
    final merged = SelkiesPresetScript.mergeReadback(
      base,
      keys: {
        'isManualResolutionMode': 'true',
        'manualWidth': '1920',
        'manualHeight': '1080',
      },
      pipes: {},
      touched: {'isManualResolutionMode', 'manualWidth', 'manualHeight'},
    );
    expect(merged.manualResolution, TriState.on);
    expect(merged.manualWidth, 1920);
    expect(merged.manualHeight, 1080);
  });

  test('toEntries 同时写新旧键', () {
    const p = StreamPreset(
      encoder: SelkiesEncoder.h264enc,
      videoCrf: 25,
      fullColor: TriState.on,
      turbo: TriState.off,
      paintoverCrf: 18,
      manualResolution: TriState.on,
      manualWidth: 1280,
      manualHeight: 720,
    );
    final entries = SelkiesPresetScript.toEntries(p);
    expect(entries['encoder'], 'h264enc');
    expect(entries['encoder_rtc'], 'x264enc');
    expect(entries['video_crf'], '25');
    expect(entries['h264_crf'], '25');
    expect(entries['video_fullcolor'], 'true');
    expect(entries['h264_fullcolor'], 'true');
    expect(entries['video_streaming_mode'], 'false');
    expect(entries['h264_streaming_mode'], 'false');
    expect(entries['video_paintover_crf'], '18');
    expect(entries['h264_paintover_crf'], '18');
    expect(entries['manual_resolution'], 'true');
    expect(entries['is_manual_resolution_mode'], 'true');
  });
}
