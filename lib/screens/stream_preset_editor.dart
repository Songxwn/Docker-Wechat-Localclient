import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection.dart';

/// 链接前串流预设编辑器：视频 / 音频 / 显示 / 输入 / 剪贴板分组。
///
/// 约定：每项默认“跟随服务端/默认”，用户显式选择后才生效；
/// 数值项留空 = 跟随。
class StreamPresetEditor extends StatefulWidget {
  final StreamPreset initial;
  final ValueChanged<StreamPreset> onChanged;

  const StreamPresetEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<StreamPresetEditor> createState() => _StreamPresetEditorState();
}

class _StreamPresetEditorState extends State<StreamPresetEditor> {
  late StreamPreset _p;
  late final TextEditingController _framerate;
  late final TextEditingController _videoBitrate;
  late final TextEditingController _videoCrf;
  late final TextEditingController _jpegQuality;
  late final TextEditingController _paintoverCrf;
  late final TextEditingController _paintoverBurst;
  late final TextEditingController _paintoverJpeg;
  late final TextEditingController _audioBitrate;
  late final TextEditingController _manualWidth;
  late final TextEditingController _manualHeight;

  static const _framerateStops = [
    8, 10, 12, 15, 18, 20, 24, 25, 30, 36, 40, 45, 48, 50, //
    60, 72, 75, 80, 90, 100, 120, 144, 165, 180, 200, 240,
  ];
  // Selkies audio_bitrate 允许枚举（bps，服务端 settings.py）。
  static const _audioBitrateStops = [
    32000, 48000, 64000, 96000, 128000, 192000, 256000, 320000, 384000, 510000,
  ];
  static const _resPresets = [
    '1920x1080', '1280x720', '1366x768', '1920x1200', '2560x1440', //
    '3840x2160', '1024x768', '800x600', '640x480', '320x240',
  ];

  @override
  void initState() {
    super.initState();
    _p = widget.initial;
    _framerate = TextEditingController();
    _videoBitrate = TextEditingController();
    _videoCrf = TextEditingController();
    _jpegQuality = TextEditingController();
    _paintoverCrf = TextEditingController();
    _paintoverBurst = TextEditingController();
    _paintoverJpeg = TextEditingController();
    _audioBitrate = TextEditingController();
    _manualWidth = TextEditingController();
    _manualHeight = TextEditingController();
    _syncControllers(_p);
  }

