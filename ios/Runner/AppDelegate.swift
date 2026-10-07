import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Already declared on both Runner and the Notification Service Extension.
  private static let appGroupId = "group.com.talktolearn.chat"
  private static let sessionFileName = "nse_session.json"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    registerSessionChannel()
    registerBackupExclusionChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Mirrors the Matrix session into the App Group container so the
  /// Notification Service Extension can fetch authenticated media for a
  /// notification the app never sees.
  private func registerSessionChannel() {
    guard let messenger = registrar(forPlugin: "PangeaNseSession")?.messenger() else { return }
    let channel = FlutterMethodChannel(name: "chat.pangea/nse_session", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "store":
        guard let json = call.arguments as? String else {
          result(false)
          return
        }
        result(Self.writeSession(json))
      case "clear":
        result(Self.writeSession(nil))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Flags a directory as excluded from iCloud/device backup. Used for call
  /// recordings waiting to upload: they are transient, can be large, and are
  /// not the learner's to have restored onto another device.
  private func registerBackupExclusionChannel() {
    guard let messenger = registrar(forPlugin: "PangeaBackupExclusion")?.messenger() else { return }
    let channel = FlutterMethodChannel(name: "chat.pangea/backup_exclusion", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "exclude":
        guard let path = call.arguments as? String else {
          result(false)
          return
        }
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func writeSession(_ json: String?) -> Bool {
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return false }
    let url = container.appendingPathComponent(sessionFileName)

    do {
      guard let json else {
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
        return true
      }
      guard let data = json.data(using: .utf8) else { return false }
      // Matches the `first_unlock` accessibility the session backup already
      // uses: readable by the extension while the device is locked, but not
      // before the first unlock since boot.
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      return false
    }
  }
}
