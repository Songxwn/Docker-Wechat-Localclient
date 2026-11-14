import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let clipboardChannel = FlutterMethodChannel(
      name: "wechat_selkies/clipboard_image",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "writeImage",
            let args = call.arguments as? [String: Any],
            let typed = args["data"] as? FlutterStandardTypedData,
            !typed.data.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }
      let mime = (args["mimeType"] as? String) ?? "image/png"
      // NSPasteboard 只认 UTI(如 public.png);直接把 MIME 字符串
      // "image/png" 当类型写入会变成无人能读的自定义类型,粘贴时拿不到内容。
      let uti: NSPasteboard.PasteboardType
      switch mime {
      case "image/png", "image/apng":
        uti = NSPasteboard.PasteboardType("public.png")
      case "image/jpeg", "image/jpg":
        uti = NSPasteboard.PasteboardType("public.jpeg")
      case "image/tiff", "image/tif":
        uti = NSPasteboard.PasteboardType("public.tiff")
      case "image/gif":
        uti = NSPasteboard.PasteboardType("com.compuserve.gif")
      case "image/bmp":
        uti = NSPasteboard.PasteboardType("com.microsoft.bmp")
      case "image/webp":
        uti = NSPasteboard.PasteboardType("public.webp")
      default:
        uti = NSPasteboard.PasteboardType(mime)
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      var ok = pasteboard.setData(typed.data, forType: uti)
      if !ok, let img = NSImage(data: typed.data) {
        // 原始字节写不进去(如 mime 未映射)时经 NSImage 转写,
        // macOS 会自动提供 TIFF 等转换格式。
        pasteboard.clearContents()
        ok = pasteboard.writeObjects([img])
      }
      if ok {
        result(nil)
      } else {
        result(FlutterError(code: "write_failed",
                            message: "NSPasteboard write failed",
                            details: mime))
      }
    }

    super.awakeFromNib()
  }
}