  /// 外部预设变化时（如 WebView 同步回）刷新内部态与输入框。
  @override
  void didUpdateWidget(StreamPresetEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial) {
      setState(() => _p = widget.initial);
      _syncControllers(_p);
    }
  }

  /// 把预设值写入各输入框（不触发 onChanged，避免回写循环）。
  void _syncControllers(StreamPreset p) {
    String intText(int? v) => v == null ? '' : v.toString();
    void set(TextEditingController c, String v) {
      if (c.text != v) {
        c.value = TextEditingValue(
          text: v,
          selection: TextSelection.collapsed(offset: v.length),
        );
      }
    }

    set(_framerate,
        p.framerate == null || p.framerate! < 0 ? '' : p.framerate.toString());
    set(_videoBitrate, intText(p.videoBitrate));
    set(_videoCrf, intText(p.videoCrf));
    set(_jpegQuality, intText(p.jpegQuality));
    set(_paintoverCrf, intText(p.paintoverCrf));
    set(_paintoverBurst, intText(p.paintoverBurst));
    set(_paintoverJpeg, intText(p.paintoverJpeg));
    set(_audioBitrate,
        p.audioBitrate == null ? '' : (p.audioBitrate! ~/ 1000).toString());
    set(_manualWidth, intText(p.manualWidth));
    set(_manualHeight, intText(p.manualHeight));
  }

  @override
  void dispose() {
    _framerate.dispose();
    _videoBitrate.dispose();
    _videoCrf.dispose();
    _jpegQuality.dispose();
    _paintoverCrf.dispose();
    _paintoverBurst.dispose();
    _paintoverJpeg.dispose();
    _audioBitrate.dispose();
    _manualWidth.dispose();
    _manualHeight.dispose();
    super.dispose();
  }

  void _update(StreamPreset next) {
    setState(() => _p = next);
    widget.onChanged(next);
  }

  int? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        ...children,
      ],
    );
  }

  /// 三态 SegmentedButton：跟随 / 开 / 关。
  Widget _tri(String label, TriState value, ValueChanged<TriState> onChanged,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          SegmentedButton<TriState>(
            segments: const [
              ButtonSegment(
                  value: TriState.serverDefault, label: Text('跟随')),
              ButtonSegment(value: TriState.on, label: Text('开')),
              ButtonSegment(value: TriState.off, label: Text('关')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
            ),
        ],
      ),
    );
  }

  Widget _enum<T extends Enum>(
      String label, T value, List<T> values, String Function(T) textOf,
      ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: value,
            items: [for (final v in values) DropdownMenuItem(value: v, child: Text(textOf(v)))],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _int(
    String label,
    TextEditingController controller,
    ValueChanged<int?> onChanged, {
    String? hint,
    List<int>? stops,
    int? Function(int?)? map,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                helperText: hint,
                hintText: '跟随服务端',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onChanged(map?.call(_parse(controller)) ?? _parse(controller)),
            ),
          ),
          if (stops != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: PopupMenuButton<int>(
                tooltip: '常用值',
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: (v) {
                  controller.text = v.toString();
                  onChanged(map?.call(v) ?? v);
                },
                itemBuilder: (_) => [
                  for (final s in stops)
                    PopupMenuItem(value: s, child: Text(s.toString())),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _transportText(StreamTransport v) => switch (v) {
        StreamTransport.serverDefault => '跟随服务端',
        StreamTransport.websockets => 'WebSocket',
        StreamTransport.webrtc => 'WebRTC',
      };

  String _encoderText(SelkiesEncoder v) => switch (v) {
        SelkiesEncoder.serverDefault => '跟随服务端',
        SelkiesEncoder.h264enc => 'H.264',
        SelkiesEncoder.h265enc => 'H.265',
        SelkiesEncoder.vp8enc => 'VP8',
        SelkiesEncoder.vp9enc => 'VP9',
        SelkiesEncoder.av1enc => 'AV1',
        SelkiesEncoder.h264encStriped => 'H.264 条带',
        SelkiesEncoder.jpeg => 'JPEG 条带',
      };

  String _rateText(RateControl v) => switch (v) {
        RateControl.serverDefault => '跟随服务端',
        RateControl.cbr => 'CBR 恒定码率',
        RateControl.crf => 'CRF 恒定质量',
      };

  String _webcamText(WebcamEncoder v) => switch (v) {
        WebcamEncoder.serverDefault => '跟随服务端',
        WebcamEncoder.auto => '自动',
        WebcamEncoder.h264 => 'H.264',
        WebcamEncoder.h265 => 'H.265',
        WebcamEncoder.vp8 => 'VP8',
        WebcamEncoder.vp9 => 'VP9',
        WebcamEncoder.av1 => 'AV1',
        WebcamEncoder.mjpeg => 'MJPEG',
      };

  String _scalingText(UiScaling v) => switch (v) {
        UiScaling.serverDefault => '跟随服务端',
        UiScaling.p100 => '100%',
        UiScaling.p125 => '125%',
        UiScaling.p150 => '150%',
        UiScaling.p175 => '175%',
        UiScaling.p200 => '200%',
        UiScaling.p225 => '225%',
        UiScaling.p250 => '250%',
        UiScaling.p275 => '275%',
        UiScaling.p300 => '300%',
      };

  @override
  Widget build(BuildContext context) {
    final followDisplay = _p.framerate != null && _p.framerate! < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('视频', [
          _enum('传输通道', _p.transport, StreamTransport.values, _transportText,
              (v) => _update(_p.copyWith(transport: v))),
          _enum('编码器', _p.encoder, SelkiesEncoder.values, _encoderText,
              (v) => _update(_p.copyWith(encoder: v))),
          _enum('摄像头上行编码', _p.webcamEncoder, WebcamEncoder.values,
              _webcamText, (v) => _update(_p.copyWith(webcamEncoder: v))),
          _tri('4:4:4 全彩', _p.fullColor,
              (v) => _update(_p.copyWith(fullColor: v))),
          _tri('10bit', _p.tenBit, (v) => _update(_p.copyWith(tenBit: v))),
          Row(
            children: [
              Expanded(
                child: _int('帧率 fps（8-240）', _framerate,
                    (v) => _update(_p.copyWith(framerate: () => v)),
                    hint: '常用 30 / 60；留空跟随',
                    stops: _framerateStops),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilterChip(
                  label: const Text('跟随显示器'),
                  selected: followDisplay,
                  onSelected: (sel) {
                    if (sel) {
                      _framerate.clear();
                      _update(_p.copyWith(framerate: () => -1));
                    } else {
                      _update(_p.copyWith(framerate: () => null));
                    }
                  },
                ),
              ),
            ],
          ),
          _enum('码率控制', _p.rateControl, RateControl.values, _rateText,
              (v) => _update(_p.copyWith(rateControl: v))),
          _int('CBR 码率 kbps', _videoBitrate,
              (v) => _update(_p.copyWith(videoBitrate: () => v)),
              hint: '如 8000 = 8Mbps；留空跟随'),
          _int('CRF 质量（5-50，越小越好）', _videoCrf,
              (v) => _update(_p.copyWith(videoCrf: () => v)),
              hint: '默认 25；留空跟随'),
          _tri('Turbo 流式编码', _p.turbo,
              (v) => _update(_p.copyWith(turbo: v)),
              hint: '每帧都编码，动态画面更流畅'),
          _int('JPEG 质量（1-100）', _jpegQuality,
              (v) => _update(_p.copyWith(jpegQuality: () => v)),
              hint: '仅 JPEG 编码时生效'),
          _tri('静止画面精修', _p.paintOver,
              (v) => _update(_p.copyWith(paintOver: v))),
          _int('精修 CRF（5-50）', _paintoverCrf,
              (v) => _update(_p.copyWith(paintoverCrf: () => v))),
          _int('精修持续帧数（1-30）', _paintoverBurst,
              (v) => _update(_p.copyWith(paintoverBurst: () => v))),
          _int('JPEG 精修质量（1-100）', _paintoverJpeg,
              (v) => _update(_p.copyWith(paintoverJpeg: () => v))),
          _tri('强制 CPU 编码', _p.useCpu,
              (v) => _update(_p.copyWith(useCpu: v))),
          _tri('CPU 多线程编码', _p.cpuThreading,
              (v) => _update(_p.copyWith(cpuThreading: v))),
        ]),
        _section('音频', [
          _int('音频码率 kbps', _audioBitrate,
              (v) => _update(_p.copyWith(
                  audioBitrate: () => v == null ? null : v * 1000)),
              hint: '如 128；留空跟随（默认 128）',
              stops: [for (final s in _audioBitrateStops) s ~/ 1000],
              map: (v) => v == null ? null : v * 1000),
          _tri('视频流', _p.video, (v) => _update(_p.copyWith(video: v)),
              hint: '连接后初始开关，可再改'),
          _tri('音频流', _p.audio, (v) => _update(_p.copyWith(audio: v))),
          _tri('麦克风', _p.microphone,
              (v) => _update(_p.copyWith(microphone: v)),
              hint: '需服务端开启麦克风转发'),
          _tri('摄像头', _p.webcam, (v) => _update(_p.copyWith(webcam: v)),
              hint: '需服务端开启摄像头转发'),
        ]),
        _section('显示', [
          _tri('手动分辨率', _p.manualResolution,
              (v) => _update(_p.copyWith(manualResolution: v)),
              hint: '开=锁定宽高；关=跟随窗口；跟随=不动服务端设置'),
          if (_p.manualResolution == TriState.on)
            Row(
              children: [
                Expanded(
                  child: _int('宽', _manualWidth,
                      (v) => _update(_p.copyWith(manualWidth: () => v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _int('高', _manualHeight,
                      (v) => _update(_p.copyWith(manualHeight: () => v))),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PopupMenuButton<String>(
                    tooltip: '常用分辨率',
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (preset) {
                      final wh = preset.split('x');
                      final w = int.parse(wh[0]);
                      final h = int.parse(wh[1]);
                      _manualWidth.text = w.toString();
                      _manualHeight.text = h.toString();
                      _update(_p.copyWith(
                          manualWidth: () => w, manualHeight: () => h));
                    },
                    itemBuilder: (_) => [
                      for (final r in _resPresets)
                        PopupMenuItem(value: r, child: Text(r)),
                    ],
                  ),
                ),
              ],
            ),
          _tri('本地缩放画布', _p.scaleLocally,
              (v) => _update(_p.copyWith(scaleLocally: v)),
              hint: '手动分辨率时拉伸填满窗口'),
          _tri('HiDPI', _p.hidpi, (v) => _update(_p.copyWith(hidpi: v)),
              hint: '高分屏清晰度；手动分辨率下默认关'),
          _tri('分辨率 16 对齐', _p.forceAligned,
              (v) => _update(_p.copyWith(forceAligned: v))),
          _enum('界面缩放', _p.uiScaling, UiScaling.values, _scalingText,
              (v) => _update(_p.copyWith(uiScaling: v))),
          _tri('抗锯齿', _p.antiAliasing,
              (v) => _update(_p.copyWith(antiAliasing: v))),
          _tri('浏览器原生光标', _p.nativeCursor,
              (v) => _update(_p.copyWith(nativeCursor: v))),
          _tri('原始指针移动', _p.rawPointer,
              (v) => _update(_p.copyWith(rawPointer: v)),
              hint: '无加速指针；mac 默认关'),
          _tri('mac Cmd 当 Ctrl', _p.macCmdAsCtrl,
              (v) => _update(_p.copyWith(macCmdAsCtrl: v)),
              hint: '仅 mac 客户端生效'),
        ]),
        _section('输入与手柄', [
          _tri('手柄输入', _p.gamepad,
              (v) => _update(_p.copyWith(gamepad: v))),
          _tri('手柄震动', _p.gamepadRumble,
              (v) => _update(_p.copyWith(gamepadRumble: v))),
          _tri('快捷键留给客户端', _p.shortcuts,
              (v) => _update(_p.copyWith(shortcuts: v)),
              hint: 'Ctrl+Shift 系列快捷键不进远端'),
          _tri('触控板模式', _p.trackpad,
              (v) => _update(_p.copyWith(trackpad: v)),
              hint: '触屏设备相对指针'),
        ]),
        _section('剪贴板', [
          _tri('上行（本机→远端）', _p.clipboardUp,
              (v) => _update(_p.copyWith(clipboardUp: v))),
          _tri('下行（远端→本机）', _p.clipboardDown,
              (v) => _update(_p.copyWith(clipboardDown: v))),
          _tri('无缝同步', _p.clipboardSeamless,
              (v) => _update(_p.copyWith(clipboardSeamless: v))),
          _tri('二进制（图片）', _p.clipboardBinary,
              (v) => _update(_p.copyWith(clipboardBinary: v))),
        ]),
        _section('其他', [
          _tri('打印自动弹出', _p.printAuto,
              (v) => _update(_p.copyWith(printAuto: v))),
          _tri('性能悬浮条', _p.statsStrip,
              (v) => _update(_p.copyWith(statsStrip: v))),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () {
                _framerate.clear();
                _videoBitrate.clear();
                _videoCrf.clear();
                _jpegQuality.clear();
                _paintoverCrf.clear();
                _paintoverBurst.clear();
                _paintoverJpeg.clear();
                _audioBitrate.clear();
                _manualWidth.clear();
                _manualHeight.clear();
                _update(const StreamPreset());
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('全部恢复跟随'),
            ),
          ),
        ]),
      ],
    );
  }
}
