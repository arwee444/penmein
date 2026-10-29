import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PenBeep") {
      let channel = FlutterMethodChannel(name: "penmein/beep", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "beep" else { return result(FlutterMethodNotImplemented) }
        Beep.play(call.arguments as? String ?? "end")
        result(nil)
      }
    }
  }
}

/// Dictation beeps, the iPhone counterpart of VoskListener.beep on Android:
/// start = recording starts, end = note saved, fail = nothing saved.
/// System sounds follow the ringer switch and volume.
enum Beep {
  static func play(_ kind: String) {
    switch kind {
    case "start": AudioServicesPlaySystemSound(1113)  // begin_record
    case "end": AudioServicesPlaySystemSound(1114)  // end_record
    default: AudioServicesPlaySystemSound(1053)  // negative
    }
  }
}
