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
    case "getAvailableSpellCheckLanguages":
      // Reported with underscores (`en_US`), and a language is usable only if
      // it appears here: iOS returns null for a tag it does not list, so
      // asking for a bare `es` fails while its own `es_ES` succeeds.
      result(UITextChecker.availableLanguages)
    case "getCurrentInputModeLanguage":
      result(KeyboardLanguagesPlugin.currentInputModeLanguage())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The primary language of whatever keyboard mode is active on the
  /// currently focused responder, or nil when nothing is focused. Finds the
  /// first responder by walking the key window's view hierarchy checking
  /// the public `isFirstResponder` property — UIKit exposes no direct
  /// "current first responder" query. `textInputMode` is declared on
  /// `UIResponder` itself (iOS 7+), so no `UITextInput` conformance check
  /// is needed. `UIApplication.windows` is deprecated in iOS 15+ in favor
  /// of scene-based lookup, but this podspec's floor is iOS 13.
  private static func currentInputModeLanguage() -> String? {
    guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    else { return nil }
    return firstResponder(in: window)?.textInputMode?.primaryLanguage
  }

  private static func firstResponder(in view: UIView) -> UIView? {
    if view.isFirstResponder { return view }
    for subview in view.subviews {
      if let found = firstResponder(in: subview) { return found }
    }
    return nil
  }
}
