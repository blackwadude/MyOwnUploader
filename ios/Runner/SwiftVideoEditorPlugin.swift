import Flutter
import UIKit
import AVFoundation

public class SwiftVideoEditorPlugin: NSObject, FlutterPlugin {
  private var resultCallback: FlutterResult?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.example.video_editor", binaryMessenger: registrar.messenger())
    let instance = SwiftVideoEditorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "openEditor":
      self.resultCallback = result
      let args = call.arguments as? [String: Any]
      let initial = args?["videoPath"] as? String
      DispatchQueue.main.async {
        self.presentEditor(initialPath: initial)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentEditor(initialPath: String?) {
    // Instantiate your editor VC
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    guard let editorVC = storyboard.instantiateViewController(withIdentifier: "VideoEditorViewController") as? VideoEditorViewController else {
      resultCallback?(FlutterError(code: "vc_not_found", message: "Could not load editor VC", details: nil))
      return
    }
    editorVC.initialVideoURL = initialPath != nil ? URL(fileURLWithPath: initialPath!) : nil
    editorVC.delegate = self

    guard let root = UIApplication.shared.keyWindow?.rootViewController else {
      resultCallback?(FlutterError(code: "no_root_vc", message: "No root VC found", details: nil))
      return
    }
    root.present(editorVC, animated: true)
  }
}

extension SwiftVideoEditorPlugin: VideoEditorDelegate {
  public func videoEditor(_ editor: UIViewController, didFinishEditing videoURL: URL, audioURL: URL?) {
    editor.dismiss(animated: true) {
      var map: [String: String] = ["videoPath": videoURL.path]
      if let audio = audioURL { map["audioPath"] = audio.path }
      self.resultCallback?(map)
    }
  }

  public func videoEditorDidCancel(_ editor: UIViewController) {
    editor.dismiss(animated: true) {
      self.resultCallback?(nil)
    }
  }
}
