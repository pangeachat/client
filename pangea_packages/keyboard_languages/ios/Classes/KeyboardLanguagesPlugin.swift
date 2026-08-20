import Flutter
import UIKit

/// Reports the primary language of every keyboard the user has enabled,
/// via `UITextInputMode.activeInputModes` — a public, unpermissioned UIKit
/// API. Non-language input modes (emoji, dictation) come through with
/// whatever `primaryLanguage` the system reports for them rather than being
/// filtered here; only the Dart caller knows which entries are
/// language-shaped. See target-language-keyboard.instructions.md in the
/// client repo.
public class KeyboardLanguagesPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pangea/keyboard_languages", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(KeyboardLanguagesPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getEnabledLanguageTags":
      let tags = UITextInputMode.activeInputModes.compactMap { $0.primaryLanguage }
      result(tags)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
