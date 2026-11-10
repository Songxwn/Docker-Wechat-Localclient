import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_selkies_client/models/connection.dart';
import 'package:wechat_selkies_client/services/selkies_preset.dart';

void main() {
  test('客户端接管剪贴板：强制关闭页面自带同步三开关', () {
    final src = SelkiesPresetScript.build(
      const StreamPreset(clipboardUp: TriState.on),
      manualOff: false,
      clientOwnsClipboard: true,
    );
    expect(src, isNotNull);
    // 上行开关必须保持 true（否则壳内推送会被上游 sendClipboardData 丢弃）
    expect(src!, contains("W('clipboard_in_enabled','true')"));
    // 下行两项必须关掉：服务端推送不再自动写回本机
    expect(src, contains("W('clipboard_out_enabled','false')"));
    expect(src, contains("W('clipboard_seamless','false')"));
  });

  test('未接管时保留用户预设值', () {
    final src = SelkiesPresetScript.build(
      const StreamPreset(clipboardUp: TriState.on),
      manualOff: false,
    );
    expect(src, contains("W('clipboard_in_enabled','true')"));
    expect(src, isNot(contains("W('clipboard_out_enabled','false')")));
  });

  test('接管模式即使预设为空也会生成脚本（否则同步关不掉）', () {
    final src = SelkiesPresetScript.build(
      const StreamPreset(),
      manualOff: false,
      clientOwnsClipboard: true,
    );
    expect(src, isNotNull);
    expect(src!, contains("W('clipboard_out_enabled','false')"));
  });
}
