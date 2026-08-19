import Flutter
import ObjectiveC
import UIKit

/// Gives Flutter's iOS text input view a UIKit `textInputContextIdentifier`.
///
/// UIKit restores the keyboard language (input mode) a user last picked for
/// any responder that reports a non-nil `textInputContextIdentifier`, and
/// persists that choice across launches. Flutter's `FlutterTextInputView`
/// inherits UIResponder's default (nil), and the engine exposes no way to set
/// it, so this plugin adds a getter to that class at runtime which returns
/// whatever identifier Dart last set via `setIdentifier`.
///
/// The engine creates a fresh `FlutterTextInputView` for every text input
/// client, so the identifier is cached per view on first read: the view that
/// became first responder with identifier X keeps reporting X for its whole
/// life even after Dart clears the identifier for the next field, and a view
/// created while the identifier is nil stays nil.
public class TextInputContextPlugin: NSObject, FlutterPlugin {
  private static let channelName = "pangea/text_input_context"
  private static let flutterTextInputViewClassName = "FlutterTextInputView"
  private static let getter = #selector(getter: UIResponder.textInputContextIdentifier)

  // All three are only touched on the main thread — the method channel
  // handler and UIKit's getter both run there — hence nonisolated(unsafe).
  /// The identifier the next text input view will report; nil for UIKit's
  /// default (no persistence).
  nonisolated(unsafe) private static var currentIdentifier: String?
  nonisolated(unsafe) private static var cachedIdentifierKey: UInt8 = 0
  nonisolated(unsafe) private static var installed = false

  /// Distinguishes "cached as nil" from "not cached yet" in the associated object.
  private final class CachedIdentifier {
    let value: String?
    init(_ value: String?) { self.value = value }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TextInputContextPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setIdentifier":
      let args = call.arguments as? [String: Any]
      TextInputContextPlugin.currentIdentifier = args?["identifier"] as? String
      result(TextInputContextPlugin.installGetterIfNeeded())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Adds the getter to FlutterTextInputView the first time it is needed.
  /// Returns whether the getter is installed — false means this engine build
  /// already implements the property itself (or renamed the class), in which
  /// case we leave it alone rather than fight it.
  @discardableResult
  private static func installGetterIfNeeded() -> Bool {
    if installed { return true }
    guard let viewClass = NSClassFromString(flutterTextInputViewClassName) else {
      NSLog("[text_input_context] %@ not found; keyboard language will not persist", flutterTextInputViewClassName)
      return false
    }
    let block: @convention(block) (UIResponder) -> NSString? = { view in
      if let cached = objc_getAssociatedObject(view, &cachedIdentifierKey) as? CachedIdentifier {
        return cached.value as NSString?
      }
      let identifier = currentIdentifier
      objc_setAssociatedObject(
        view, &cachedIdentifierKey, CachedIdentifier(identifier), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      return identifier as NSString?
    }
    let imp = imp_implementationWithBlock(block)
    // class_addMethod fails if the class already has its own implementation
    // (inherited ones don't count), which is exactly the case we must not
    // override blindly.
    installed = class_addMethod(viewClass, getter, imp, "@@:")
    if !installed {
      NSLog("[text_input_context] %@ already implements textInputContextIdentifier; not overriding", flutterTextInputViewClassName)
    }
    return installed
  }
}
