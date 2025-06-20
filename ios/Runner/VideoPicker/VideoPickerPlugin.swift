import Flutter
import UIKit

public class VideoPickerPlugin: NSObject, FlutterPlugin {

  private var pendingResult: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(name: "video_picker",
                                  binaryMessenger: registrar.messenger())
    let inst = VideoPickerPlugin()
    registrar.addMethodCallDelegate(inst, channel: ch)
  }

  public func handle(_ call: FlutterMethodCall,
                     result: @escaping FlutterResult) {
    guard call.method == "pickVideo" else {
      result(FlutterMethodNotImplemented); return
    }
    pendingResult = result
    presentCamera()
  }

  private func presentCamera() {
    guard let root = UIApplication.shared.windows.first?.rootViewController else {
      pendingResult?(FlutterError(code: "NO_UI", message: "No root VC", details: nil))
      return
    }
    let cam = CustomCameraVC()
    cam.completion = { [weak self] videoPath, thumbPath in
      // `thumbPath` may be nil if user cancelled before export finished
      self?.pendingResult?(["path": videoPath as Any,
                            "thumbnail": thumbPath as Any])
      self?.pendingResult = nil
    }
    cam.modalPresentationStyle = .fullScreen
    root.present(cam, animated: true)
  }
}
