import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_stream_state.dart';

/// Opens the streaming-STT WebSocket. Defaults to [WebSocketChannel.connect];
/// tests inject a fake so no real socket is opened. The signature matches
/// `WebSocketChannel.connect` exactly (uri + `protocols`), so the subprotocol
/// auth is preserved through the seam.
typedef WebSocketConnector =
    WebSocketChannel Function(Uri uri, {Iterable<String>? protocols});

/// Client transport for the streaming-STT relay (`/choreo/speech_to_text/stream`).
///
/// Lifted from Luna's `LunaVoiceRepo` — transport core only. Authenticates with
/// the learner's Matrix access token via the `access_token.<token>` subprotocol
/// (never a query string; works cross-origin from browsers where headers can't
/// be set), streams raw PCM16 out as binary frames, and normalizes the relay's
/// D4 JSON into [SttPartial] / [SttStreamState]. The repo only moves
/// bytes/events; capture and rendering are the caller's concern (so it stays
/// unit-testable and transport-only).
///
/// Dropped from Luna (conversation-specific, out of pilot scope): audio-out
/// playback and the binary-inbound branch, corrections, interruptions, tutor
/// turns, and cost. Nothing here imports a `luna_*` file.
class SttStreamRepo {
  SttStreamRepo({
    required this.wsUrl,
    required this.accessToken,
    this.lang = 'en',
    WebSocketConnector? connector,
  }) : _connect = connector ?? WebSocketChannel.connect;

  /// The neutral D4 wire version this client speaks, advertised on connect as
  /// `?wire=` (spec D2a). `open` is emitted ONLY when the relay's `ready` frame
  /// negotiates this exact version — anything else fails closed to batch (M8).
  static const int wireVersion = 2;

  /// The `wss://`/`ws://` relay endpoint (see `PApiUrls.speechToTextStream`).
  final String wsUrl;
  final String accessToken;

  /// D4 language query (`?lang=`): wave-1's relay REQUIRES it — it gates the
  /// language and closes 1008 for an unsupported one, only defaulting to `en`
  /// as a fallback. The client already gates to the pilot's supported set
  /// (English), so the gated language is passed through explicitly here.
  final String lang;

  final WebSocketConnector _connect;

  /// The exact D4 connect [Uri]: [wsUrl] with the `?lang=` and `?wire=` queries
  /// merged in (existing query params preserved).
  Uri get connectUri => Uri.parse(wsUrl).replace(
    queryParameters: <String, String>{
      ...Uri.parse(wsUrl).queryParameters,
      'lang': lang,
      'wire': '$wireVersion',
    },
  );

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  /// The wire version the relay negotiated in its `{"type":"ready","wire":n}`
  /// frame, or `null` until it arrives. Set only when it matches [wireVersion].
  int? _negotiatedWire;
  int? get negotiatedWire => _negotiatedWire;

  /// The provider the RELAY actually selected for this session (H9), from its
  /// `{"type":"provider","id":...}` control frame. `null` until it arrives; the
  /// session stamps THIS as the persisted provenance (never a hardcoded engine).
  String? _selectedProvider;
  String? get selectedProvider => _selectedProvider;

  /// True when the relay's PRIMARY provider failed and this session is being
  /// served by a RUNNER-UP (the `degraded` flag on the same `provider` frame,
  /// H9b). Streaming stays fully live when this is true — only the ENGINE
  /// changed. Drives the "degraded but live" degradation banner. `false`
  /// until/unless a provider frame sets it.
  bool _degraded = false;
  bool get degraded => _degraded;

  /// The primary provider's id when [degraded] is true (diagnostics / banner
  /// copy); `null` on a normal (non-degraded) session.
  String? _primaryProvider;
  String? get primaryProvider => _primaryProvider;

  final StreamController<SttPartial> _partials =
      StreamController<SttPartial>.broadcast();
  final StreamController<void> _utteranceEnds =
      StreamController<void>.broadcast();
  final StreamController<SttStreamState> _state =
      StreamController<SttStreamState>.broadcast();
  final StreamController<void> _providerUpdates =
      StreamController<void>.broadcast();

  /// Interim `partial` and settled `segment_final`/`stream_final` transcript
  /// updates (neutral D4).
  Stream<SttPartial> get partials => _partials.stream;

  /// A `{"type":"speech_boundary"}` word-gap segment boundary (neutral D4). Kept
  /// as a first-class transport signal because the editable-buffer state machine
  /// (D7) commits a segment on it; a transport that recognized the frame but
  /// dropped it would not be complete.
  Stream<void> get utteranceEnds => _utteranceEnds.stream;

  /// Socket lifecycle: connecting -> open -> closed, or error.
  Stream<SttStreamState> get state => _state.stream;

  /// Fires whenever a `{"type":"provider"}` frame updates [selectedProvider] /
  /// [degraded] / [primaryProvider] (H9b), so a live listener (the session, in
  /// turn the recording view-model's degradation banner) can rebuild promptly
  /// instead of waiting for the next partial. Payload is `void` — same idiom as
  /// [utteranceEnds]; listeners read the just-updated getters.
  Stream<void> get providerUpdates => _providerUpdates.stream;

  void _emitState(SttStreamState s) {
    if (!_closed && !_state.isClosed) _state.add(s);
  }

