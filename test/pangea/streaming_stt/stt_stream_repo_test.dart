import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_repo.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';

/// An in-memory [WebSocketSink] that records every frame handed to it and never
/// touches a real socket, so the transport's framing (binary PCM vs JSON
/// control) can be asserted deterministically.
class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink({this.throwOnAdd = false});

  /// Models the socket-close race: `sink.add` throws (e.g. "Cannot add to a
  /// closed sink") AFTER the repo's last `_closed` check but before onError
  /// flips `_closed`.
  final bool throwOnAdd;

  final List<dynamic> added = <dynamic>[];
  bool closed = false;
  int? sentCloseCode;
  String? sentCloseReason;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {
    if (throwOnAdd) throw StateError('Cannot add to a closed sink');
    added.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    sentCloseCode = closeCode;
    sentCloseReason = closeReason;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// A [WebSocketChannel] test double: [emit] pushes an inbound frame to the
/// repo's listener; [sent] exposes what the repo wrote outbound.
class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  _FakeWebSocketChannel({this.protocols, bool throwOnAdd = false})
    : _sink = _FakeWebSocketSink(throwOnAdd: throwOnAdd);

  final Iterable<String>? protocols;
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final _FakeWebSocketSink _sink;

  List<dynamic> get sent => _sink.added;
  bool get isClosed => _sink.closed;

  void emit(dynamic message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  void emitDone() {
    if (!_incoming.isClosed) _incoming.close();
  }

  void emitError(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol =>
      (protocols != null && protocols!.isNotEmpty) ? protocols!.first : null;

  @override
  int? get closeCode => _sink.closed ? (_sink.sentCloseCode ?? 1000) : null;

  @override
  String? get closeReason => _sink.sentCloseReason;
}

void main() {
  late Uri? connectedUri;
  late Iterable<String>? connectedProtocols;
  late _FakeWebSocketChannel channel;
  late int connectorCalls;

  WebSocketChannel connector(Uri uri, {Iterable<String>? protocols}) {
    connectorCalls++;
    connectedUri = uri;
    connectedProtocols = protocols;
    channel = _FakeWebSocketChannel(protocols: protocols);
    return channel;
  }

  setUp(() {
    connectedUri = null;
    connectedProtocols = null;
    connectorCalls = 0;
  });

  SttStreamRepo buildRepo({String lang = 'en'}) => SttStreamRepo(
    wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
    accessToken: 'TOKEN123',
    lang: lang,
    connector: connector,
  );

  /// A connected repo whose fake socket handshake has completed (`channel.ready`
  /// is a resolved future), but the relay has NOT yet sent a `ready` frame — the
  /// exact window B3/M8 gate. Drive `debugHandleInbound`/`debugCloseTransport`
  /// on the returned repo to model the relay's next move.
  SttStreamRepo openRepoWithReadyHandshake() => buildRepo()..connect();

  group('connect', () {
    test(
      'connects to the EXACT D4 uri (with ?lang=en&wire=2) and access_token subprotocol',
      () {
        final repo = buildRepo();
        repo.connect();

        // D4 URL contract: wave-1's relay REQUIRES the ?lang= query (closes 1008
        // for an unsupported language) and the D2a handshake advertises ?wire=.
        expect(
          connectedUri.toString(),
          'wss://api.example/choreo/speech_to_text/stream?lang=en&wire=2',
        );
        expect(connectedUri?.queryParameters['lang'], 'en');
        expect(connectedUri?.queryParameters['wire'], '2');
        expect(connectedProtocols, <String>['access_token.TOKEN123']);
      },
    );

    test('the gated language flows through to the ?lang= query', () {
      buildRepo(lang: 'de').connect();
      expect(connectedUri?.queryParameters['lang'], 'de');
    });

    test(
      'connect() never double-connects nor opens after close (fix #1 guard)',
      () async {
        final repo = buildRepo();
        repo.connect();
        expect(connectorCalls, 1);

        // Double-connect guard: a second connect must NOT open another socket.
        repo.connect();
        expect(connectorCalls, 1);

        // Connect-after-close guard: a cancel/teardown that raced a pending
        // start must not resurrect a socket. (Reverting the guard => connect
        // opens a socket on a closed repo => connectorCalls increments => RED.)
        final closedRepo = buildRepo();
        await closedRepo.close();
        connectorCalls = 0;
        closedRepo.connect();
        expect(connectorCalls, 0);
      },
    );

    test(
      'emits connecting -> open (on the ready frame) -> closed across the lifecycle',
      () async {
        final repo = buildRepo();
        final states = <SttStreamState>[];
        repo.state.listen(states.add);

        repo.connect();
        await pumpEventQueue();
        // B3: `open` now fires on the relay's ready frame, not the raw handshake.
        channel.emit(jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}));
        await pumpEventQueue();
        channel.emitDone();
        await pumpEventQueue();

        expect(states, <SttStreamState>[
          SttStreamState.connecting,
          SttStreamState.open,
          SttStreamState.closed,
        ]);
      },
    );
  });

  group('wire handshake: open-on-ready (B3), fail-closed (M8), provider (H9)', () {
    test('advertises its wire version on connect via ?wire=', () {
      buildRepo(lang: 'ja').connect();
      expect(connectedUri?.queryParameters['lang'], 'ja');
      expect(
        connectedUri?.queryParameters['wire'],
        '2',
      ); // SttStreamRepo.wireVersion
    });

    test('does NOT emit open on the socket handshake alone (B3)', () async {
      // channel.ready completes, but NO ready frame yet -> stay connecting.
      final repo = openRepoWithReadyHandshake();
      final states = <SttStreamState>[];
      repo.state.listen(states.add);
      await pumpEventQueue();
      expect(states, isNot(contains(SttStreamState.open))); // handshake != open
    });

    test('emits open ONLY when the ready frame arrives (B3)', () async {
      final repo = openRepoWithReadyHandshake();
      final opened = expectLater(repo.state, emitsThrough(SttStreamState.open));
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
      );
      await opened;
      expect(repo.negotiatedWire, 2);
    });

    test(
      'close BEFORE ready => terminal state, never open (B3 -> batch)',
      () async {
        final repo = openRepoWithReadyHandshake();
        final sawOpen = repo.state.any((s) => s == SttStreamState.open);
        final terminal = expectLater(
          repo.state,
          emitsThrough(anyOf(SttStreamState.closed, SttStreamState.error)),
        );
        repo.debugCloseTransport(); // relay 1013 before any ready frame
        await terminal;
        // never emitted open — the session's _awaitOpen() resolves false -> batch.
        expect(await sawOpen, isFalse);
      },
    );

    test('ready frame is not surfaced as a partial', () async {
      final repo = openRepoWithReadyHandshake();
      final partials = <SttPartial>[];
      repo.partials.listen(partials.add);
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
      );
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{
          'type': 'partial',
          'transcript': 'hi',
          'words': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventQueue();
      expect(partials, hasLength(1));
      expect(partials.single.transcript, 'hi');
    });

    test(
      'fail-closed on wire != this client (M8): wire:3 / missing / non-int => batch, never open',
      () async {
        for (final ready in <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'ready',
            'wire': 3,
          }, // a future backend, no v3 parser here
          <String, dynamic>{'type': 'ready'}, // missing wire
          <String, dynamic>{'type': 'ready', 'wire': 'x'}, // non-int
          <String, dynamic>{'type': 'ready', 'wire': 2.0}, // numeric, not int
        ]) {
          final repo = openRepoWithReadyHandshake();
          final sawOpen = repo.state.any((s) => s == SttStreamState.open);
          final terminal = expectLater(
            repo.state,
            emitsThrough(anyOf(SttStreamState.closed, SttStreamState.error)),
          );
          repo.debugHandleInbound(jsonEncode(ready));
          await terminal;
          expect(
            await sawOpen,
            isFalse,
            reason: 'wire=$ready must NOT open (mic never starts)',
          );
        }
      },
    );

    test(
      'records the server-selected provider from the {"type":"provider"} frame (H9)',
      () {
        final repo = openRepoWithReadyHandshake();
        repo.debugHandleInbound(
          jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
        );
        expect(repo.selectedProvider, isNull); // none until the provider frame
        repo.debugHandleInbound(
          jsonEncode(<String, dynamic>{
            'type': 'provider',
            'id': 'speechmatics',
          }),
        );
        expect(repo.selectedProvider, 'speechmatics');
      },
    );

    test('records degraded + primary from the provider frame and fires '
        'providerUpdates (H9b degradation banner wiring)', () async {
      final repo = openRepoWithReadyHandshake();
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
      );
      var updates = 0;
      repo.providerUpdates.listen((_) => updates++);

      // Neutral defaults until any provider frame arrives.
      expect(repo.degraded, isFalse);
      expect(repo.primaryProvider, isNull);

      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{
          'type': 'provider',
          'id': 'assemblyai',
          'degraded': true,
          'primary': 'deepgram',
        }),
      );
      await pumpEventQueue();

      expect(repo.selectedProvider, 'assemblyai'); // still the SERVING id
      expect(repo.degraded, isTrue);
      expect(repo.primaryProvider, 'deepgram');
      expect(
        updates,
        1,
        reason:
            'a live listener (the session) must be able to rebuild '
            'promptly instead of waiting for the next partial',
      );
    });

    test('a normal (non-degraded) provider frame defaults degraded=false, '
        'primary=null (H9b)', () {
      final repo = openRepoWithReadyHandshake();
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{'type': 'ready', 'wire': 2}),
      );
      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{'type': 'provider', 'id': 'deepgram'}),
      );

      expect(repo.selectedProvider, 'deepgram');
      expect(repo.degraded, isFalse);
      expect(repo.primaryProvider, isNull);
    });
  });

  group('outbound framing', () {
    test('sendAudio forwards raw PCM bytes as a single binary frame', () {
      final repo = buildRepo();
      repo.connect();

      final pcm = Uint8List.fromList(<int>[0, 1, 2, 250, 251, 252]);
      repo.sendAudio(pcm);

      expect(channel.sent, hasLength(1));
      final frame = channel.sent.single;
      expect(frame, isA<Uint8List>());
      expect(frame, equals(pcm));
    });

    test('stop sends the {"type":"stop"} control frame as JSON text', () {
      final repo = buildRepo();
      repo.connect();

      repo.stop();

      expect(
        channel.sent,
        contains(jsonEncode(<String, String>{'type': 'stop'})),
      );
    });
  });

  group('inbound wire (D4 shape)', () {
    test(
      'partial message -> SttPartial with words, isFinal/speechFinal false',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        repo.partials.listen(partials.add);

        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'partial',
            'transcript': 'hello wor',
            'words': <Map<String, dynamic>>[
              <String, dynamic>{
                'word': 'hello',
                'start': 0.1,
                'end': 0.4,
                'confidence': 0.92,
              },
            ],
          }),
        );
        await pumpEventQueue();

        expect(partials, hasLength(1));
        final p = partials.single;
        expect(p.transcript, 'hello wor');
        expect(p.isFinal, isFalse);
        expect(p.speechFinal, isFalse);
        expect(p.words, hasLength(1));
        expect(p.words.single.word, 'hello');
        expect(p.words.single.start, 0.1);
        expect(p.words.single.end, 0.4);
        expect(p.words.single.confidence, 0.92);
      },
    );

    test(
      'segment_final message -> SttPartial isFinal true, speechFinal false',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        repo.partials.listen(partials.add);

        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'segment_final',
            'transcript': 'hello',
            'words': <Map<String, dynamic>>[],
          }),
        );
        await pumpEventQueue();

        expect(partials, hasLength(1));
        expect(partials.single.transcript, 'hello');
        expect(partials.single.isFinal, isTrue);
        expect(partials.single.speechFinal, isFalse);
      },
    );

    test(
      'stream_final message -> SttPartial with isFinal & speechFinal true',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        repo.partials.listen(partials.add);

        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'stream_final',
            'transcript': 'hello world',
            'words': <Map<String, dynamic>>[],
          }),
        );
        await pumpEventQueue();

        expect(partials, hasLength(1));
        expect(partials.single.transcript, 'hello world');
        expect(partials.single.isFinal, isTrue);
        expect(partials.single.speechFinal, isTrue);
        expect(partials.single.words, isEmpty);
      },
    );

    test('speech_boundary message -> utteranceEnds signal', () async {
      final repo = buildRepo();
      repo.connect();
      var utteranceEnds = 0;
      repo.utteranceEnds.listen((_) => utteranceEnds++);

      channel.emit(jsonEncode(<String, String>{'type': 'speech_boundary'}));
      await pumpEventQueue();

      expect(utteranceEnds, 1);
    });

    test(
      'error message runs full teardown: error once, sends no-op, late frame '
      'dropped, no later closed',
      () async {
        final repo = buildRepo();
        repo.connect();
        final states = <SttStreamState>[];
        final partials = <SttPartial>[];
        repo.state.listen(states.add);
        repo.partials.listen(partials.add);
        await pumpEventQueue();

        final sentBeforeError = channel.sent.length;
        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'error',
            'code': 'deepgram_upstream',
          }),
        );
        await pumpEventQueue();

        // Terminal error emitted, no partial from the error frame.
        expect(states, contains(SttStreamState.error));
        expect(partials, isEmpty);

        // (a) the underlying sink is closed (teardown ran).
        expect(channel.isClosed, isTrue);

        // (b) `_closed` is set -> post-error sendAudio/stop are no-ops.
        repo.sendAudio(Uint8List.fromList(<int>[1, 2, 3]));
        repo.stop();
        expect(channel.sent.length, sentBeforeError);

        // controllers closed -> a late inbound frame is dropped, no crash.
        repo.debugHandleInbound(
          jsonEncode(<String, dynamic>{
            'type': 'partial',
            'transcript': 'late',
            'words': <Map<String, dynamic>>[],
          }),
        );
        await pumpEventQueue();
        expect(partials, isEmpty);

        // A later remote onDone (or close()) must NOT emit a second terminal
        // state: error is emitted exactly once, and no `closed` follows.
        channel.emitDone();
        await repo.close();
        await pumpEventQueue();
        expect(
          states.where((SttStreamState s) => s == SttStreamState.error).length,
          1,
        );
        expect(states, isNot(contains(SttStreamState.closed)));
      },
    );

    test(
      'unknown, malformed, and binary inbound frames are ignored (no crash)',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        final states = <SttStreamState>[];
        repo.partials.listen(partials.add);
        repo.state.listen(states.add);
        await pumpEventQueue();
        states.clear();

        channel.emit('this is not json {');
        channel.emit(jsonEncode(<String, String>{'type': 'bogus'}));
        channel.emit(jsonEncode(<String, dynamic>{'no_type': true}));
        channel.emit(
          Uint8List.fromList(<int>[1, 2, 3]),
        ); // inbound is JSON-only
        channel.emit(42);
        await pumpEventQueue();

        expect(partials, isEmpty);
        expect(states, isEmpty);
      },
    );
  });

  group('close', () {
    test('is idempotent and closes the underlying sink', () async {
      final repo = buildRepo();
      repo.connect();

      await repo.close();
      expect(channel.isClosed, isTrue);

      // Second close must not throw.
      await repo.close();
    });

    test('post-close sendAudio/stop are no-ops', () async {
      final repo = buildRepo();
      repo.connect();
      await repo.close();

      final sentAfterClose = channel.sent.length;
      repo.sendAudio(Uint8List.fromList(<int>[1, 2, 3]));
      repo.stop();

      expect(channel.sent.length, sentAfterClose);
    });

    test('inbound frames after close are dropped', () async {
      final repo = buildRepo();
      repo.connect();
      final partials = <SttPartial>[];
      repo.partials.listen(partials.add);
      await repo.close();

      channel.emit(
        jsonEncode(<String, dynamic>{
          'type': 'partial',
          'transcript': 'late',
          'words': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventQueue();

      expect(partials, isEmpty);
    });

    // Finding 3 (teeth): a real late-delivery — a frame handled AFTER `_closed`
    // is set, driving the handler directly so the cancel-before-emit path in
    // the test above cannot make this vacuous. If the `_closed` guard in
    // `_onMessage` is removed, this adds to a closed controller -> throws (RED).
    test('a frame handled after close is dropped without throwing', () async {
      final repo = buildRepo();
      repo.connect();
      final partials = <SttPartial>[];
      repo.partials.listen(partials.add);
      await repo.close();

      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{
          'type': 'partial',
          'transcript': 'late',
          'words': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventQueue();

      expect(partials, isEmpty);
    });
  });

  group('wrong-typed but valid-JSON frames (Finding 1)', () {
    test(
      'wrong-typed partial is coerced, not thrown; socket stays open',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        final states = <SttStreamState>[];
        repo.partials.listen(partials.add);
        repo.state.listen(states.add);
        await pumpEventQueue();
        states.clear();

        // transcript is a number and words is a string (wrong types), yet the
        // frame is valid JSON — coercion must not throw and must keep the socket
        // open. A `partial` derives isFinal/speechFinal false from the type.
        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'partial',
            'transcript': 123,
            'words': 'nope',
          }),
        );
        await pumpEventQueue();

        expect(partials, hasLength(1));
        expect(partials.single.transcript, '');
        expect(partials.single.isFinal, isFalse);
        expect(partials.single.speechFinal, isFalse);
        expect(partials.single.words, isEmpty);
        // No error state emitted; the socket is still usable.
        expect(states, isEmpty);
      },
    );

    test(
      'wrong-typed stream_final (and wrong-typed word rows) are coerced, not thrown',
      () async {
        final repo = buildRepo();
        repo.connect();
        final partials = <SttPartial>[];
        repo.partials.listen(partials.add);

        channel.emit(
          jsonEncode(<String, dynamic>{
            'type': 'stream_final',
            'transcript': 'ok',
            'words': <dynamic>[
              <String, dynamic>{
                'word': 42,
                'start': 'x',
                'end': null,
                'confidence': 'high',
              },
            ],
          }),
        );
        await pumpEventQueue();

        expect(partials, hasLength(1));
        final p = partials.single;
        expect(p.transcript, 'ok');
        expect(p.words, hasLength(1));
        expect(p.words.single.word, '');
        expect(p.words.single.start, 0);
        expect(p.words.single.end, 0);
        expect(p.words.single.confidence, 0);
      },
    );
  });

  group('remote close teardown (Finding 2)', () {
    test(
      'remote onDone runs teardown: sends become no-ops, closed emitted once',
      () async {
        final repo = buildRepo();
        final states = <SttStreamState>[];
        repo.state.listen(states.add);
        repo.connect();
        await pumpEventQueue();

        final sentBeforeRemoteClose = channel.sent.length;
        channel.emitDone(); // far side closes the socket
        await pumpEventQueue();

        // After a remote close, sends must not reach the stale sink.
        repo.sendAudio(Uint8List.fromList(<int>[1, 2, 3]));
        repo.stop();
        expect(channel.sent.length, sentBeforeRemoteClose);

        // `closed` is emitted exactly once (no duplicate from a later close()).
        await repo.close();
        expect(
          states.where((SttStreamState s) => s == SttStreamState.closed).length,
          1,
        );
      },
    );

    test('inbound frames after a remote close are dropped', () async {
      final repo = buildRepo();
      repo.connect();
      final partials = <SttPartial>[];
      repo.partials.listen(partials.add);
      await pumpEventQueue();

      channel.emitDone();
      await pumpEventQueue();

      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{
          'type': 'partial',
          'transcript': 'late',
          'words': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventQueue();

      expect(partials, isEmpty);
    });
  });

  group('transport error teardown (Finding 2b)', () {
    test(
      'stream onError runs teardown: error emitted once, sends become no-ops',
      () async {
        final repo = buildRepo();
        final states = <SttStreamState>[];
        repo.state.listen(states.add);
        repo.connect();
        await pumpEventQueue();

        final sentBeforeError = channel.sent.length;
        channel.emitError(Exception('socket blew up'));
        await pumpEventQueue();

        // (b) `_closed` is set, so post-error sends never reach the stale sink.
        repo.sendAudio(Uint8List.fromList(<int>[1, 2, 3]));
        repo.stop();
        expect(channel.sent.length, sentBeforeError);

        // (a) `error` is emitted exactly once; a later close() adds no `closed`.
        await repo.close();
        expect(
          states.where((SttStreamState s) => s == SttStreamState.error).length,
          1,
        );
        expect(states, isNot(contains(SttStreamState.closed)));
      },
    );

    test('(c) inbound frames after a transport error are dropped', () async {
      final repo = buildRepo();
      repo.connect();
      final partials = <SttPartial>[];
      repo.partials.listen(partials.add);
      await pumpEventQueue();

      channel.emitError(Exception('socket blew up'));
      await pumpEventQueue();

      repo.debugHandleInbound(
        jsonEncode(<String, dynamic>{
          'type': 'partial',
          'transcript': 'late',
          'words': <Map<String, dynamic>>[],
        }),
      );
      await pumpEventQueue();

      expect(partials, isEmpty);
    });
  });

  group('sink.add throw is funneled to teardown (fix #2)', () {
    test(
      'sendAudio throw does NOT propagate; teardown runs; later sends no-op',
      () async {
        late _FakeWebSocketChannel throwingChannel;
        final repo = SttStreamRepo(
          wsUrl: 'wss://api.example/choreo/speech_to_text/stream',
          accessToken: 'TOKEN123',
          connector: (uri, {protocols}) {
            throwingChannel = _FakeWebSocketChannel(
              protocols: protocols,
              throwOnAdd: true,
            );
            return throwingChannel;
          },
        );
        final states = <SttStreamState>[];
        repo.state.listen(states.add);
        repo.connect();
        await pumpEventQueue();

        // A close-race throw from sink.add must NOT reach the capture callback.
        // (Reverting the try/catch => sendAudio rethrows => `returnsNormally`
        // fails and no teardown fires => RED.)
        expect(
          () => repo.sendAudio(Uint8List.fromList(<int>[1, 2, 3, 4])),
          returnsNormally,
        );
        await pumpEventQueue();

        // The throw was funneled through the idempotent error teardown.
        expect(states, contains(SttStreamState.error));
        expect(throwingChannel.isClosed, isTrue);

        // Later sends are clean no-ops (guarded by `_closed`), never a throw.
        final sentBefore = throwingChannel.sent.length;
        expect(() => repo.stop(), returnsNormally);
        expect(throwingChannel.sent.length, sentBefore);
      },
    );
  });
}
