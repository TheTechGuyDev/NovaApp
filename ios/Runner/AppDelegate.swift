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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NovaSecurity") {
      let channel = FlutterMethodChannel(name: "nova/security", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "integrity": result(AppDelegate.jailbreakSigns())
        case "secureScreen": result(nil) // iOS has no screenshot block API
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// Signs that the device is jailbroken. Empty = looks clean.
  static func jailbreakSigns() -> [String] {
    #if targetEnvironment(simulator)
    return []
    #else
    var signs: [String] = []
    let paths = [
      "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib", "/bin/bash", "/usr/sbin/sshd",
      "/etc/apt", "/private/var/lib/apt/", "/usr/bin/ssh", "/var/jb", "/private/preboot/jb",
      "/usr/lib/libsubstitute.dylib", "/usr/lib/TweakInject",
    ]
    if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { signs.append("jailbreak_files") }
    let probe = "/private/nova_jb_probe.txt"
    if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
      try? FileManager.default.removeItem(atPath: probe)
      signs.append("sandbox_writable")
    }
    if let url = URL(string: "cydia://package/com.example"), UIApplication.shared.canOpenURL(url) {
      signs.append("cydia_scheme")
    }
    return signs
    #endif
  }
}
