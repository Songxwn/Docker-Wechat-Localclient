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
    // 即使用户预设开了上行，接管模式下也必须写 false
    expect(src!, contains("W('clipboard_in_enabled','false')"));
    expect(src, contains("W('clipboard_out_enabled','false')"));
    expect(src, contains("W('clipboard_seamless','false')"));
    expect(src, isNot(contains("W('clipboard_in_enabled','true')")));
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
    expect(src!, contains("W('clipboard_in_enabled','false')"));
  });
}
