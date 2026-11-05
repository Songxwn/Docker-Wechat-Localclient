import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wechat_selkies_client/models/connection.dart';
import 'package:wechat_selkies_client/screens/stream_preset_editor.dart';

void main() {
  /// 把目标滚到可见。不能用 scrollUntilVisible：编辑器内 DropdownButton
  /// 自带 Scrollable，scrollable 定位有歧义；ensureVisible 无此问题。
  Future<void> showUp(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }


  testWidgets('预设编辑器渲染全部的分区分组', (tester) async {
    StreamPreset current = const StreamPreset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamPresetEditor(
              initial: current,
              onChanged: (p) => current = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final section in ['视频', '音频', '显示', '输入与手柄', '剪贴板', '其他']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.text('串流预设（链接前设置）'), findsNothing);
    // 关键控件存在
    expect(find.text('传输通道'), findsOneWidget);
    expect(find.text('手动分辨率'), findsOneWidget);
    expect(find.text('全部恢复跟随'), findsOneWidget);
  });

  testWidgets('三态开关与手动分辨率交互', (tester) async {
    StreamPreset current = const StreamPreset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamPresetEditor(
              initial: current,
              onChanged: (p) => current = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开手动分辨率 → 出现宽高输入
    expect(find.text('宽'), findsNothing);
    await showUp(tester, find.text('手动分辨率'));
    // 手动分辨率行内的 SegmentedButton 切到“开”
    final manualRow = find.ancestor(
      of: find.text('手动分辨率'),
      matching: find.byType(Column),
    ).first;
    final segInRow = find.descendant(
      of: manualRow,
      matching: find.byType(SegmentedButton<TriState>),
    );
    expect(segInRow, findsOneWidget);
    // 点“开”segment
    final onSeg = find.descendant(
      of: segInRow,
      matching: find.text('开'),
    );
    await tester.tap(onSeg);
    await tester.pumpAndSettle();
    expect(current.manualResolution, TriState.on);
    expect(find.text('宽'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);

    // 填宽高
    await tester.enterText(
        find.widgetWithText(TextFormField, '宽'), '1280');
    await tester.enterText(
        find.widgetWithText(TextFormField, '高'), '720');
    await tester.pumpAndSettle();
    expect(current.manualWidth, 1280);
    expect(current.manualHeight, 720);
  });

  testWidgets('帧率跟随显示器 chip 切换', (tester) async {
    StreamPreset current = const StreamPreset();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamPresetEditor(
              initial: current,
              onChanged: (p) => current = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await showUp(tester, find.text('跟随显示器'));
    await tester.tap(find.text('跟随显示器'));
    await tester.pumpAndSettle();
    expect(current.framerate, -1);
  });
}
