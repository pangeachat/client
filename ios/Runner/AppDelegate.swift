import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import WebRTC

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Already declared on both Runner and the Notification Service Extension.
  private static let appGroupId = "group.com.talktolearn.chat"
  private static let sessionFileName = "nse_session.json"

  /// Rings for incoming calls on the iOS call screen. Created at launch,
  /// because a VoIP push can be what launched the app.
  private var callScreen: CallScreen?

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
    if let messenger = registrar(forPlugin: "PangeaCallScreen")?.messenger() {
      callScreen = CallScreen(messenger: messenger)
    }
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

/// Rings for an incoming call on the iOS call screen (CallKit), woken by a VoIP
/// push (PushKit). pangeachat/client#9411; design in
/// voice-video-calls.instructions.md, "Ringing when the app is closed".
///
/// Apple stops waking an app that does not show a call for every VoIP push it
/// receives, so the call screen goes up here, from the push alone, before any
/// Dart has run. The app then reads the ring and ends the call screen at once
/// if the ring is already over. Sygnal sends this app VoIP pushes for call
/// rings and nothing else.
final class CallScreen: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
  private let channel: FlutterMethodChannel
  private let registry = PKPushRegistry(queue: .main)
  private let provider: CXProvider

  /// What the app needs to find each call on the screen, by CallKit id.
  private var calls: [UUID: [String: Any]] = [:]
  private var answered: Set<UUID> = []

  /// Events from before the app was listening. The app is usually launched BY
  /// the push, so it starts listening well after the call screen went up.
  private var pending: [(String, [String: Any])] = []
  private var listening = false
  private var voipToken: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "chat.pangea/call_screen", binaryMessenger: messenger)
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallGroups = 1
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    // A language-learning call is not a phone call the learner wants in the
    // Phone app's history.
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "listen":
      listening = true
      let due = pending
      pending.removeAll()
      for (method, info) in due { channel.invokeMethod(method, arguments: info) }
      result(voipToken)
    case "end":
      // The app ended the call: the ring is over, or the call it became has
      // ended. Reported rather than requested, so it does not come back as the
      // learner pressing End.
      if let uuid = (args["uuid"] as? String).flatMap(UUID.init) {
        calls[uuid] = nil
        answered.remove(uuid)
        provider.reportCall(with: uuid, endedAt: Date(), reason: Self.reason(args["reason"]))
      }
      result(nil)
    case "update":
      if let uuid = (args["uuid"] as? String).flatMap(UUID.init) {
        let update = CXCallUpdate()
        update.hasVideo = args["video"] as? Bool ?? false
        provider.reportCall(with: uuid, updated: update)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func reason(_ value: Any?) -> CXCallEndedReason {
    switch value as? String {
    case "unanswered": return .unanswered
    case "answeredElsewhere": return .answeredElsewhere
    case "declinedElsewhere": return .declinedElsewhere
    case "failed": return .failed
    default: return .remoteEnded
    }
  }

  private func send(_ method: String, _ info: [String: Any]) {
    if listening {
      channel.invokeMethod(method, arguments: info)
    } else {
      pending.append((method, info))
    }
  }

  // MARK: PushKit

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate credentials: PKPushCredentials,
    for type: PKPushType
  ) {
    // Base64, which is what Sygnal expects a pushkey to be.
    let token = credentials.token.base64EncodedString()
    voipToken = token
    send("token", ["token": token])
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    voipToken = nil
    send("token", [:])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    let data = payload.dictionaryPayload
    let alert = (data["aps"] as? [String: Any])?["alert"] as? [String: Any]
    let caller = (alert?["loc-args"] as? [String])?.first ?? ""
    let eventId = data["event_id"] as? String ?? ""
    let info: [String: Any] = [
      "roomId": data["room_id"] as? String ?? "",
      "eventId": eventId,
      // Set per account on its VoIP pusher, because every account on this
      // phone shares the one VoIP token.
      "account": data["pangea_account"] as? String ?? "",
      "caller": caller,
    ]
    // The same ring pushed twice stays one call on the screen.
    let uuid = calls.first { $0.value["eventId"] as? String == eventId }?.key ?? UUID()
    var withId = info
    withId["uuid"] = uuid.uuidString
    calls[uuid] = withId

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: info["roomId"] as? String ?? "")
    update.localizedCallerName = caller.isEmpty ? nil : caller
    // Corrected by the app once it has read the ring.
    update.hasVideo = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error {
        // Do Not Disturb, a blocked caller, or the same call reported twice.
        // There is nothing on the screen for the app to watch.
        NSLog("PangeaCallScreen: incoming call not shown: \(error)")
        if (error as NSError).code != CXErrorCodeIncomingCallError.callUUIDAlreadyExists.rawValue {
          self?.calls[uuid] = nil
        }
      } else {
        self?.send("incoming", withId)
      }
      completion()
    }
  }

  // MARK: CallKit

  func providerDidReset(_ provider: CXProvider) {
    for (uuid, info) in calls {
      var ended = info
      ended["answered"] = answered.contains(uuid)
      send("end", ended)
    }
    calls.removeAll()
    answered.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let info = calls[action.callUUID] else {
      action.fail()
      return
    }
    answered.insert(action.callUUID)
    // CallKit owns the audio session for this call: WebRTC waits for
    // didActivate below instead of starting the microphone itself, which is
    // what leaves an answered CallKit call with no audio.
    RTCAudioSession.sharedInstance().useManualAudio = true
    send("answer", info)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let info = calls.removeValue(forKey: action.callUUID) else {
      action.fulfill()
      return
    }
    var ended = info
    ended["answered"] = answered.remove(action.callUUID) != nil
    send("end", ended)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    if let info = calls[action.callUUID] {
      var muted = info
      muted["muted"] = action.isMuted
      send("mute", muted)
    }
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    let rtc = RTCAudioSession.sharedInstance()
    rtc.audioSessionDidActivate(audioSession)
    rtc.isAudioEnabled = true
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    let rtc = RTCAudioSession.sharedInstance()
    rtc.audioSessionDidDeactivate(audioSession)
    rtc.isAudioEnabled = false
    // Calls placed from inside the app manage their own audio again.
    rtc.useManualAudio = false
  }
}
