import 'package:uuid/uuid.dart';

const String kDefaultUrl = 'https://localhost:3001';

/// 传输通道：跟随服务端默认 / WebSocket / WebRTC。
enum StreamTransport { serverDefault, websockets, webrtc }

/// 编码器：跟随服务端默认，或锁定某一编码。
enum SelkiesEncoder {
  serverDefault,
  h264enc,
  h265enc,
  vp8enc,
  vp9enc,
  av1enc,
  h264encStriped,
  jpeg,
}

/// 码率控制：跟随服务端默认 / CBR / CRF。
enum RateControl { serverDefault, cbr, crf }

/// 摄像头上行编码偏好：跟随服务端默认 / 自动 / 指定编码。
enum WebcamEncoder {
  serverDefault,
  auto,
  h264,
  h265,
  vp8,
  vp9,
  av1,
  mjpeg,
}

/// UI 缩放：跟随服务端默认，或指定 DPI。
enum UiScaling {
  serverDefault,
  p100,
  p125,
  p150,
  p175,
  p200,
  p225,
  p250,
  p275,
  p300,
}

/// 三态开关：跟随服务端默认 / 开 / 关。
enum TriState { serverDefault, on, off }

/// Selkies 串流预设：链接前在首页配置，WebView 在文档起始写入
/// Selkies 的 localStorage（`<origin+path>_<key>` 命名空间，见
/// selkies-web-core/lib/util.js `getStorageAppName`）。
///
/// 约定：所有字段默认 = 跟随服务端/Selkies 默认（注入时不写对应键），
/// 用户显式选择后才写入对应键并覆盖 `_pick` 残留（见 selkies-web-core
/// 的 `held-settings.js`）。显式选择还会写 `<key>_explicit_choice=true`，
/// 以通过 Selkies 的 conditional-settings 梯子（见
/// `conditional-settings.js`）；链接后页内修改不受影响（注入脚本只覆盖
/// 本预设有值的键）。
class StreamPreset {
  /// 传输通道（`stream_mode`）。
  final StreamTransport transport;

  /// 视频编码器（`encoder`）。
  final SelkiesEncoder encoder;

  /// 摄像头上行编码（`webcam_encoder`）。
  final WebcamEncoder webcamEncoder;

  /// 4:4:4 全彩（`video_fullcolor`）。
  final TriState fullColor;

  /// 10bit（`video_10bit`）。
  final TriState tenBit;

  /// 帧率 fps；null = 跟随服务端。-1 = 跟随显示器刷新率（Selkies 约定
  /// `framerate=display`，见 selkies-web-core/lib/display-refresh.js）。
  final int? framerate;

  /// 码率控制（`rate_control_mode`）。
  final RateControl rateControl;

  /// CBR 码率 kbps（`video_bitrate`）；null = 跟随服务端。
  final int? videoBitrate;

  /// CRF 恒定质量（`video_crf`）；null = 跟随服务端。
  final int? videoCrf;

  /// Turbo 流式编码（`video_streaming_mode`，页内称 Turbo）。
  final TriState turbo;

  /// JPEG 质量（`jpeg_quality`，仅 JPEG 编码）；null = 跟随服务端。
  final int? jpegQuality;

  /// 静止画面精修（`use_paint_over_quality`）。
  final TriState paintOver;

  /// 精修 CRF（`video_paintover_crf`）；null = 跟随服务端。
  final int? paintoverCrf;

  /// 精修持续帧数（`video_paintover_burst_frames`）；null = 跟随服务端。
  final int? paintoverBurst;

  /// JPEG 精修质量（`paint_over_jpeg_quality`）；null = 跟随服务端。
  final int? paintoverJpeg;

  /// 强制 CPU 编码（`use_cpu`）。
  final TriState useCpu;

  /// CPU 多线程编码（`cpu_encode_threading`）。
  final TriState cpuThreading;

  /// 音频码率 bps（`audio_bitrate`）；null = 跟随服务端。
  final int? audioBitrate;

