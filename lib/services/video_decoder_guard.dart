/// macOS WebCodecs 资源泄漏的页面级兜底。
///
/// 已知问题：macOS 上 WebCodecs 的 `VideoDecoder` 在页面不可见时不会自动
/// 释放 VideoToolbox/CoreMedia 资源；Selkies 页面只停止绘制，仍继续解码，
/// 于是 WebContent 进程的 `CMSampleBuffer` 持续累积（实测 26 小时约 3.1M 个，
/// 进程 footprint 2.7 GB）。Chromium/WebCodecs 同一问题的结论是：页面隐藏时
/// 必须显式 `decoder.close()`，可见时再重建。
///
/// 本脚本在 document-start 包装 `VideoDecoder`：
/// 1. 记录页面创建的所有 decoder；
/// 2. 页面隐藏/停止 requestAnimationFrame（被遮挡、最小化、切到后台）时关闭
///    全部 decoder，并丢弃隐藏期间的 decode 调用；
/// 3. 恢复可见时再关闭一次（丢弃隐藏期间重建的实例），让页面按自己的
///    “decoder closed → initializeDecoder” 路径重建。
///
/// 不改变可见期间的解码/绘制路径；只影响隐藏期间的解码资源。
String videoDecoderVisibilityGuardScript() => r'''
(function(){
  if (window.__selkiesVideoDecoderGuard) return;
  window.__selkiesVideoDecoderGuard = true;

  var decoders = [];
  var lastRaf = Date.now();
  var hidden = false;

  function raf(){
    lastRaf = Date.now();
    window.requestAnimationFrame(raf);
  }
  window.requestAnimationFrame(raf);

  // document.hidden 覆盖最小化/切后台；rAF 停止覆盖窗口被遮挡但页面仍报
  // visible 的情况。两者任一成立都视为后台。
  function isBackground(){
    try {
      if (document.hidden || document.visibilityState === 'hidden') return true;
    } catch(e) {}
    return Date.now() - lastRaf > 1500;
  }

  function closeAll(){
    for (var i = 0; i < decoders.length; i++) {
      var d = decoders[i];
      try { if (d && d.state !== 'closed') d.close(); } catch(e) {}
    }
    decoders.length = 0;
  }

  function install(){
    var VD = window.VideoDecoder;
    if (!VD || VD.__guardInstalled) return false;

    var origDecode = VD.prototype.decode;
    VD.prototype.decode = function(chunk){
      if (isBackground()) return;
      return origDecode.apply(this, arguments);
    };

    var Wrapped = new Proxy(VD, {
      construct: function(target, args){
        var d = Reflect.construct(target, args);
        try { decoders.push(d); } catch(e) {}
        return d;
      }
    });
    try {
      Object.defineProperty(window, 'VideoDecoder', {
        value: Wrapped, configurable: true, writable: true
      });
    } catch(e) {
      try { window.VideoDecoder = Wrapped; } catch(e2) { return false; }
    }
    if (window.VideoDecoder !== Wrapped) return false;
    VD.__guardInstalled = true;
    return true;
  }

  if (!install()) {
    var tries = 0;
    var t = setInterval(function(){
      if (install() || ++tries > 100) clearInterval(t);
    }, 50);
  }

  function update(){
    var h = isBackground();
    if (h === hidden) return;
    hidden = h;
    // 进入后台：释放 VT/CoreMedia 资源；回到前台：重置隐藏期间重建的实例，
    // 让页面从下一个 keyframe 重新配置。
    closeAll();
  }

  setInterval(update, 500);
  document.addEventListener('visibilitychange', update);
  update();
})();
''';