  /// Open the socket. Emits [SttStreamState.connecting] synchronously, then
  /// [SttStreamState.open] once the channel is ready.
  void connect() {
    // Guard: never open a socket on a terminally-closed repo (a cancel/teardown
    // that raced a pending start would leave an unreapable socket), and never
    // double-connect.
    if (_closed || _channel != null) return;
    _emitState(SttStreamState.connecting);
    final channel = _connect(
      connectUri,
      protocols: <String>['access_token.$accessToken'],
    );
    _channel = channel;
    // B3: the socket handshake NO LONGER emits `open`. A successful handshake
    // stays `connecting` until the relay's `{"type":"ready","wire":2}` frame
    // arrives (handled in _onMessage); only a handshake FAILURE tears down here.
    channel.ready.catchError((_) => _teardown(SttStreamState.error));
    // A remote close (onDone) or transport failure (onError) must run the SAME
    // idempotent teardown as an explicit close(): emit the terminal state once,
    // set `_closed`, and shut the controllers/subscription — otherwise
    // sendAudio/stop would keep writing to a dead sink.
    _sub = channel.stream.listen(
      _onMessage,
      onError: (_) => _teardown(SttStreamState.error),
      onDone: () => _teardown(SttStreamState.closed),
    );
  }

  /// Test seam: drive the inbound handler directly so the post-`_closed` guard
  /// can be exercised even when the real subscription is already cancelled.
  @visibleForTesting
  void debugHandleInbound(dynamic data) => _onMessage(data);

  /// Test seam: run the same idempotent teardown a remote `onDone` would, so a
  /// "close before ready" (relay 1013 wire cutoff / gate reject) can be
  /// exercised without a real socket.
  @visibleForTesting
  void debugCloseTransport() => unawaited(_teardown(SttStreamState.closed));

  void _onMessage(dynamic data) {
    if (_closed) return;
    // Inbound is JSON text only (D4). Binary / non-string frames are ignored.
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'ready':
        // B3: the SOLE emitter of `open` now — the relay admitted us (auth,
        // entitlement, language, and gate all passed). M8 fail-closed: open ONLY
        // if the relay's wire == the version THIS client can parse; anything else
        // (a future 3, missing, non-int) tears down before open -> batch.
        final w = msg['wire'];
        if (w is int && w == wireVersion) {
          _negotiatedWire = w;
          _emitState(SttStreamState.open);
        } else {
          unawaited(_teardown(SttStreamState.error));
        }
        break;
      case 'provider':
        // H9: server-authoritative provenance. Record which provider the relay's
        // chain-walk selected; the session stamps THIS on the persisted
        // transcript. Control frame — never surfaced as a transcript.
        final id = msg['id'];
        if (id is String && id.isNotEmpty) {
          _selectedProvider = id;
          // H9b degradation: the PRIMARY failed and a runner-up is serving —
          // streaming stays live. `primary` names the failed engine when
          // present; both default false/null on a normal, non-degraded frame.
          _degraded = msg['degraded'] == true;
          final primary = msg['primary'];
          _primaryProvider = primary is String && primary.isNotEmpty
              ? primary
              : null;
          if (!_providerUpdates.isClosed) _providerUpdates.add(null);
        }
        break;
      case 'partial':
      case 'segment_final':
      case 'stream_final':
        _partials.add(SttPartial.fromJson(msg));
        break;
      case 'speech_boundary':
        if (!_utteranceEnds.isClosed) _utteranceEnds.add(null);
        break;
      case 'error':
        // A server error frame is terminal: run the SAME idempotent teardown as
        // onDone/onError (emit `error` once, set `_closed`, cancel the sub,
        // close the controllers) so post-error sends are no-ops and no later
        // `closed` can follow. Fire-and-forget: `_onMessage` is a sync callback.
        unawaited(_teardown(SttStreamState.error));
        break;
      default:
        // Unknown / typeless message: ignore, never crash.
        break;
    }
  }

  /// Stream raw PCM16 @16kHz mic frames to the relay as a binary frame
  /// (no-op after [close]).
  void sendAudio(Uint8List pcm) => _guardedSend(pcm);

  /// Signal end-of-utterance to the relay (→ Deepgram Finalize+CloseStream),
  /// flushing trailing finals (no-op after [close]).
  void stop() => _guardedSend(jsonEncode(<String, String>{'type': 'stop'}));

  /// Write to the sink defensively. A socket-close race can make `sink.add`
  /// throw AFTER our last `_closed` check but BEFORE `onError`/`onDone` flips
  /// `_closed`; such a throw must NOT propagate into the capture callback (it
  /// would crash the mic tee). Funnel it through the idempotent error teardown
  /// and swallow, so a later send is a clean no-op.
  void _guardedSend(dynamic data) {
    if (_closed) return;
    try {
      _channel?.sink.add(data);
    } catch (_) {
      unawaited(_teardown(SttStreamState.error));
    }
  }

  /// Idempotently tear down the socket and all streams. Post-close sends are
  /// no-ops and post-close inbound frames are dropped (the `_closed` guard).
  Future<void> close() => _teardown(SttStreamState.closed);

  /// The single teardown path shared by [close], remote `onDone`, `onError`,
  /// and a failed `ready`. Idempotent: [finalState] is emitted at most once and
  /// the controllers are closed exactly once.
  Future<void> _teardown(SttStreamState finalState) async {
    if (_closed) return;
    _emitState(finalState);
    _closed = true;
    try {
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {
      // Best-effort teardown; a failing close must not surface.
    } finally {
      await _partials.close();
      await _utteranceEnds.close();
      await _state.close();
      await _providerUpdates.close();
    }
  }
}