  /// 手动分辨率开关（`manual_resolution` + `manual_width/height`）。
  /// 开启且宽高有效时锁定分辨率；关闭 = 跟随窗口。
  final TriState manualResolution;

  /// 手动分辨率宽（偶数）。
  final int? manualWidth;

  /// 手动分辨率高（偶数）。
  final int? manualHeight;

  /// 本地缩放手动分辨率画布（`scaleLocallyManual`）。
  final TriState scaleLocally;

  /// HiDPI（`useCssScaling` 取反，见 conditional-settings `HIDPI_SPEC`）。
  final TriState hidpi;

  /// 分辨率对齐到 16 的倍数（`force_aligned_resolution`）。
  final TriState forceAligned;

  /// UI 缩放（`scaling_dpi`）。
  final UiScaling uiScaling;

  /// 抗锯齿（`antiAliasingEnabled`，纯客户端）。
  final TriState antiAliasing;

  /// 浏览器原生光标样式（`use_browser_cursors`）。
  final TriState nativeCursor;

  /// 原始指针移动（`raw_pointer_motion`）。
  final TriState rawPointer;

  /// macOS Cmd 当 Ctrl（`mac_cmd_as_ctrl`，仅 mac 客户端生效）。
  final TriState macCmdAsCtrl;

  /// 视频流开关（`__selkies_preset_pipeline=video:0/1`，连接后 core 应用）。
  final TriState video;

  /// 音频流开关（同上 `audio`）。
  final TriState audio;

  /// 麦克风开关（同上 `microphone`）。
  final TriState microphone;

  /// 摄像头开关（同上 `webcam`）。
  final TriState webcam;

  /// 手柄输入开关（`isGamepadEnabled`）。
  final TriState gamepad;

  /// 手柄震动（`gamepad_rumble`）。
  final TriState gamepadRumble;

  /// 剪贴板上行（本机→远端，`clipboard_in_enabled`）。
  final TriState clipboardUp;

  /// 剪贴板下行（远端→本机，`clipboard_out_enabled`）。
  final TriState clipboardDown;

  /// 剪贴板无缝同步（`clipboard_seamless`）。
  final TriState clipboardSeamless;

  /// 二进制剪贴板（图片，`enable_binary_clipboard`）。
  final TriState clipboardBinary;

  /// 快捷键保留给客户端（`keyboard_shortcuts`）。
  final TriState shortcuts;

  /// 触控板模式（`trackpadMode`，纯客户端）。
  final TriState trackpad;

  /// 触控板速度倍率（`trackpad_speed`）；null = 跟随默认（1x）。
  final double? trackpadSpeed;

  /// 打印自动弹出（`print_auto`，纯客户端）。
  final TriState printAuto;

  /// 性能悬浮条（`stats_strip`，纯客户端）。
  final TriState statsStrip;

  const StreamPreset({
    this.transport = StreamTransport.serverDefault,
    this.encoder = SelkiesEncoder.serverDefault,
    this.webcamEncoder = WebcamEncoder.serverDefault,
    this.fullColor = TriState.serverDefault,
    this.tenBit = TriState.serverDefault,
    this.framerate,
    this.rateControl = RateControl.serverDefault,
    this.videoBitrate,
    this.videoCrf,
    this.turbo = TriState.serverDefault,
    this.jpegQuality,
    this.paintOver = TriState.serverDefault,
    this.paintoverCrf,
    this.paintoverBurst,
    this.paintoverJpeg,
    this.useCpu = TriState.serverDefault,
    this.cpuThreading = TriState.serverDefault,
    this.audioBitrate,
    this.manualResolution = TriState.serverDefault,
    this.manualWidth,
    this.manualHeight,
    this.scaleLocally = TriState.serverDefault,
    this.hidpi = TriState.serverDefault,
    this.forceAligned = TriState.serverDefault,
    this.uiScaling = UiScaling.serverDefault,
    this.antiAliasing = TriState.serverDefault,
    this.nativeCursor = TriState.serverDefault,
    this.rawPointer = TriState.serverDefault,
    this.macCmdAsCtrl = TriState.serverDefault,
    this.video = TriState.serverDefault,
    this.audio = TriState.serverDefault,
    this.microphone = TriState.serverDefault,
    this.webcam = TriState.serverDefault,
    this.gamepad = TriState.serverDefault,
    this.gamepadRumble = TriState.serverDefault,
    this.clipboardUp = TriState.serverDefault,
    this.clipboardDown = TriState.serverDefault,
    this.clipboardSeamless = TriState.serverDefault,
    this.clipboardBinary = TriState.serverDefault,
    this.shortcuts = TriState.serverDefault,
    this.trackpad = TriState.serverDefault,
    this.trackpadSpeed,
    this.printAuto = TriState.serverDefault,
    this.statsStrip = TriState.serverDefault,
  });

