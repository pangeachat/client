import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';

/// A [SttAudioCapture] test double: never touches a real mic. [pushFrame]
/// invokes the tee callback the session registered, so the dual-sink can be
/// asserted deterministically.
class _FakeCapture implements SttAudioCaptureApi {
  _FakeCapture({
    this.permission = true,
    this.startResult = true,
    this.permissionGate,
    this.startGate,
  });

  bool permission;
  bool startResult;

  /// Optional gates so a test can hold `hasPermission()` / `start()` pending and
  /// interpose a teardown mid-flight (cancellation-safety tests).
  final Completer<bool>? permissionGate;
  final Completer<void>? startGate;

  void Function(Uint8List)? _onFrame;
  void Function(Object)? _onError;
  bool started = false;
  bool stopped = false;
  bool disposed = false;
  int stopCount = 0;
  int disposeCount = 0;

  /// Models the underlying mic STREAM: `start()` (once it completes) makes it
  /// active; `stop()` deactivates it. A stop that races an in-flight start (the
  /// leak this guards) leaves it active unless stop is called AFTER start
  /// finishes — exactly what the session's deferred capture disposal does.
  bool isStreamActive = false;

  void pushFrame(Uint8List frame) => _onFrame?.call(frame);

  /// Simulate a runtime mic-stream error (what `record`'s stream would deliver
  /// to the listener's onError).
  void triggerError(Object error) => _onError?.call(error);

  @override
  Future<bool> hasPermission() async {
    if (permissionGate != null) return permissionGate!.future;
    return permission;
  }

  @override
  Future<bool> start(
    void Function(Uint8List frame) onFrame, {
    void Function(Object error)? onError,
  }) async {
    if (!permission) return false;
    _onFrame = onFrame;
    _onError = onError;
    if (startGate != null) await startGate!.future;
    started = startResult;
    if (startResult) isStreamActive = true;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCount++;
    isStreamActive = false;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    disposed = true;
    await stop();
  }
}

class _FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> added = <dynamic>[];
  bool closed = false;
  int closeCount = 0;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) => added.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    closeCount++;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  _FakeWebSocketChannel({this.failReady = false});

  /// When true, `ready` errors — models a socket that never opens (a connect /
  /// handshake failure or an immediate deny). The error future is created
  /// LAZILY inside the getter so `connect`'s `.catchError` attaches in the same
  /// turn (no spurious unhandled-error). Defaults to open.
  final bool failReady;

  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  List<dynamic> get sent => _sink.added;
  bool get isClosed => _sink.closed;
  int get closeCount => _sink.closeCount;

  void emit(dynamic message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  void emitError(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }

  /// Close the inbound stream — models Deepgram closing the socket after it has
  /// flushed all trailing finals (the relay proxies the close). The repo maps
  /// onDone -> SttStreamState.closed, which is what settles the finalizing drain.
  void emitClose() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready {
    if (failReady) {
      return Future<void>.error(Exception('1008 policy violation'));
    }
    // Model a compliant relay (B3): once the socket handshake completes, the
    // relay sends its wire-2 `ready` frame, which is what makes the repo emit
    // `open`. Scheduled so the repo's inbound listener is subscribed first.
    scheduleMicrotask(
      () => emit(jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2})),
    );
    return Future<void>.value();
  }

  @override
  String? get protocol => null;
  @override
  int? get closeCode => _sink.closed ? 1000 : null;
  @override
  String? get closeReason => null;
}

/// A repo whose socket handshake completes but the relay closes (1013 wire
/// cutoff / gate reject) BEFORE any `ready` frame — so it emits connecting then
/// closed, and NEVER `open`. Proves the CLIENT batches (start()==false), not
/// merely that the server closed (B3).
class _FakeRepoNoReadyThenClose extends SttStreamRepo {
  _FakeRepoNoReadyThenClose()
    : super(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
      );

  final StreamController<SttStreamState> _stateCtrl =
      StreamController<SttStreamState>.broadcast();
  final StreamController<SttPartial> _partialCtrl =
      StreamController<SttPartial>.broadcast();

  @override
  Stream<SttStreamState> get state => _stateCtrl.stream;
  @override
  Stream<SttPartial> get partials => _partialCtrl.stream;

  @override
  void connect() {
    scheduleMicrotask(() {
      if (_stateCtrl.isClosed) return;
      _stateCtrl.add(SttStreamState.connecting);
      _stateCtrl.add(SttStreamState.closed);
    });
  }

  @override
  void sendAudio(Uint8List pcm) {}
  @override
  void stop() {}
  @override
  Future<void> close() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
  }
}

/// A fully controllable repo double for the post-`ready` degrade tests: emit
/// state transitions on demand and set the server-selected provider directly.
/// Overrides connect/sendAudio/stop/close so no real socket opens.
class _FakeRepo extends SttStreamRepo {
  _FakeRepo()
    : super(
        wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
        accessToken: 'TOKEN',
      );

