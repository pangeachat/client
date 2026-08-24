import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

/// What the fake engine does when asked to `speak`.
enum FakeSpeakBehavior {
  /// A real engine on a good day: reports a start, then a completion, and the
  /// speak future resolves with the completion — the order every platform
  /// delivers.
  startAndComplete,

  /// The utterance is accepted, starts, and then never ends on its own — it
  /// stays in flight until something stops it. What a word being spoken looks
  /// like from Dart until the next tap cuts it off.
  startAndHang,

  /// The engine reports an error before any start, and the speak future never
  /// resolves. What the web plugin does on `not-allowed` /
  /// `synthesis-failed`: its `onError` nulls the completer without completing
  /// it.
  errorBeforeStart,

  /// Nothing at all: no start, no end, no error, and the speak future never
  /// resolves. What the web plugin does when its own state is stuck on a
  /// previous utterance — its `_speak` silently no-ops.
  silentHang,

  /// The speak future resolves without the engine ever having reported a
  /// start. What a stale `end` event from the previous utterance does to the
  /// current one's completer on browsers that fire `end` on cancel.
  returnWithoutStart,
}

/// A scripted stand-in for the `flutter_tts` platform side.
///
/// Answers the method channel the way the real plugin does — `getVoices`,
/// `speak`, `stop`, and the rest — AND drives the plugin's callbacks
/// (`speak.onStart`, `speak.onComplete`, `speak.onCancel`, `speak.onError`)
/// back into Dart, which is what the controller now settles a device utterance
/// on. A mock that only returned from `speak` would pass for an engine that
/// never spoke.
class FakeTtsEngine {
  FakeTtsEngine({
    this.voices = const [
      {'name': 'Paulina', 'locale': 'es-ES', 'quality': 'enhanced'},
    ],
    this.onSpeak = FakeSpeakBehavior.startAndComplete,
    this.errorMessage = 'not-allowed',
    this.stopFiresCancel = true,
  });

  static const MethodChannel channel = MethodChannel('flutter_tts');
  static const StandardMethodCodec _codec = StandardMethodCodec();

  List<Map<String, String>> voices;
  FakeSpeakBehavior onSpeak;

  /// The message sent with `speak.onError` for [FakeSpeakBehavior.errorBeforeStart].
  String errorMessage;

  /// Whether `stop` on an in-flight utterance makes the engine confirm the
  /// cancel (Chrome: `error interrupted`; iOS: `speak.onCancel`). Real engines
  /// do; turning it off simulates one that never confirms.
  bool stopFiresCancel;

  /// How `stop` confirms a cancel: `'cancel'` sends `speak.onCancel` (native),
  /// `'interrupted'` sends `speak.onError('interrupted')` (Chrome),
  /// `'end'` sends `speak.onComplete` (browsers that fire `end` on cancel).
  String stopConfirmation = 'cancel';

  /// Every method-channel call, in order, plus the callbacks this fake sent
  /// back (`<-speak.onStart` etc.), so a test can assert on ordering.
  final List<String> log = [];

  /// Text of every `speak` call.
  final List<String> spoken = [];

  /// The speak completer of the utterance currently in flight, if any.
  Completer<dynamic>? _inFlight;
  bool _inFlightStarted = false;

  bool get hasInFlight => _inFlight != null;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  /// Send a plugin callback into Dart, as the platform would.
  Future<void> emit(String method, [dynamic arguments]) async {
    log.add('<-$method${arguments == null ? '' : '($arguments)'}');
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          _codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
  }

  /// Finish the in-flight utterance as a real engine would at end of speech.
  Future<void> completeInFlight() async {
    final c = _inFlight;
    if (c == null) return;
    _inFlight = null;
    await emit('speak.onComplete');
    if (!c.isCompleted) c.complete(1);
  }

  Future<dynamic> _handle(MethodCall call) async {
    log.add(call.method);
    switch (call.method) {
      case 'getVoices':
        return voices;
      case 'speak':
        spoken.add('${call.arguments}');
        return _speak();
      case 'stop':
        await _stop();
        return 1;
      case 'getSpeechRateValidRange':
        return {'min': 0.0, 'normal': 0.5, 'max': 1.0, 'platform': 'ios'};
      default:
        return 1;
    }
  }

  Future<dynamic> _speak() async {
    final completer = Completer<dynamic>();
    _inFlight = completer;
    _inFlightStarted = false;
    switch (onSpeak) {
      case FakeSpeakBehavior.startAndComplete:
        // The callbacks are dispatched asynchronously, as they are on every
        // platform, so the controller's `speak` await is already pending
        // when they land.
        unawaited(() async {
          await Future<void>.delayed(Duration.zero);
          if (!identical(_inFlight, completer)) return;
          _inFlightStarted = true;
          await emit('speak.onStart');
          await Future<void>.delayed(Duration.zero);
          if (!identical(_inFlight, completer)) return;
          await completeInFlight();
        }());
        return completer.future;
      case FakeSpeakBehavior.startAndHang:
        unawaited(() async {
          await Future<void>.delayed(Duration.zero);
          if (!identical(_inFlight, completer)) return;
          _inFlightStarted = true;
          await emit('speak.onStart');
        }());
        return completer.future;
      case FakeSpeakBehavior.errorBeforeStart:
        unawaited(() async {
          await Future<void>.delayed(Duration.zero);
          if (!identical(_inFlight, completer)) return;
          _inFlight = null;
          await emit('speak.onError', errorMessage);
          // The web plugin nulls its completer here without completing it.
        }());
        return completer.future;
      case FakeSpeakBehavior.silentHang:
        return completer.future;
      case FakeSpeakBehavior.returnWithoutStart:
        _inFlight = null;
        return 1;
    }
  }

  Future<void> _stop() async {
    final c = _inFlight;
    if (c == null || !stopFiresCancel) return;
    _inFlight = null;
    // Asynchronous, like the browser's and the OS's confirmation.
    unawaited(() async {
      await Future<void>.delayed(Duration.zero);
      switch (stopConfirmation) {
        case 'interrupted':
          // Chrome: an error, `interrupted` after start / `canceled` before.
          await emit(
            'speak.onError',
            _inFlightStarted ? 'interrupted' : 'canceled',
          );
          // And the web plugin nulls its completer without completing it.
          break;
        case 'end':
          await emit('speak.onComplete');
          if (!c.isCompleted) c.complete(1);
          break;
        default:
          // iOS: `didCancel` → speak.onCancel; the pending result is dropped.
          // Android: the pending result resolves 0, then onStop → onCancel.
          await emit('speak.onCancel');
      }
    }());
  }
}