  /// 是否有任何显式预设（决定是否注入脚本）。
  bool get hasExplicit {
    return transport != StreamTransport.serverDefault ||
        encoder != SelkiesEncoder.serverDefault ||
        webcamEncoder != WebcamEncoder.serverDefault ||
        fullColor != TriState.serverDefault ||
        tenBit != TriState.serverDefault ||
        framerate != null ||
        rateControl != RateControl.serverDefault ||
        videoBitrate != null ||
        videoCrf != null ||
        turbo != TriState.serverDefault ||
        jpegQuality != null ||
        paintOver != TriState.serverDefault ||
        paintoverCrf != null ||
        paintoverBurst != null ||
        paintoverJpeg != null ||
        useCpu != TriState.serverDefault ||
        cpuThreading != TriState.serverDefault ||
        audioBitrate != null ||
        manualResolution != TriState.serverDefault ||
        scaleLocally != TriState.serverDefault ||
        hidpi != TriState.serverDefault ||
        forceAligned != TriState.serverDefault ||
        uiScaling != UiScaling.serverDefault ||
        antiAliasing != TriState.serverDefault ||
        nativeCursor != TriState.serverDefault ||
        rawPointer != TriState.serverDefault ||
        macCmdAsCtrl != TriState.serverDefault ||
        video != TriState.serverDefault ||
        audio != TriState.serverDefault ||
        microphone != TriState.serverDefault ||
        webcam != TriState.serverDefault ||
        gamepad != TriState.serverDefault ||
        gamepadRumble != TriState.serverDefault ||
        clipboardUp != TriState.serverDefault ||
        clipboardDown != TriState.serverDefault ||
        clipboardSeamless != TriState.serverDefault ||
        clipboardBinary != TriState.serverDefault ||
        shortcuts != TriState.serverDefault ||
        trackpad != TriState.serverDefault ||
        trackpadSpeed != null ||
        printAuto != TriState.serverDefault ||
        statsStrip != TriState.serverDefault;
  }

  static TriState _triFromJson(dynamic v) {
    if (v == 'on') return TriState.on;
    if (v == 'off') return TriState.off;
    return TriState.serverDefault;
  }

  static String? _triToJson(TriState v) {
    if (v == TriState.on) return 'on';
    if (v == TriState.off) return 'off';
    return null;
  }