  final StreamController<SttStreamState> _stateCtrl =
      StreamController<SttStreamState>.broadcast();
  final StreamController<SttPartial> _partialCtrl =
      StreamController<SttPartial>.broadcast();

  @override
  Stream<SttStreamState> get state => _stateCtrl.stream;
  @override
  Stream<SttPartial> get partials => _partialCtrl.stream;

  void emitState(SttStreamState s) {
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  String? _selectedProvider;
  @override
  String? get selectedProvider => _selectedProvider;
  set selectedProvider(String? id) => _selectedProvider = id;

  bool _degraded = false;
  @override
  bool get degraded => _degraded;
  set degraded(bool value) => _degraded = value;

  String? _primaryProvider;
  @override
  String? get primaryProvider => _primaryProvider;
  set primaryProvider(String? id) => _primaryProvider = id;

  @override
  void connect() {}
  @override
  void sendAudio(Uint8List pcm) {}
  @override
  void stop() {}
  @override
  Future<void> close() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_partialCtrl.isClosed) await _partialCtrl.close();
  }
}

/// In-memory temp writer: no real disk I/O, so the degrade tests run fast and
/// deterministically (the M12 timing assertion needs no real file system).
Future<String> _memWriter(Uint8List wav) async =>
    '/tmp/stt_degrade_${wav.length}.wav';

Uint8List _pcm(int bytes) => Uint8List(bytes);

StreamingSttSession _degradeSession(_FakeRepo repo) => StreamingSttSession(
  capture: _FakeCapture()..permission = true,
  repo: repo,
  tempFileWriter: _memWriter,
  // Long watchdog so a started-but-idle degrade case never trips it.
  frameWatchdogTimeout: const Duration(seconds: 30),
);

