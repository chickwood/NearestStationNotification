import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backupChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "name.w57.nearest_station_notification/backup",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backupChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(
          FlutterError(
            code: "invalid_path",
            message: "path is required",
            details: nil
          )
        )
        return
      }
      var url = URL(fileURLWithPath: path)
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "exclude_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }
}