  StreamPreset copyWith({
    StreamTransport? transport,
    SelkiesEncoder? encoder,
    WebcamEncoder? webcamEncoder,
    TriState? fullColor,
    TriState? tenBit,
    int? Function()? framerate,
    RateControl? rateControl,
    int? Function()? videoBitrate,
    int? Function()? videoCrf,
    TriState? turbo,
    int? Function()? jpegQuality,
    TriState? paintOver,
    int? Function()? paintoverCrf,
    int? Function()? paintoverBurst,
    int? Function()? paintoverJpeg,
    TriState? useCpu,
    TriState? cpuThreading,
    int? Function()? audioBitrate,
    TriState? manualResolution,
    int? Function()? manualWidth,
    int? Function()? manualHeight,
    TriState? scaleLocally,
    TriState? hidpi,
    TriState? forceAligned,
    UiScaling? uiScaling,
    TriState? antiAliasing,
    TriState? nativeCursor,
    TriState? rawPointer,
    TriState? macCmdAsCtrl,
    TriState? video,
    TriState? audio,
    TriState? microphone,
    TriState? webcam,
    TriState? gamepad,
    TriState? gamepadRumble,
    TriState? clipboardUp,
    TriState? clipboardDown,
    TriState? clipboardSeamless,
    TriState? clipboardBinary,
    TriState? shortcuts,
    TriState? trackpad,
    double? Function()? trackpadSpeed,
    TriState? printAuto,
    TriState? statsStrip,
  }) {
    return StreamPreset(
      transport: transport ?? this.transport,
      encoder: encoder ?? this.encoder,
      webcamEncoder: webcamEncoder ?? this.webcamEncoder,
      fullColor: fullColor ?? this.fullColor,
      tenBit: tenBit ?? this.tenBit,
      framerate: framerate != null ? framerate() : this.framerate,
      rateControl: rateControl ?? this.rateControl,
      videoBitrate:
          videoBitrate != null ? videoBitrate() : this.videoBitrate,
      videoCrf: videoCrf != null ? videoCrf() : this.videoCrf,
      turbo: turbo ?? this.turbo,
      jpegQuality:
          jpegQuality != null ? jpegQuality() : this.jpegQuality,
      paintOver: paintOver ?? this.paintOver,
      paintoverCrf:
          paintoverCrf != null ? paintoverCrf() : this.paintoverCrf,
      paintoverBurst:
          paintoverBurst != null ? paintoverBurst() : this.paintoverBurst,
      paintoverJpeg:
          paintoverJpeg != null ? paintoverJpeg() : this.paintoverJpeg,
      useCpu: useCpu ?? this.useCpu,
      cpuThreading: cpuThreading ?? this.cpuThreading,
      audioBitrate:
          audioBitrate != null ? audioBitrate() : this.audioBitrate,
      manualResolution: manualResolution ?? this.manualResolution,
      manualWidth:
          manualWidth != null ? manualWidth() : this.manualWidth,
      manualHeight:
          manualHeight != null ? manualHeight() : this.manualHeight,
      scaleLocally: scaleLocally ?? this.scaleLocally,
      hidpi: hidpi ?? this.hidpi,
      forceAligned: forceAligned ?? this.forceAligned,
      uiScaling: uiScaling ?? this.uiScaling,
      antiAliasing: antiAliasing ?? this.antiAliasing,
      nativeCursor: nativeCursor ?? this.nativeCursor,
      rawPointer: rawPointer ?? this.rawPointer,
      macCmdAsCtrl: macCmdAsCtrl ?? this.macCmdAsCtrl,
      video: video ?? this.video,
      audio: audio ?? this.audio,
      microphone: microphone ?? this.microphone,
      webcam: webcam ?? this.webcam,
      gamepad: gamepad ?? this.gamepad,
      gamepadRumble: gamepadRumble ?? this.gamepadRumble,
      clipboardUp: clipboardUp ?? this.clipboardUp,
      clipboardDown: clipboardDown ?? this.clipboardDown,
      clipboardSeamless: clipboardSeamless ?? this.clipboardSeamless,
      clipboardBinary: clipboardBinary ?? this.clipboardBinary,
      shortcuts: shortcuts ?? this.shortcuts,
      trackpad: trackpad ?? this.trackpad,
      trackpadSpeed:
          trackpadSpeed != null ? trackpadSpeed() : this.trackpadSpeed,
      printAuto: printAuto ?? this.printAuto,
      statsStrip: statsStrip ?? this.statsStrip,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    void tri(String k, TriState v) {
      final s = _triToJson(v);
      if (s != null) m[k] = s;
    }
    if (transport != StreamTransport.serverDefault) {
      m['transport'] = transport.name;
    }
    if (encoder != SelkiesEncoder.serverDefault) m['encoder'] = encoder.name;
    if (webcamEncoder != WebcamEncoder.serverDefault) {
      m['webcamEncoder'] = webcamEncoder.name;
    }
    tri('fullColor', fullColor);
    tri('tenBit', tenBit);
    if (framerate != null) m['framerate'] = framerate;
    if (rateControl != RateControl.serverDefault) {
      m['rateControl'] = rateControl.name;
    }
    if (videoBitrate != null) m['videoBitrate'] = videoBitrate;
    if (videoCrf != null) m['videoCrf'] = videoCrf;
    tri('turbo', turbo);
    if (jpegQuality != null) m['jpegQuality'] = jpegQuality;
    tri('paintOver', paintOver);
    if (paintoverCrf != null) m['paintoverCrf'] = paintoverCrf;
    if (paintoverBurst != null) m['paintoverBurst'] = paintoverBurst;
    if (paintoverJpeg != null) m['paintoverJpeg'] = paintoverJpeg;
    tri('useCpu', useCpu);
    tri('cpuThreading', cpuThreading);
    if (audioBitrate != null) m['audioBitrate'] = audioBitrate;
    tri('manualResolution', manualResolution);
    if (manualWidth != null) m['manualWidth'] = manualWidth;
    if (manualHeight != null) m['manualHeight'] = manualHeight;
    tri('scaleLocally', scaleLocally);
    tri('hidpi', hidpi);
    tri('forceAligned', forceAligned);
    if (uiScaling != UiScaling.serverDefault) m['uiScaling'] = uiScaling.name;
    tri('antiAliasing', antiAliasing);
    tri('nativeCursor', nativeCursor);
    tri('rawPointer', rawPointer);
    tri('macCmdAsCtrl', macCmdAsCtrl);
    tri('video', video);
    tri('audio', audio);
    tri('microphone', microphone);
    tri('webcam', webcam);
    tri('gamepad', gamepad);
    tri('gamepadRumble', gamepadRumble);
    tri('clipboardUp', clipboardUp);
    tri('clipboardDown', clipboardDown);
    tri('clipboardSeamless', clipboardSeamless);
    tri('clipboardBinary', clipboardBinary);
    tri('shortcuts', shortcuts);
    tri('trackpad', trackpad);
    if (trackpadSpeed != null) m['trackpadSpeed'] = trackpadSpeed;
    tri('printAuto', printAuto);
    tri('statsStrip', statsStrip);
    return m;
  }

  factory StreamPreset.fromJson(Map<String, dynamic> json) {
    T enumOr<T extends Enum>(dynamic v, List<T> values, T fallback) {
      if (v is! String) return fallback;
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }
    int? intOr(dynamic v) => v is num ? v.toInt() : null;
    double? dblOr(dynamic v) => v is num ? v.toDouble() : null;
    return StreamPreset(
      transport: enumOr(json['transport'], StreamTransport.values,
          StreamTransport.serverDefault),
      encoder: enumOr(json['encoder'], SelkiesEncoder.values,
          SelkiesEncoder.serverDefault),
      webcamEncoder: enumOr(json['webcamEncoder'], WebcamEncoder.values,
          WebcamEncoder.serverDefault),
      fullColor: _triFromJson(json['fullColor']),
      tenBit: _triFromJson(json['tenBit']),
      framerate: intOr(json['framerate']),
      rateControl: enumOr(json['rateControl'], RateControl.values,
          RateControl.serverDefault),
      videoBitrate: intOr(json['videoBitrate']),
      videoCrf: intOr(json['videoCrf']),
      turbo: _triFromJson(json['turbo']),
      jpegQuality: intOr(json['jpegQuality']),
      paintOver: _triFromJson(json['paintOver']),
      paintoverCrf: intOr(json['paintoverCrf']),
      paintoverBurst: intOr(json['paintoverBurst']),
      paintoverJpeg: intOr(json['paintoverJpeg']),
      useCpu: _triFromJson(json['useCpu']),
      cpuThreading: _triFromJson(json['cpuThreading']),
      audioBitrate: intOr(json['audioBitrate']),
      manualResolution: _triFromJson(json['manualResolution']),
      manualWidth: intOr(json['manualWidth']),
      manualHeight: intOr(json['manualHeight']),
      scaleLocally: _triFromJson(json['scaleLocally']),
      hidpi: _triFromJson(json['hidpi']),
      forceAligned: _triFromJson(json['forceAligned']),
      uiScaling: enumOr(
          json['uiScaling'], UiScaling.values, UiScaling.serverDefault),
      antiAliasing: _triFromJson(json['antiAliasing']),
      nativeCursor: _triFromJson(json['nativeCursor']),
      rawPointer: _triFromJson(json['rawPointer']),
      macCmdAsCtrl: _triFromJson(json['macCmdAsCtrl']),
      video: _triFromJson(json['video']),
      audio: _triFromJson(json['audio']),
      microphone: _triFromJson(json['microphone']),
      webcam: _triFromJson(json['webcam']),
      gamepad: _triFromJson(json['gamepad']),
      gamepadRumble: _triFromJson(json['gamepadRumble']),
      clipboardUp: _triFromJson(json['clipboardUp']),
      clipboardDown: _triFromJson(json['clipboardDown']),
      clipboardSeamless: _triFromJson(json['clipboardSeamless']),
      clipboardBinary: _triFromJson(json['clipboardBinary']),
      shortcuts: _triFromJson(json['shortcuts']),
      trackpad: _triFromJson(json['trackpad']),
      trackpadSpeed: dblOr(json['trackpadSpeed']),
      printAuto: _triFromJson(json['printAuto']),
      statsStrip: _triFromJson(json['statsStrip']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StreamPreset &&
        transport == other.transport &&
        encoder == other.encoder &&
        webcamEncoder == other.webcamEncoder &&
        fullColor == other.fullColor &&
        tenBit == other.tenBit &&
        framerate == other.framerate &&
        rateControl == other.rateControl &&
        videoBitrate == other.videoBitrate &&
        videoCrf == other.videoCrf &&
        turbo == other.turbo &&
        jpegQuality == other.jpegQuality &&
        paintOver == other.paintOver &&
        paintoverCrf == other.paintoverCrf &&
        paintoverBurst == other.paintoverBurst &&
        paintoverJpeg == other.paintoverJpeg &&
        useCpu == other.useCpu &&
        cpuThreading == other.cpuThreading &&
        audioBitrate == other.audioBitrate &&
        manualResolution == other.manualResolution &&
        manualWidth == other.manualWidth &&
        manualHeight == other.manualHeight &&
        scaleLocally == other.scaleLocally &&
        hidpi == other.hidpi &&
        forceAligned == other.forceAligned &&
        uiScaling == other.uiScaling &&
        antiAliasing == other.antiAliasing &&
        nativeCursor == other.nativeCursor &&
        rawPointer == other.rawPointer &&
        macCmdAsCtrl == other.macCmdAsCtrl &&
        video == other.video &&
        audio == other.audio &&
        microphone == other.microphone &&
        webcam == other.webcam &&
        gamepad == other.gamepad &&
        gamepadRumble == other.gamepadRumble &&
        clipboardUp == other.clipboardUp &&
        clipboardDown == other.clipboardDown &&
        clipboardSeamless == other.clipboardSeamless &&
        clipboardBinary == other.clipboardBinary &&
        shortcuts == other.shortcuts &&
        trackpad == other.trackpad &&
        trackpadSpeed == other.trackpadSpeed &&
        printAuto == other.printAuto &&
        statsStrip == other.statsStrip;
  }

  @override
  int get hashCode => Object.hashAll([
        transport,
        encoder,
        webcamEncoder,
        fullColor,
        tenBit,
        framerate,
        rateControl,
        videoBitrate,
        videoCrf,
        turbo,
        jpegQuality,
        paintOver,
        paintoverCrf,
        paintoverBurst,
        paintoverJpeg,
        useCpu,
        cpuThreading,
        audioBitrate,
        manualResolution,
        manualWidth,
        manualHeight,
        scaleLocally,
        hidpi,
        forceAligned,
        uiScaling,
        antiAliasing,
        nativeCursor,
        rawPointer,
        macCmdAsCtrl,
        video,
        audio,
        microphone,
        webcam,
        gamepad,
        gamepadRumble,
        clipboardUp,
        clipboardDown,
        clipboardSeamless,
        clipboardBinary,
        shortcuts,
        trackpad,
        trackpadSpeed,
        printAuto,
        statsStrip,
      ]);
}

/// 表示一个 wechat-selkies 连接配置。
class Connection {
  final String id;
  final String name;
  final String url;

  /// 是否忽略 SSL 证书错误（自签名证书场景）。
  final bool ignoreSsl;

  /// 是否使用系统默认浏览器打开（而非应用内 WebView）。
  final bool openExternal;

  /// 是否注入 IME 整段提交脚本（修复中文输入吃字，默认开）。
  final bool imeFix;

  /// 可选的 HTTP Basic 认证用户名。
  final String username;

  /// 可选的 HTTP Basic 认证密码。
  final String password;

  /// 可选的 FileBrowser 文件管理地址（连接页标题栏按钮跳系统浏览器）。
  final String fileBrowserUrl;

  /// 串流预设（链接前设置，默认全跟随服务端）。
  final StreamPreset preset;

  const Connection({
    required this.id,
    required this.name,
    required this.url,
    this.ignoreSsl = true,
    this.openExternal = false,
    this.imeFix = true,
    this.username = '',
    this.password = '',
    this.fileBrowserUrl = '',
    this.preset = const StreamPreset(),
  });

  /// 创建一个带新 ID 的连接。
  factory Connection.create({
    String name = '未命名',
    String url = kDefaultUrl,
    bool ignoreSsl = true,
    bool openExternal = false,
    bool imeFix = true,
    String username = '',
    String password = '',
    String fileBrowserUrl = '',
    StreamPreset preset = const StreamPreset(),
  }) {
    return Connection(
      id: const Uuid().v4(),
      name: name,
      url: url,
      ignoreSsl: ignoreSsl,
      openExternal: openExternal,
      imeFix: imeFix,
      username: username,
      password: password,
      fileBrowserUrl: fileBrowserUrl,
      preset: preset,
    );
  }

  /// 默认连接（首次启动时自动创建）。
  factory Connection.defaultConnection() {
    return Connection.create(
      name: '本地微信',
      url: kDefaultUrl,
      ignoreSsl: true,
    );
  }

  bool get hasBasicAuth => username.trim().isNotEmpty || password.isNotEmpty;

  Connection copyWith({
    String? id,
    String? name,
    String? url,
    bool? ignoreSsl,
    bool? openExternal,
    bool? imeFix,
    String? username,
    String? password,
    String? fileBrowserUrl,
    StreamPreset? preset,
  }) {
    return Connection(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      ignoreSsl: ignoreSsl ?? this.ignoreSsl,
      openExternal: openExternal ?? this.openExternal,
      imeFix: imeFix ?? this.imeFix,
      username: username ?? this.username,
      password: password ?? this.password,
      fileBrowserUrl: fileBrowserUrl ?? this.fileBrowserUrl,
      preset: preset ?? this.preset,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'ignoreSsl': ignoreSsl,
        'openExternal': openExternal,
        'imeFix': imeFix,
        'username': username,
        'password': password,
        'fileBrowserUrl': fileBrowserUrl,
        'preset': preset.toJson(),
      };

  factory Connection.fromJson(Map<String, dynamic> json) {
    final p = json['preset'];
    return Connection(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      name: (json['name'] as String?) ?? '未命名',
      url: (json['url'] as String?) ?? kDefaultUrl,
      ignoreSsl: json['ignoreSsl'] != false,
      openExternal: json['openExternal'] == true,
      imeFix: json['imeFix'] != false,
      username: (json['username'] as String?) ?? '',
      password: json['password'] == null ? '' : json['password'].toString(),
      fileBrowserUrl: (json['fileBrowserUrl'] as String?) ?? '',
      preset: p is Map
          ? StreamPreset.fromJson(Map<String, dynamic>.from(p))
          : const StreamPreset(),
    );
  }
}