void main() {
  late _FakeWebSocketChannel channel;

  SttStreamRepo buildRepo() {
    channel = _FakeWebSocketChannel();
    return SttStreamRepo(
      wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
      accessToken: 'TOKEN',
      connector: (uri, {protocols}) => channel,
    );
  }

  /// A repo whose socket NEVER opens (the handshake future errors), modelling a
  /// denied/failed connect (auth/entitlement/language 1008 or transport error).
  SttStreamRepo buildDeniedRepo() {
    channel = _FakeWebSocketChannel(failReady: true);
    return SttStreamRepo(
      wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
      accessToken: 'TOKEN',
      connector: (uri, {protocols}) => channel,
    );
  }

  /// A temp-file writer backed by dart:io only (no path_provider plugin), so
  /// the synthesized WAV can be read back on disk in a unit test.
  final List<String> writtenPaths = <String>[];
  Future<String> tempWriter(Uint8List wav) async {
    final dir = await Directory.systemTemp.createTemp('stt_session_test');
    final file = File('${dir.path}/voice.wav');
    await file.writeAsBytes(wav);
    writtenPaths.add(file.path);
    return file.path;
  }

  tearDown(() async {
    for (final p in writtenPaths) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    writtenPaths.clear();
  });

  StreamingSttSession buildSession(
    _FakeCapture capture,
    SttStreamRepo repo, {
    Duration maxDuration = const Duration(minutes: 5),
    // Keep the finalizing drain short so tests without a trailing final don't
    // block; the drain test overrides this with a comfortable window.
    Duration finalizeTimeout = const Duration(milliseconds: 40),
    // Long by default so ordinary tests never trip the no-frames watchdog; the
    // watchdog test overrides it to a short window.
    Duration frameWatchdogTimeout = const Duration(seconds: 30),
  }) => StreamingSttSession(
    capture: capture,
    repo: repo,
    tempFileWriter: tempWriter,
    maxDuration: maxDuration,
    finalizeTimeout: finalizeTimeout,
    frameWatchdogTimeout: frameWatchdogTimeout,
    sampleRate: 16000,
  );

  group('start / permission ladder (D10)', () {
    test(
      'permission denied -> start returns false (caller falls to batch)',
      () async {
        final capture = _FakeCapture(permission: false);
        final session = buildSession(capture, buildRepo());

        final ok = await session.start();

        expect(ok, isFalse);
      },
    );

    test('capture start failure -> start returns false, no crash', () async {
      final capture = _FakeCapture(startResult: false);
      final session = buildSession(capture, buildRepo());

      final ok = await session.start();

      expect(ok, isFalse);
    });

    test('happy path -> start returns true and capture is running', () async {
      final capture = _FakeCapture();
      final session = buildSession(capture, buildRepo());

      final ok = await session.start();

      expect(ok, isTrue);
      expect(capture.started, isTrue);
    });

    test(
      'pre-open connect DENY -> start returns false and the mic never starts (fix #1)',
      () async {
        final capture = _FakeCapture();
        final repo = buildDeniedRepo();
        final session = buildSession(capture, repo);

        final ok = await session.start();

        // fix #1 teeth: a denied/failed socket must NOT leave the user in the
        // streaming UI. start() returns false (recorder takes the batch path)
        // and the mic is never started behind a dead socket.
        // (Reverting the await-open gate => the mic starts + start() returns
        // true => RED.)
        expect(ok, isFalse);
        expect(
          capture.started,
          isFalse,
          reason: 'mic must not start when the socket is denied',
        );
      },
    );

    test(
      'server closes before ready (wire=1/malformed cutoff) => start() false => batch (B3)',
      () async {
        // The socket handshake reaches the relay, but it closes 1013 BEFORE any
        // ready frame (exactly what the relay does for wire=1/malformed/gate
        // reject). `open` never fires -> _awaitOpen() false -> start() false ->
        // the caller runs today's batch record path (D10).
        final session = StreamingSttSession(
          capture: _FakeCapture()..permission = true,
          repo: _FakeRepoNoReadyThenClose(),
          tempFileWriter: tempWriter,
          connectTimeout: const Duration(milliseconds: 200),
        );

        final ok = await session.start();

        expect(ok, isFalse);
      },
    );
  });

  group('dual sink tee (D5a: one mic, two sinks)', () {
    test(
      'each captured PCM frame goes to BOTH sendAudio AND the buffer',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        await session.start();

        final f1 = Uint8List.fromList(<int>[1, 2, 3, 4]);
        final f2 = Uint8List.fromList(<int>[5, 6, 7, 8]);
        capture.pushFrame(f1);
        capture.pushFrame(f2);

        // Sink (a): sent to the relay as binary frames.
        final binaryFrames = channel.sent.whereType<Uint8List>().toList(
          growable: false,
        );
        expect(binaryFrames, hasLength(2));
        expect(binaryFrames[0], equals(f1));
        expect(binaryFrames[1], equals(f2));

        // Sink (b): accumulated in the in-memory PCM buffer.
        expect(session.pcmByteLength, f1.length + f2.length);
      },
    );

    test(
      'a captured frame updates the RMS-derived amplitude timeline',
      () async {
        final capture = _FakeCapture();
        final session = buildSession(capture, buildRepo());
        await session.start();

        // A loud-ish frame (non-zero PCM16 samples).
        capture.pushFrame(Uint8List.fromList(<int>[0, 64, 0, 64, 0, 64]));

        expect(session.amplitudeTimeline, isNotEmpty);
        expect(session.amplitudeTimeline.last, greaterThanOrEqualTo(1));
      },
    );
  });

  group('partial accumulation (replace-in-place, final settles)', () {
    test('partials replace in place; a final settles the transcript', () async {
      final capture = _FakeCapture();
      final repo = buildRepo();
      final session = buildSession(capture, repo);
      await session.start();

      channel.emit(_partial('hel'));
      await pumpEventQueue();
      expect(session.liveTranscript, 'hel');

      channel.emit(_partial('hello wor'));
      await pumpEventQueue();
      // Replace-in-place: NOT concatenated to 'helhello wor'.
      expect(session.liveTranscript, 'hello wor');
      expect(session.finalTranscript, isEmpty);

      channel.emit(_final('hello world'));
      await pumpEventQueue();
      expect(session.liveTranscript, 'hello world');
      expect(session.finalTranscript, 'hello world');
    });

    test(
      'MULTI-SEGMENT: successive segment_final/stream_final chunks (one per '
      'pause/endpoint) ACCUMULATE — never overwrite — in live + final transcript',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        await session.start();

        // Segment 1: interim -> committed final chunk (with words).
        channel.emit(_partial('hello i'));
        await pumpEventQueue();
        expect(session.liveTranscript, 'hello i');
        channel.emit(_finalWithWords('hello I would', ['hello', 'I', 'would']));
        await pumpEventQueue();
        expect(session.finalTranscript, 'hello I would');

        // Segment 2 (after a pause): a NEW interim starts fresh from Deepgram, but
        // the display must KEEP segment 1 and append.
        channel.emit(_partial('like to'));
        await pumpEventQueue();
        // Teeth: pre-fix this replaced -> 'like to' (segment 1 lost). Must keep it.
        expect(session.liveTranscript, 'hello I would like to');

        channel.emit(
          _finalWithWords('like to practice English', [
            'like',
            'to',
            'practice',
            'English',
          ]),
        );
        await pumpEventQueue();
        expect(
          session.liveTranscript,
          'hello I would like to practice English',
        );
        // Teeth: pre-fix finalTranscript was only the LAST chunk -> a truncated
        // message would be SENT. It must be the full accumulated transcript.
        expect(
          session.finalTranscript,
          'hello I would like to practice English',
        );
        // WORD TIMINGS accumulate across BOTH segments, in order (D9 / D8). Teeth:
        // pre-fix _finalWords was replaced by the last chunk -> only 4 words.
        expect(session.finalWords.map((w) => w.word).toList(), <String>[
          'hello',
          'I',
          'would',
          'like',
          'to',
          'practice',
          'English',
        ]);
      },
    );
  });

  group('failure fallback (D10) — mid-stream socket terminal', () {
    test(
      'error after a result degrades the complete retained WAV to batch',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        final degradedReady = Completer<StreamingSttResult>();
        StreamingSttResult? degraded;
        session.onStreamDegradeToBatch = (result) {
          degraded = result;
          degradedReady.complete(result);
        };
        await session.start();

        capture.pushFrame(Uint8List.fromList(<int>[1, 2, 3, 4]));
        channel.emit(_partial('mid'));
        await pumpEventQueue();
        channel.emitError(Exception('socket blew up'));
        await degradedReady.future;

        expect(degraded, isNotNull);
        expect(degraded!.transcript, 'mid');
        expect(capture.disposed, isTrue);
      },
    );
  });

  group('teardown on cancel (D6)', () {
    test('capture stopped, socket closed, buffer + temp discarded', () async {
      final capture = _FakeCapture();
      final repo = buildRepo();
      final session = buildSession(capture, repo);
      await session.start();
      capture.pushFrame(Uint8List.fromList(<int>[1, 2, 3, 4]));

      await session.teardown();

      expect(capture.stopped, isTrue);
      expect(channel.isClosed, isTrue);
      expect(session.pcmByteLength, 0);
    });

    test(
      'teardown is idempotent: capture disposal / socket.close run once (fix #3)',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        await session.start();

        await session.teardown();
        await session.teardown(); // second call must be a clean no-op

        // (Reverting the `if (_teardownDone) return` guard => the second teardown
        // re-runs capture disposal and repo.close() => counts become 2 => RED.)
        expect(capture.stopCount, 1);
        expect(capture.disposeCount, 1);
        expect(channel.closeCount, 1);
        expect(session.pcmByteLength, 0);
      },
    );
  });

  group('start() cancellation-safety (fix #1, no socket/mic leak)', () {
    test(
      'teardown during permission -> start false, socket NEVER opens',
      () async {
        final permGate = Completer<bool>();
        final capture = _FakeCapture(permissionGate: permGate);
        var connectorCalls = 0;
        final repo = SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN',
          connector: (uri, {protocols}) {
            connectorCalls++;
            return _FakeWebSocketChannel();
          },
        );
        final session = buildSession(capture, repo);

        final startFuture = session.start(); // suspends at hasPermission()
        await pumpEventQueue();
        await session.teardown(); // cancel BEFORE permission resolves
        permGate.complete(true); // permission now resolves true

        expect(await startFuture, isFalse);
        // The post-permission `if (_teardownDone) return` + the repo connect
        // guard mean connect() never opened a socket. (Reverting the check AND
        // the guard => a socket opens on a closed repo => leak => connectorCalls
        // becomes 1 => RED.)
        expect(connectorCalls, 0);
        expect(capture.started, isFalse);
      },
    );

    test(
      'teardown while capture.start() is in flight stops the just-started mic',
      () async {
        final startGate = Completer<void>();
        final capture = _FakeCapture(startGate: startGate);
        final repo = buildRepo();
        final session = buildSession(capture, repo);

        final startFuture = session.start();
        await pumpEventQueue(); // past permission + open; suspended in capture.start
        final teardownFuture = session.teardown(); // races mic start
        await pumpEventQueue();
        startGate.complete(); // capture.start() now completes -> stream active

        await teardownFuture;
        expect(await startFuture, isFalse);
        // No leak: the mic that became active during the race is stopped by the
        // deferred capture disposal. (Reverting that check => isStreamActive
        // stays true => RED.)
        expect(capture.isStreamActive, isFalse);
        expect(capture.disposeCount, 1);
        expect(channel.isClosed, isTrue);
      },
    );
  });

  group('max-duration cap truncates the crossing frame (D5a, fix #3)', () {
    test(
      'a frame that crosses the cap is truncated: PCM and WS bytes == cap exactly',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        // 100ms @16kHz*2 = 3200-byte cap (NOT a frame multiple, so the second
        // frame genuinely CROSSES rather than landing exactly on the cap).
        final session = buildSession(
          capture,
          repo,
          maxDuration: const Duration(milliseconds: 100),
        );
        var maxHits = 0;
        session.onMaxDuration = () => maxHits++;
        await session.start();

        capture.pushFrame(Uint8List(3000)); // just under the 3200-byte cap
        capture.pushFrame(Uint8List(1000)); // would push to 4000 -> crosses
        await pumpEventQueue();

        int wsBytes() => channel.sent.whereType<Uint8List>().fold<int>(
          0,
          (sum, f) => sum + f.length,
        );

        // fix #3 teeth: the crossing frame is TRUNCATED to the remaining 200
        // bytes — neither the retained PCM nor the WS-sent bytes overrun.
        // (Reverting to send/buffer the whole frame => 4000, not 3200 => RED.)
        expect(session.pcmByteLength, 3200);
        expect(wsBytes(), 3200);
        expect(session.isMaxDurationReached, isTrue);
        expect(maxHits, greaterThanOrEqualTo(1));
        expect(capture.stopped, isTrue);

        // Frames after the cap are dropped entirely (no send, no buffer growth).
        capture.pushFrame(Uint8List(1000));
        expect(session.pcmByteLength, 3200);
        expect(wsBytes(), 3200);
      },
    );
  });

  group('finalizing drain settles the trailing final (fix #3)', () {
    test(
      'a final arriving shortly after stop IS reflected in the transcript',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(
          capture,
          repo,
          // Comfortable window so the post-stop final settles before timeout.
          finalizeTimeout: const Duration(seconds: 5),
        );
        await session.start();

        // Only a PARTIAL before stop: without the drain, the returned transcript
        // would fall back to this partial, never the post-stop final.
        channel.emit(_partial('trailing fin'));
        await pumpEventQueue();

        final future = session.stopAndSynthesize();
        // Let _finalize send stop and register the drain listeners.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        channel.emit(_final('trailing final'));
        // Deepgram then closes the socket -> the drain settles on close.
        channel.emitClose();

        final result = await future;
        expect(result, isNotNull);
        expect(result!.transcript, 'trailing final');
      },
    );

    test(
      'MULTIPLE trailing finals after stop ALL accumulate — the drain waits for '
      'the socket CLOSE, not the first final, so no segment is dropped/truncated',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(
          capture,
          repo,
          finalizeTimeout: const Duration(seconds: 5),
        );
        await session.start();

        final future = session.stopAndSynthesize();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // First trailing final after stop. Pre-fix this SETTLES the drain, so
        // _cancelSubs then runs and the subscription is torn down.
        channel.emit(_final('hello I would'));
        await pumpEventQueue();
        // A SECOND trailing final of the same utterance arrives BEFORE close.
        // Pre-fix the sub is already gone -> this is DROPPED. Post-fix the drain
        // is still waiting for close, so it accumulates.
        channel.emit(_final('like to practice English'));
        channel.emitClose();

        final result = await future;
        expect(result, isNotNull);
        // Teeth: pre-fix (settle on first final) -> only 'hello I would'.
        expect(result!.transcript, 'hello I would like to practice English');
      },
    );
  });

  // The SURFACED-error path: fires only IF `record` ever forwards a mic-stream
  // error to onError (rare — see stt_audio_capture.dart). The genuine D10
  // detector is the no-frames watchdog below.
  group('capture onError (surfaced) -> teardown + fatal', () {
    test(
      'a forwarded mic error tears down and fires onFatalError, no throw',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        var fatal = 0;
        session.onFatalError = () => fatal++;
        await session.start();

        capture.triggerError(Exception('mic died'));
        await pumpEventQueue();

        expect(fatal, 1);
        expect(session.hasError, isTrue);
        // Teardown ran: mic stopped and socket closed (no dangling capture/WS).
        expect(capture.stopped, isTrue);
        expect(channel.isClosed, isTrue);
      },
    );
  });

  group(
    'no-frames watchdog is the real D10 capture-failure detector (fix #2)',
    () {
      test(
        'mic starts but delivers NO frames -> watchdog -> teardown + batch fallback',
        () async {
          final capture =
              _FakeCapture(); // start() succeeds, never pushes a frame
          final repo = buildRepo();
          final session = buildSession(
            capture,
            repo,
            frameWatchdogTimeout: const Duration(milliseconds: 50),
          );
          var fatal = 0;
          session.onFatalError = () => fatal++;

          expect(await session.start(), isTrue); // socket opens, mic "started"

          // No PCM ever arrives. Wait past the watchdog window. (Reverting the
          // watchdog => fatal stays 0 / capture never stops => RED.)
          await Future<void>.delayed(const Duration(milliseconds: 130));
          await pumpEventQueue();

          expect(fatal, 1);
          expect(session.hasError, isTrue);
          expect(capture.stopped, isTrue);
          expect(channel.isClosed, isTrue);
        },
      );

      test('frames keep arriving -> the watchdog does NOT fire', () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(
          capture,
          repo,
          frameWatchdogTimeout: const Duration(milliseconds: 60),
        );
        var fatal = 0;
        session.onFatalError = () => fatal++;
        await session.start();

        // Push a frame every ~20ms across ~140ms — each resets the watchdog, so
        // it must never fire while the mic is healthy.
        for (var i = 0; i < 7; i++) {
          capture.pushFrame(Uint8List.fromList(<int>[0, 1, 2, 3]));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(fatal, 0);
        expect(session.hasError, isFalse);
        expect(capture.stopped, isFalse);

        await session.teardown(); // cancel the watchdog before the test ends
      });
    },
  );

  group('stopAndSynthesize (D5a retained WAV)', () {
    test(
      'synthesizes a WAV temp file and returns the settled transcript',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(capture, repo);
        await session.start();

        capture.pushFrame(
          Uint8List.fromList(<int>[10, 0, 20, 0, 30, 0, 40, 0]),
        );
        channel.emit(_final('the settled final'));
        await pumpEventQueue();

        final result = await session.stopAndSynthesize();

        expect(result, isNotNull);
        expect(result!.transcript, 'the settled final');
        expect(capture.stopped, isTrue);
        expect(capture.disposeCount, 1);

        final file = File(result.wavPath);
        expect(await file.exists(), isTrue);
        final bytes = await file.readAsBytes();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        // 44-byte header + 8 bytes of pumped PCM.
        expect(bytes.length, 44 + 8);

        await session.teardown();
        expect(capture.disposeCount, 1);
      },
    );

    test(
      'a teardown() racing the finalizing drain -> returns null and leaks NO '
      'temp WAV (post-finalize _teardownDone re-check)',
      () async {
        final capture = _FakeCapture();
        final repo = buildRepo();
        final session = buildSession(
          capture,
          repo,
          // Wide window so the drain is still in flight when teardown lands.
          finalizeTimeout: const Duration(seconds: 5),
        );
        await session.start();
        capture.pushFrame(
          Uint8List.fromList(<int>[10, 0, 20, 0, 30, 0, 40, 0]),
        );
        await pumpEventQueue();

        final future = session.stopAndSynthesize();
        // Let _finalize begin its drain, then CANCEL via teardown mid-drain
        // (repo.close settles the drain early, so `future` resolves).
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await session.teardown();

        final result = await future;
        // Teeth: without the post-finalize `if (_teardownDone) return null`,
        // this synthesizes an (empty) WAV -> non-null result + a leaked temp
        // file that teardown (ran with _tempPath == null) can never delete.
        expect(result, isNull);
        expect(writtenPaths, isEmpty);
      },
    );
  });

  group('post-ready terminal degrades to batch (B4/H8/M12/H9)', () {
    test(
      'POST-ready, mic started + PCM buffered, terminal BEFORE first result => degrade w/ retained PCM',
      () async {
        final repo = _FakeRepo();
        final session = _degradeSession(repo);
        StreamingSttResult? degraded;
        session.onStreamDegradeToBatch = (r) => degraded = r;

        final startFuture = session.start(); // start() awaits ready/open
        await pumpEventQueue(); // let start() subscribe before the state emit
        repo.emitState(SttStreamState.open); // <- `ready` (wire:2) arrived
        expect(await startFuture, isTrue); // mic started

        session.debugOnFrame(_pcm(3200)); // ~100ms audio buffered (tee -> _pcm)
        repo.emitState(
          SttStreamState.error,
        ); // deferred connect/guard/chain failed, pre-result
        await pumpEventQueue();

        expect(
          degraded,
          isNotNull,
        ); // degrade fired (not onFatalError/_hasError)
        expect(degraded!.wavPath, isNotEmpty); // retained PCM synthesized
      },
    );

    test(
      'PRE-ready terminal => start()==false, NO synth, NO degrade callback (normal batch recorder, H8)',
      () async {
        final repo = _FakeRepo();
        final session = _degradeSession(repo);
        var degradeFired = false;
        session.onStreamDegradeToBatch = (_) => degradeFired = true;

        final startFuture = session.start();
        await pumpEventQueue();
        repo.emitState(
          SttStreamState.closed,
        ); // server closes BEFORE any `ready` (wire cutoff / gate)
        expect(
          await startFuture,
          isFalse,
        ); // -> caller runs today's batch RECORDER
        await pumpEventQueue();

        expect(degradeFired, isFalse); // degrade never fires pre-ready
        expect(
          session.debugSynthesizeCalled,
          isFalse,
        ); // NO synth on empty audio
      },
    );

    test(
      'POST-ready but ZERO PCM buffered, terminal => NO degrade (nothing to save)',
      () async {
        final repo = _FakeRepo();
        final session = _degradeSession(repo);
        var degradeFired = false;
        session.onStreamDegradeToBatch = (_) => degradeFired = true;

        final startFuture = session.start();
        await pumpEventQueue();
        repo.emitState(SttStreamState.open);
        await startFuture; // mic started, but no frame pushed
        repo.emitState(SttStreamState.error);
        await pumpEventQueue();

        expect(degradeFired, isFalse); // _pcm.length==0 -> no empty-WAV degrade
        // Teeth for the `_pcm.length > 0` guard: the no-drain synth sets
        // debugSynthesizeCalled BEFORE its empty-PCM null return, so dropping the
        // guard flips this true (degradeFired alone can't catch it — an empty
        // synth returns null and never fires the callback).
        expect(session.debugSynthesizeCalled, isFalse);
        await session.teardown(); // cancel the idle watchdog
      },
    );

    test(
      'PRE-ready terminal even WITH buffered PCM => NO synth, NO degrade (H8: _openedAndMicStarted)',
      () async {
        final repo = _FakeRepo();
        final session = _degradeSession(repo);
        var degradeFired = false;
        session.onStreamDegradeToBatch = (_) => degradeFired = true;

        final startFuture = session.start();
        await pumpEventQueue();
        // Buffer audio during the PRE-`ready` window (via the seam) so ONLY the
        // _openedAndMicStarted gate — not _pcm.length>0 — keeps this out of the
        // degrade branch. This isolates H8: dropping _openedAndMicStarted would
        // degrade + synth a WAV before the relay ever admitted us.
        session.debugOnFrame(_pcm(3200));
        repo.emitState(SttStreamState.closed); // server closes BEFORE any ready
        expect(await startFuture, isFalse);
        await pumpEventQueue();

        expect(degradeFired, isFalse);
        expect(session.debugSynthesizeCalled, isFalse);
      },
    );

    test(
      'unexpected error/close before/after results always degrades retained WAV',
      () async {
        for (final terminal in <SttStreamState>[
          SttStreamState.error,
          SttStreamState.closed,
        ]) {
          for (final afterResult in <bool>[false, true]) {
            final repo = _FakeRepo();
            final capture = _FakeCapture()..permission = true;
            var writes = 0;
            final session = StreamingSttSession(
              capture: capture,
              repo: repo,
              tempFileWriter: (_) async => '/tmp/recovered_${++writes}.wav',
              frameWatchdogTimeout: const Duration(seconds: 30),
            );
            StreamingSttResult? degraded;
            session.onStreamDegradeToBatch = (r) => degraded = r;

            final startFuture = session.start();
            await pumpEventQueue();
            repo.emitState(SttStreamState.open);
            expect(await startFuture, isTrue);
            session.debugOnFrame(_pcm(3200));
            if (afterResult) {
              session.debugApplyPartial(
                const SttPartial(
                  transcript: 'hola',
                  words: <SttWord>[],
                  isFinal: true,
                  speechFinal: true,
                ),
              );
            }

            repo.emitState(terminal);
            await pumpEventQueue();

            expect(
              degraded,
              isNotNull,
              reason: '$terminal afterResult=$afterResult',
            );
            expect(degraded!.transcript, afterResult ? 'hola' : '');
            expect(writes, 1);
            expect(capture.disposeCount, 1);
            await session.teardown();
            expect(capture.disposeCount, 1);
          }
        }
      },
    );

    test(
      'terminal recovery racing stop shares one synthesis and one artifact',
      () async {
        final repo = _FakeRepo();
        final capture = _FakeCapture()..permission = true;
        final writeGate = Completer<void>();
        var writes = 0;
        final session = StreamingSttSession(
          capture: capture,
          repo: repo,
          tempFileWriter: (_) async {
            writes++;
            await writeGate.future;
            return '/tmp/recovered.wav';
          },
          finalizeTimeout: const Duration(milliseconds: 1),
          frameWatchdogTimeout: const Duration(seconds: 30),
        );
        StreamingSttResult? degraded;
        session.onStreamDegradeToBatch = (r) => degraded = r;

        final startFuture = session.start();
        await pumpEventQueue();
        repo.emitState(SttStreamState.open);
        expect(await startFuture, isTrue);
        session.debugOnFrame(_pcm(3200));

        repo.emitState(SttStreamState.error);
        await pumpEventQueue();
        final concurrentStop = session.stopAndSynthesize();
        writeGate.complete();
        final stopped = await concurrentStop;
        await pumpEventQueue();

        expect(writes, 1);
        expect(stopped, same(degraded));
        expect(capture.disposeCount, 1);
      },
    );

    test(
      'teardown racing terminal write suppresses callback and deletes artifact',
      () async {
        final repo = _FakeRepo();
        final capture = _FakeCapture()..permission = true;
        final writeStarted = Completer<void>();
        final writeGate = Completer<void>();
        late String retainedPath;
        final session = StreamingSttSession(
          capture: capture,
          repo: repo,
          tempFileWriter: (wav) async {
            writeStarted.complete();
            await writeGate.future;
            final dir = await Directory.systemTemp.createTemp(
              'stt_degrade_cancel',
            );
            final file = File('${dir.path}/retained.wav');
            await file.writeAsBytes(wav);
            retainedPath = file.path;
            writtenPaths.add(file.path);
            return file.path;
          },
          frameWatchdogTimeout: const Duration(seconds: 30),
        );
        StreamingSttResult? degraded;
        session.onStreamDegradeToBatch = (r) => degraded = r;

        final startFuture = session.start();
        await pumpEventQueue();
        repo.emitState(SttStreamState.open);
        expect(await startFuture, isTrue);
        session.debugOnFrame(_pcm(3200));
        repo.emitState(SttStreamState.error);
        await writeStarted.future;

        var teardownCompleted = false;
        final teardownFuture = session.teardown().then(
          (_) => teardownCompleted = true,
        );
        await pumpEventQueue();
        expect(
          teardownCompleted,
          isFalse,
          reason: 'teardown must join the in-flight retained-WAV write',
        );
        writeGate.complete();
        await teardownFuture;
        final recovered = await session.stopAndSynthesize();

        expect(recovered, isNull);
        expect(degraded, isNull);
        expect(await File(retainedPath).exists(), isFalse);
        expect(capture.disposeCount, 1);
      },
    );

    test(
      'terminal degrade fires WITHOUT waiting finalizeTimeout (M12)',
      () async {
        final repo = _FakeRepo();
        // A long finalizeTimeout: if the degrade path waited on
        // _awaitFinalizingDrain (as stopAndSynthesize does), it would block ~30s on
        // an already-dead socket, and a timer-free pumpEventQueue would leave
        // `degraded` null.
        final session = StreamingSttSession(
          capture: _FakeCapture()..permission = true,
          repo: repo,
          tempFileWriter: _memWriter,
          finalizeTimeout: const Duration(seconds: 30),
          frameWatchdogTimeout: const Duration(seconds: 30),
        );
        StreamingSttResult? degraded;
        session.onStreamDegradeToBatch = (r) => degraded = r;

        final startFuture = session.start();
        await pumpEventQueue();
        repo.emitState(SttStreamState.open);
        await startFuture;

        session.debugOnFrame(_pcm(3200));
        repo.emitState(SttStreamState.error);
        await pumpEventQueue(); // NO real-timer advance

        expect(
          degraded,
          isNotNull,
        ); // degrade already fired — no 30s drain wait
        expect(session.debugSynthesizeCalled, isTrue);
      },
    );

    test(
      'provenance is server-authoritative (H9): routed provider stamped, never deepgram',
      () {
        final repo = _FakeRepo();
        final session = _degradeSession(repo);
        expect(
          session.service,
          'streaming_v2',
        ); // neutral BEFORE the provider is known
        repo.selectedProvider =
            'soniox'; // server's {"type":"provider","id":"soniox"}
        expect(session.service, 'soniox'); // stamps the SERVER's provider
        expect(session.service, isNot('deepgram')); // never the old default
      },
    );

    test('degraded-live status is server-authoritative (H9b): isDegradedLive / '
        'degradedPrimaryProvider delegate to the repo, alongside service', () {
      final repo = _FakeRepo();
      final session = _degradeSession(repo);
      expect(session.isDegradedLive, isFalse); // neutral before any frame
      expect(session.degradedPrimaryProvider, isNull);

      repo.degraded = true;
      repo.primaryProvider = 'deepgram';
      expect(session.isDegradedLive, isTrue);
      expect(session.degradedPrimaryProvider, 'deepgram');
    });
  });

  group(
    'live provider-degrade signal (H9b): runner-up while still streaming',
    () {
      test(
        'a degraded provider frame fires onUpdate promptly (no partial '
        'needed) and stamps isDegradedLive/degradedPrimaryProvider/service',
        () async {
          final capture = _FakeCapture();
          final repo = buildRepo();
          final session = buildSession(capture, repo);
          var updates = 0;
          session.onUpdate = () => updates++;

          expect(await session.start(), isTrue);
          expect(session.isDegradedLive, isFalse);
          updates = 0; // isolate the provider frame's own update(s)

          channel.emit(
            jsonEncode(<String, dynamic>{
              'type': 'provider',
              'id': 'assemblyai',
              'degraded': true,
              'primary': 'deepgram',
            }),
          );
          await pumpEventQueue();

          expect(
            updates,
            greaterThan(0),
            reason:
                'the banner must be able to appear WHILE still '
                'recording, without waiting on the next partial',
          );
          expect(session.isDegradedLive, isTrue);
          expect(session.degradedPrimaryProvider, 'deepgram');
          expect(session.service, 'assemblyai'); // still the ACTUAL server id
          await session.teardown();
        },
      );

      test(
        'a normal (non-degraded) provider frame leaves isDegradedLive false',
        () async {
          final capture = _FakeCapture();
          final repo = buildRepo();
          final session = buildSession(capture, repo);

          expect(await session.start(), isTrue);

          channel.emit(
            jsonEncode(<String, dynamic>{'type': 'provider', 'id': 'deepgram'}),
          );
          await pumpEventQueue();

          expect(session.isDegradedLive, isFalse);
          expect(session.degradedPrimaryProvider, isNull);
          expect(session.service, 'deepgram');
          await session.teardown();
        },
      );
    },
  );
}

String _partial(String text) => jsonEncode(<String, dynamic>{
  'type': 'partial',
  'transcript': text,
  'words': <Map<String, dynamic>>[],
});

String _final(String text) => jsonEncode(<String, dynamic>{
  'type': 'stream_final',
  'transcript': text,
  'words': <Map<String, dynamic>>[],
});

String _finalWithWords(String text, List<String> words) =>
    jsonEncode(<String, dynamic>{
      'type': 'stream_final',
      'transcript': text,
      'words': words
          .map(
            (w) => <String, dynamic>{
              'word': w,
              'start': 0.0,
              'end': 0.1,
              'confidence': 0.9,
            },
          )
          .toList(),
    });
