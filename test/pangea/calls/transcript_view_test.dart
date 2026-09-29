import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/subscription/widgets/locked_preview_banner.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_box.dart';
import 'package:fluffychat/routes/chat/audio_player.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_recordings_load.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_view.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';
import 'package:fluffychat/routes/chat/calls/whole_call_transcriber.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

const _callKey = r'$membership:fakeServer.notExisting';

/// A real wall-clock instant, because that is what a position IS.
///
/// 2026-08-26T09:00:00Z. Using 0 here would quietly make every fixture agree
/// with a screen that never converted absolute time to elapsed.
const _callStart = 1787994000000;
const _me = '@test:fakeServer.notExisting';
const _peer = '@peer:fakeServer.notExisting';

/// Skips `initMatrix()` — push, notification listeners and the Pangea
/// controller wiring are all irrelevant here and none of them stand up
/// under `flutter test`. Only needed for the recordings tests below, which
/// render an `AudioPlayerWidget` and so need a real `Matrix.of(context)` to
/// answer -- every other test in this file renders `CallTranscriptView`
/// directly and never reaches for one. Same bootstrap as
/// `incoming_call_banner_test.dart`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// A stand-in for the merged recording's [AudioPlayer]: there is no audio
/// backend under `flutter test`, so `setFilePath`/playback would throw and no
/// real position/playing events would ever flow. This fake lets a test drive
/// `positionStream`/`playerStateStream` (both broadcast, so the transcript's
/// observation AND the bar control's own StreamBuilder can co-observe) and
/// records the transport calls the fixes turn on (seek/play/pause). Only the
/// members the merged-playback path actually touches are implemented; anything
/// else throwing via [noSuchMethod] would signal a missed call, not pass
/// silently.
class _FakeAudioPlayer implements AudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  Duration _pos = Duration.zero;
  PlayerState _state = PlayerState(false, ProcessingState.ready);

  int playCount = 0;
  int pauseCount = 0;
  int seekCount = 0;
  bool disposed = false;

  /// When true, [seek] REJECTS -- so a test can drive the replay-seek failure
  /// path ([_MergedFullCallControlState._replayFromStart]).
  bool failSeek = false;

  /// When set, [seek] BLOCKS on this until it completes -- so a test can land a
  /// second tap between a replay's seek and its resume (the G-2 window).
  Completer<void>? seekGate;

  /// When true, [stop]/[pause]/[dispose] RECORD their effect and then THROW --
  /// so a test can drive a rejecting teardown and assert no unhandled async
  /// error escapes the fire-and-forget release paths (G-3).
  bool failTeardown = false;

  /// Drives a playback position through both streams' consumers.
  void emitPosition(Duration position) {
    _pos = position;
    _positions.add(position);
  }

  /// Drives a playing/paused edge through `playerStateStream`.
  void emitPlaying(bool playing) {
    _state = PlayerState(playing, ProcessingState.ready);
    _states.add(_state);
  }

  /// Drives an end-of-track edge: `ProcessingState.completed` with the playing
  /// flag still set, as just_audio reports it when a track runs to the end.
  void emitCompleted() {
    _state = PlayerState(true, ProcessingState.completed);
    _states.add(_state);
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  Duration get position => _pos;

  @override
  Duration? get duration => null;

  @override
  bool get playing => _state.playing;

  @override
  PlayerState get playerState => _state;

  @override
  Future<void> play() async {
    playCount++;
    emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    emitPlaying(false);
    if (failTeardown) throw StateError('pause rejected');
  }

  @override
  Future<void> stop() async {
    emitPlaying(false);
    if (failTeardown) throw StateError('stop rejected');
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (seekGate != null) await seekGate!.future;
    if (failSeek) throw StateError('seek rejected');
    seekCount++;
    if (position != null) _pos = position;
  }

  @override
  Future<Duration?> setFilePath(
    String filePath, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async => null;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _positions.close();
    await _states.close();
    if (failTeardown) throw StateError('dispose rejected');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The timeline draws the app's real Avatar, which reads
    // BotName.byEnvironment -> GetStorage and dotenv. Neither is stood up by
    // the widget-test harness, so a bare Avatar THROWS -- and Flutter answers
    // a thrown build with a RenderErrorBox, which reports itself as 100000
    // pixels tall and pushes everything after it out of a lazy list.
    //
    // That is worth the comment: the failure reads as a layout bug in the
    // widget under test, and it is a missing fixture in this file. Same
    // bootstrap as turn_timeline_test.dart and incoming_call_banner_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('transcript_view');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
  });

  late Client client;

  setUp(() async {
    client = await getTestClient();
    // #8792's whole-transcript paywall reads
    // `MatrixState.pangeaController.subscriptionController
    // .showSubscriptionGatedContent` on every build of the conversation
    // body, so every group in this file needs SOME `pangeaController`
    // installed, not only the 'call recordings' group that already set one
    // up for its own (unrelated) reasons. The paywall/on-demand groups below
    // install their OWN `FakePangeaController` per test and override this
    // default; every other group just needs the field initialized at all.
    MatrixState.pangeaController = FakePangeaController();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A room whose membership is already in memory and marked complete, so
  /// `requestParticipants` answers from state instead of reaching for a
  /// homeserver this test does not have.
  Room room({List<String> members = const [_me, _peer]}) {
    // A real direct chat: the peer is read from m.direct, which is where both
    // sides of a 1:1 call now come from.
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        _peer: ['!c:fakeServer.notExisting'],
      },
    );
    final r = Room(
      id: '!c:fakeServer.notExisting',
      client: client,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': members.length,
        'm.invited_member_count': 0,
        'm.heroes': <String>[],
      }),
    );
    for (final id in members) {
      r.setState(
        Event(
          type: EventTypes.RoomMember,
          stateKey: id,
          content: const {'membership': 'join'},
          senderId: id,
          eventId: '\$member-$id',
          originServerTs: DateTime.now(),
          room: r,
        ),
      );
    }
    return r;
  }

  /// The same room, but encrypting its events.
  Room encryptedRoom() {
    final r = room();
    r.setState(
      Event(
        type: EventTypes.Encryption,
        stateKey: '',
        content: const {'algorithm': 'm.megolm.v1.aes-sha2'},
        senderId: _me,
        eventId: r'$enc',
        originServerTs: DateTime.now(),
        room: r,
      ),
    );
    return r;
  }

  MatrixEvent half(
    String sender, {
    List<String> texts = const ['hola que tal'],
    int captured = 1,
    int transcribed = 1,
    int lost = 0,

    /// Chunks the writing device's own speech detector held back. Zero in every
    /// fixture that is not about them, which is the ordinary case.
    int suppressed = 0,

    /// Chunks handed to another of this account's devices. Zero in every
    /// fixture that is not about a handover, which is the ordinary case.
    int discarded = 0,
    bool drainComplete = true,
    bool declared = true,

    /// One position per entry in [texts], as ABSOLUTE Unix milliseconds --
    /// which is what the writer emits and therefore the only shape worth
    /// testing against. Small numbers like 0 and 3000 would be the DISPLAY
    /// unit, and a fixture in the display unit cannot catch a screen that
    /// forgot to convert. Null is the ordinary case here, which is why the
    /// per-speaker view is what most of these assert.
    List<int>? atMs,

    /// What this device's clock read against the SFU's when it joined.
    ///
    /// Present by default, and in step with the SFU, because that is what
    /// `transcript_writer.dart` emits whenever `ClockAnchor.of` can read both
    /// clocks -- the ordinary case. A fixture that models our own writer has to
    /// carry the claims our writer makes, the same argument [positionsMarked]
    /// already settles one field down.
    ///
    /// The offset is deliberately ZERO, so this default moves no position and
    /// changes what no test asserts. What it does change is which QUESTION the
    /// fixture asks: without an anchor, two speaking halves are two devices
    /// whose clocks were never compared, and this screen no longer vouches for
    /// times measured across those. The tests that are ABOUT a missing anchor
    /// pass null explicitly.
    ClockAnchor? anchor = const ClockAnchor(
      sfuMs: _callStart - 2000,
      deviceMs: _callStart - 2000,
    ),

    /// How much later than its `at_ms` each segment could have begun, or null
    /// for a segment placed at its own first word. One entry per [texts] entry.
    List<int?>? spanMs,

    /// Whether this writer says which of its positions are exact.
    ///
    /// TRUE by default because that is what `transcript_writer.dart` emits, and
    /// a fixture that models our own writer has to carry the claims our writer
    /// makes. The four tests that broke when this arrived were not finding a
    /// bug -- they were fixtures that had silently become foreign clients, and
    /// a foreign client's times are deliberately not printed.
    bool positionsMarked = true,

    /// The writing device never opened a microphone. False in every fixture
    /// that is not about it, which is the ordinary case.
    bool captureRefused = false,

    /// Which of the sender's devices wrote this half. Null in every fixture
    /// that is not about two devices, which is both the ordinary case and the
    /// shape of every half written before the field existed.
    String? deviceId,

    /// The stretches this device says it kept, and the ones it says it handed
    /// to a sibling. Empty in every fixture that is not about a handover, which
    /// is both the ordinary case and the shape of every half written before the
    /// fields existed.
    List<CaptureSpan> keptSpans = const [],
    List<CaptureSpan> discardedSpans = const [],
  }) => MatrixEvent(
    type: CallTranscriptContent.relType,
    eventId: '\$half-$sender-${deviceId ?? ''}',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    content: {
      'call_key': _callKey,
      'segments': [
        for (final (i, t) in texts.indexed)
          {
            'text': t,
            if (atMs != null) 'at_ms': atMs[i],
            if (spanMs?[i] != null) 'at_span_ms': spanMs![i],
          },
      ],
      'device_id': ?deviceId,
      if (positionsMarked) 'positions_marked': true,
      if (keptSpans.isNotEmpty)
        'kept_spans': [for (final span in keptSpans) span.toJson()],
      if (discardedSpans.isNotEmpty)
        'discarded_spans': [for (final span in discardedSpans) span.toJson()],
      // From the writer's own serialiser, so a fixture cannot drift out of the
      // declaration contract when a field is added to it.
      if (declared)
        ...HalfAccounting(
          chunksCaptured: captured,
          chunksTranscribed: transcribed,
          chunksLost: lost,
          chunksSuppressed: suppressed,
          chunksDiscarded: discarded,
          captureRefused: captureRefused,
          drainComplete: drainComplete,
        ).toJson(),
      ...?anchor?.toJson(),
    },
  );

  /// A `pangea.call_audio` half for [sender], built by the real model's own
  /// serialiser -- like [half] above is not, but [packedToNothing] below is
  /// -- so a fixture here cannot drift out of the writer's actual content
  /// shape (`url`/`mimetype`/`size` at the top level, never nested under
  /// `info`) when a field is added to it.
  MatrixEvent audioEvent(
    String sender, {
    String? deviceId,
    String url = 'mxc://fakeServer.notExisting/AUDIO',
  }) => MatrixEvent(
    type: CallAudioContent.relType,
    eventId: '\$audio-$sender-${deviceId ?? ''}',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    content: CallAudioContent(
      callKey: _callKey,
      deviceId: deviceId,
      url: url,
      mimetype: 'audio/wav',
      codec: kCallAudioCodec,
      size: 12345,
      durationMs: 4000,
      sampleRate: 16000,
      channels: 1,
    ).toJson(),
  );

  /// A `pangea.call_audio_merged` full-call recording for the call, built by
  /// the real model's own serialiser -- like [audioEvent] and unlike [half] --
  /// so a fixture here cannot drift out of the writer's actual content shape.
  /// [sourceEventIds] is this merge's coverage: its length drives
  /// `coverageCardinality`, and it must be non-empty or `fromJson` refuses it.
  MatrixEvent mergedEvent(
    String sender, {
    String eventId = r'$merged',
    List<String> sourceEventIds = const [r'$a', r'$b'],
    // The recording's start on the SFU clock. Null by default -- as an old or
    // foreign merge that carries no start would be -- so the fixtures that are
    // not about the timeline anchor keep the first-turn origin unchanged.
    int? mergedStartSfuMs,
  }) => MatrixEvent(
    type: CallAudioMergedContent.relType,
    eventId: eventId,
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
    content: CallAudioMergedContent(
      callKey: _callKey,
      url: 'mxc://fakeServer.notExisting/MERGED',
      mimetype: 'audio/wav',
      codec: kCallAudioCodec,
      size: 24680,
      durationMs: 8000,
      sampleRate: 16000,
      channels: 1,
      sourceEventIds: sourceEventIds,
      mergedStartSfuMs: mergedStartSfuMs,
    ).toJson(),
  );

  /// A half OUR OWN writer packed down to nothing.
  ///
  /// Written by the real writer rather than hand-rolled, because the shape only
  /// exists when one segment's text alone will not fit the budget: the binary
  /// search then converges on zero, and the half ships marked truncated, with
  /// every segment omitted and no words. A hand-written accounting could assert
  /// that combination whether or not the packer can ever reach it.
  Future<MatrixEvent> packedToNothing(String sender) async {
    Map<String, dynamic>? written;
    final wrote = await writeCallTranscript(
      send: (content, _) async {
        written = content;
      },
      callKey: _callKey,
      senderId: sender,
      // No device, so the event this builds is byte-for-byte the shape every
      // other fixture here uses and the packing assertion turns on nothing
      // else.
      deviceId: null,
      segments: [TranscriptSegment('a' * 2000)],
      chunksCaptured: 1,
      chunksTranscribed: 1,
      chunksLost: 0,
      chunksRefusedUnsubscribed: 0,
      chunksSuppressed: 0,
      chunksDiscarded: 0,
      keptSpans: const [],
      discardedSpans: const [],
      captureDroppedMs: 0,
      captureRefused: false,
      drainComplete: true,
      maxBytes: 600,
    );

    expect(
      wrote,
      isTrue,
      reason: 'the envelope alone fits, so the empty half IS sent',
    );
    return MatrixEvent(
      type: CallTranscriptContent.relType,
      eventId: '\$packed-$sender',
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: written!,
    );
  }

  /// A fetcher serving one page and then saying it is exhausted.
  RelationsFetcher serving(List<MatrixEvent> events) =>
      ({
        required String roomId,
        required String eventId,
        required String relType,
        String? from,
      }) async => (chunk: events, nextBatch: null);

  /// Like [serving], but returns only the events whose type matches the
  /// requested [relType], the way the real `/relations/{event}/{relType}`
  /// endpoint does. [serving] hands EVERY event to EVERY read, which is
  /// harmless when a sender has a matching half of each kind, but a
  /// `pangea.call_audio` event handed to the TRANSCRIPT read parses as an
  /// unreadable transcript -- so a sender with a recording but no transcript
  /// half reads as `couldNotRead` rather than `absent`. The loading tests need
  /// exactly that split (recording present, transcript half genuinely absent),
  /// so they serve through this.
  RelationsFetcher servingByType(List<MatrixEvent> events) =>
      ({
        required String roomId,
        required String eventId,
        required String relType,
        String? from,
      }) async => (
        chunk: events.where((event) => event.type == relType).toList(),
        nextBatch: null,
      );

  /// A fetcher that fails until [failures] is exhausted, then serves.
  ({RelationsFetcher fetch, int Function() calls}) flaky(
    int failures,
    List<MatrixEvent> events,
  ) {
    var calls = 0;
    Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
      required String roomId,
      required String eventId,
      required String relType,
      String? from,
    }) async {
      calls++;
      if (calls <= failures) throw Exception('network');
      return (chunk: events, nextBatch: null);
    }

    return (fetch: fetch, calls: () => calls);
  }

  Future<void> pump(WidgetTester tester, RelationsFetcher fetcher) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: CallTranscriptView(
          room: room(),
          callKey: _callKey,
          fetcher: fetcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CallTranscriptView', () {
    testWidgets('a fully positioned call is drawn as ONE conversation', (
      tester,
    ) async {
      // The whole point of the feature: a teacher reads the call in the order
      // it happened, rather than two columns to cross-reference by hand.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola', 'que tal'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart, _callStart + 6000],
          ),
          half(_peer, texts: ['muy bien'], atMs: [_callStart + 3000]),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);

      // Asserted on what is DRAWN, not on what was handed over. The widget
      // sorts its own input, so reading `turns` back would only prove what
      // this file passed in -- a test that cannot see the ordering it exists
      // to check.
      //
      // Interleaved by time, not grouped by speaker: the peer's reply at 3s
      // sits BETWEEN our two turns, which is the thing the per-speaker view
      // cannot express.
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('hola'), lessThan(top('muy bien')));
      expect(top('muy bien'), lessThan(top('que tal')));
    });

    testWidgets('turn times are elapsed from the call, not wall clock', (
      tester,
    ) async {
      // The two sides of this seam speak different units. A position is an
      // ABSOLUTE Unix millisecond, which is what makes two devices comparable;
      // a turn's time is ELAPSED and prints as m:ss. Handed over unconverted,
      // a call placed in 2026 renders as some twenty-eight million minutes in
      // -- and every fixture that used 0 and 3000 agreed with it, because
      // those are the display unit rather than the stored one.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart]),
          half(_peer, texts: ['muy bien'], atMs: [_callStart + 74000]),
        ]),
      );

      // Counted from the EARLIEST turn in the transcript, so the first thing
      // anybody said is the zero.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('1:14'), findsOneWidget);
    });

    testWidgets('the clock starts at the first turn, whoever spoke it', (
      tester,
    ) async {
      // Per-half origins would restart the clock for the second speaker and
      // stack both columns on top of each other. One clock runs behind the
      // whole conversation, and it starts when somebody first speaks -- here
      // that is the PEER, so our own later turn must not read as zero.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart + 30000]),
          half(_peer, texts: ['muy bien'], atMs: [_callStart]),
        ]),
      );

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
    });

    testWidgets('a call with SOME positions is not drawn as a conversation', (
      tester,
    ) async {
      // The dangerous case, and the reason the gate is all-or-nothing. Drawing
      // the positioned half in order and guessing where the other one goes
      // would present a guess in the shape of a record.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart]),
          half(_peer, texts: ['muy bien']),
        ]),
      );

      expect(find.byType(TurnTimeline), findsNothing);
      expect(find.text('hola'), findsOneWidget);
      expect(find.text('muy bien'), findsOneWidget);
    });

    testWidgets('positions that go backwards are not a conversation', (
      tester,
    ) async {
      // Present on every segment, and jumbled. Presence alone would let this
      // render a speaker's own words out of order with full confidence.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola', 'que tal'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart + 6000, _callStart],
          ),
          half(_peer, texts: ['muy bien'], atMs: [_callStart + 3000]),
        ]),
      );

      expect(find.byType(TurnTimeline), findsNothing);
    });

    testWidgets('an answer bounded to a chunk does not jump ahead of its '
        'question', (tester) async {
      // THE HARM, staged from the real shape of it. One of Alice's chunks ran
      // from 0s to 45s and its word timings could not be used, so every
      // sentence cut from it carries the same estimate -- the earliest evidence
      // of speech anywhere in the chunk. Her "si" was actually said forty
      // seconds in, answering Bob's question at thirty.
      //
      // Placed at the estimate, "si" renders at 0:00 and the transcript shows a
      // learner answering a question they had not been asked. Placed at the end
      // of the chunk it was cut from -- the last moment it could have been
      // said -- it cannot.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['si'],
            atMs: [_callStart],
            spanMs: [45000],
            anchor: null,
          ),
          half(_peer, texts: ['estas de acuerdo'], atMs: [_callStart + 30000]),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(
        top('estas de acuerdo'),
        lessThan(top('si')),
        reason: 'the question must come before the answer to it',
      );
    });

    testWidgets('the SAME halves without the span read out of order', (
      tester,
    ) async {
      // The control, and the thing that proves the test above exercises the
      // span rather than agreeing with the raw positions. Identical fixture
      // with `at_span_ms` stripped: the answer sorts on the estimate and lands
      // ahead of the question, which is the defect exactly.
      await pump(
        tester,
        serving([
          half(_me, texts: ['si'], atMs: [_callStart]),
          half(_peer, texts: ['estas de acuerdo'], atMs: [_callStart + 30000]),
        ]),
      );

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('si'), lessThan(top('estas de acuerdo')));
    });

    testWidgets('a turn bounded to a chunk says "by", and says why', (
      tester,
    ) async {
      // The peer opens the call with an exactly timed word, so the origin is
      // that word and every number below is elapsed from it. Without it the
      // origin would be the EARLIEST PLACED moment, which is the peer's
      // question at 30s -- correct, but it puts the reader's arithmetic on a
      // number that has nothing to do with what this test is about.
      await pump(
        tester,
        serving([
          half(_me, texts: ['si'], atMs: [_callStart], spanMs: [45000]),
          half(
            _peer,
            texts: ['hola', 'estas de acuerdo'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart, _callStart + 30000],
          ),
        ]),
      );

      // Placed at the END of its window, and printed as the bound it is.
      expect(find.text('by 0:45'), findsOneWidget);
      // The other speaker's turns were timed to their own words, so they print
      // plain stamps -- which is what stops this test passing on a screen that
      // simply gave up and marked everything approximate.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      expect(find.textContaining('at or before'), findsOneWidget);
    });

    testWidgets('the clock starts at the earliest PLACED moment', (
      tester,
    ) async {
      // The origin is the minimum over the same keys everything is ordered by,
      // not over the raw positions. Two reasons, and this fixture is the second
      // one: our estimate here is _callStart while our turn is PLACED 45s
      // later, so an origin taken from the estimate would put the peer's 30s
      // turn at 0:30 and ours at 0:45 -- but an origin taken from the raw
      // minimum of a DIFFERENT half could sit after a key and render a
      // negative elapsed time. Taking the minimum over exactly the values being
      // subtracted from makes that impossible.
      await pump(
        tester,
        serving([
          half(_me, texts: ['si'], atMs: [_callStart], spanMs: [45000]),
          half(_peer, texts: ['estas de acuerdo'], atMs: [_callStart + 30000]),
        ]),
      );

      // The peer's exact 30s word is the earliest placed moment, so it is the
      // zero, and ours reads fifteen seconds later rather than forty-five.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('by 0:15'), findsOneWidget);
      expect(
        find.textContaining('-'),
        findsNothing,
        reason: 'no turn may render before the origin',
      );
    });

    testWidgets('an unvouched turn does not become the zero every other time '
        'is measured from', (tester) async {
      // Every time on screen is a DIFFERENCE from the origin, and a difference
      // is only as sound as both its ends. The peer's older client opens the
      // call and never said how exact its times are; if that turn set the zero,
      // our own exactly timed word would print "0:03" -- an exact-looking stamp
      // measured from a number the same screen says it cannot vouch for, and
      // wrong by however wrong that half was.
      await pump(
        tester,
        serving([
          half(
            _peer,
            texts: ['hola'],
            atMs: [_callStart],
            positionsMarked: false,
          ),
          half(_me, texts: ['que tal'], atMs: [_callStart + 3000]),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      // Both turns are shown, in the order their devices put them.
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('hola'), lessThan(top('que tal')));

      // Our word is the earliest moment anybody vouched for, so it is the zero.
      expect(find.text('0:00'), findsOneWidget);
      expect(
        find.text('0:03'),
        findsNothing,
        reason: 'that stamp would be measured from an unvouched moment',
      );
      // And the peer's turn still shows no time of its own.
      expect(find.textContaining('how exact'), findsOneWidget);
    });

    testWidgets('an unmarked half\'s span is not printed as a bound either', (
      tester,
    ) async {
      // A span from a writer that never characterised its positions is a bound
      // on a number we cannot vouch for. Acting on it to place the turn LATER
      // is safe and is still done; saying "by 0:45" about it would be this app
      // standing behind a claim its writer never made.
      await pump(
        tester,
        serving([
          half(
            _peer,
            texts: ['si'],
            atMs: [_callStart],
            spanMs: [45000],
            positionsMarked: false,
          ),
          half(_me, texts: ['que tal'], atMs: [_callStart + 3000]),
        ]),
      );

      expect(find.text('si'), findsOneWidget);
      expect(find.textContaining('by '), findsNothing);
      // The span still ORDERED it: placed at the end of its chunk, the peer's
      // turn falls after our word rather than before it.
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('que tal'), lessThan(top('si')));
    });

    testWidgets('a call whose times are all exact carries NO timing caveat', (
      tester,
    ) async {
      // The other side of the rule. A caveat that fires on an ordinary call
      // appears on every call and stops meaning anything.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart]),
          half(_peer, texts: ['muy bien'], atMs: [_callStart + 3000]),
        ]),
      );

      expect(find.textContaining('at or before'), findsNothing);
      expect(find.textContaining('how exact'), findsNothing);
    });

    testWidgets('a writer that never said how exact its times are shows none', (
      tester,
    ) async {
      // An older or foreign client. It asserted a moment and never said
      // whether that moment is a word's or a whole chunk's, so printing it
      // would put our confidence behind its silence. The WORDS still show, and
      // the turn keeps the place its device asserted.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola'],
            atMs: [_callStart],
            positionsMarked: false,
          ),
          half(
            _peer,
            texts: ['muy bien'],
            atMs: [_callStart + 3000],
            positionsMarked: false,
          ),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      expect(find.text('hola'), findsOneWidget);
      expect(find.text('muy bien'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
      expect(find.text('0:03'), findsNothing);
      expect(find.textContaining('how exact'), findsOneWidget);
    });

    testWidgets('one unmarked half does not silence the other\'s times', (
      tester,
    ) async {
      // Per HALF, not per call. The peer's older client says nothing about its
      // own times; ours does, and ours are still worth printing.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart]),
          half(
            _peer,
            texts: ['muy bien'],
            atMs: [_callStart + 3000],
            positionsMarked: false,
          ),
        ]),
      );

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:03'), findsNothing);
      expect(find.textContaining('how exact'), findsOneWidget);
    });

    testWidgets('a silent speaker is noted BELOW the conversation', (
      tester,
    ) async {
      // Absent, silent and unreadable are facts about a HALF and have no
      // moment they happened at. Given a place in the timeline they would
      // invent one, at an instant nobody spoke.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart]),
          half(_peer, texts: const [], captured: 0, transcribed: 0),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      expect(find.text('hola'), findsOneWidget);

      final note = find.textContaining('did not say anything');
      expect(note, findsOneWidget);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getTopLeft(find.text('hola')).dy),
        reason:
            'a fact about a half has no moment, so it sits below the '
            'conversation rather than inside it',
      );
    });

    testWidgets('both speakers get their own section', (tester) async {
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola que tal']),
          half(_peer, texts: ['muy bien gracias']),
        ]),
      );

      expect(find.text('hola que tal'), findsOneWidget);
      expect(find.text('muy bien gracias'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('an unresolved peer does not produce a confident empty '
        'transcript', (tester) async {
      // The room is not a direct chat and has no single other member, so the
      // peer cannot be worked out. A half from them is still in the room. It
      // used to be read, discarded as unplaceable, and the call reported as
      // containing nothing -- with the read marked complete.
      final r = Room(
        id: '!c:fakeServer.notExisting',
        client: client,
        summary: RoomSummary.fromJson({
          'm.joined_member_count': 3,
          'm.invited_member_count': 0,
          'm.heroes': <String>[],
        }),
      );
      client.accountData.remove('m.direct');
      for (final id in [_me, _peer, '@third:example.com']) {
        r.setState(
          Event(
            type: EventTypes.RoomMember,
            stateKey: id,
            content: const {'membership': 'join'},
            senderId: id,
            eventId: '\$m-\$id',
            originServerTs: DateTime.now(),
            room: r,
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: CallTranscriptView(
            room: r,
            callKey: _callKey,
            fetcher: serving([
              half(_peer, texts: ['lo dije yo']),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('not known who else was on this call'),
        findsOneWidget,
        reason:
            'the screen admits it could not read all of this call, and says '
            'which of the three reasons it was',
      );
      expect(
        find.textContaining('too much to read'),
        findsNothing,
        reason:
            'the peer is unknown, not the call too long -- a specific wrong '
            'cause is worse than no cause at all',
      );
      expect(find.textContaining('No transcript from'), findsNothing);
      expect(find.textContaining('did not say anything'), findsNothing);
    });

    testWidgets('in an ENCRYPTED room nobody is reported as having said '
        'nothing', (tester) async {
      // Nothing on the relations path decrypts, so every half comes back
      // unreadable and is filtered out. The view must pass the room's
      // encryption down, or the read looks exhausted and both people are told
      // the other was silent.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: CallTranscriptView(
            room: encryptedRoom(),
            callKey: _callKey,
            fetcher: serving(const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No transcript from'), findsNothing);
      expect(find.textContaining('did not say anything'), findsNothing);
      expect(find.textContaining('Nothing could be read'), findsWidgets);
      expect(
        find.textContaining('could not be unlocked'),
        findsOneWidget,
        reason: 'the caveat names encryption, which is the actual cause',
      );
      expect(
        find.textContaining('too much to read'),
        findsNothing,
        reason:
            'this call was not too long; every event came back sealed, and '
            'saying otherwise sends the reader after a length problem that '
            'does not exist',
      );
    });

    testWidgets('a speaker who wrote NO half is not reported as silent', (
      tester,
    ) async {
      // The distinction the whole design rests on. "They said nothing" is a
      // claim about them; "we have no half" is a statement about our read, and
      // presenting the second as the first puts words in nobody's mouth but
      // takes some out of theirs.
      await pump(tester, serving([half(_me)]));

      expect(find.textContaining('No transcript from'), findsOneWidget);
      expect(find.textContaining('did not say anything'), findsNothing);
    });

    testWidgets('a speaker who was SILENT is not reported as missing', (
      tester,
    ) async {
      // The mirror of the test above: an empty half is a real answer, and
      // reading it as "no transcript" would hide that they were there.
      await pump(
        tester,
        serving([
          half(_me),
          half(_peer, texts: const [], captured: 0, transcribed: 0),
        ]),
      );

      expect(find.textContaining('did not say anything'), findsOneWidget);
      expect(find.textContaining('No transcript from'), findsNothing);
    });

    testWidgets('a call OUR trim emptied is not reported as silence', (
      tester,
    ) async {
      // The learner talked; the trim's thresholds -- unvalidated, calibrated on
      // one recording -- found no speech in any chunk, so nothing was ever sent
      // and nothing came back. The half is empty, its accounting is coherent
      // and admits nothing, and the screen used to answer that with a flat "You
      // did not say anything": our own detector's verdict printed as a fact
      // about a person.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: const [],
            captured: 3,
            transcribed: 0,
            suppressed: 3,
          ),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('did not say anything'), findsNothing);
      expect(find.textContaining('No transcript from'), findsNothing);
      // And the cause it does name is ours, not a half we failed to read.
      expect(find.textContaining('sent to be transcribed'), findsOneWidget);
      expect(find.textContaining('Nothing could be read'), findsNothing);
    });

    testWidgets('a microphone that never opened is not a read failure', (
      tester,
    ) async {
      // The writing device refused capture, so there was never any audio. That
      // is a fact about THEIR device, and until this branch existed it read as
      // "nothing could be read", which points whoever chases it at the reader.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: const [],
            captured: 0,
            transcribed: 0,
            captureRefused: true,
          ),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('never opened a microphone'), findsOneWidget);
      expect(find.textContaining('Nothing could be read'), findsNothing);
      expect(find.textContaining('did not say anything'), findsNothing);
    });

    testWidgets('audio captured and then lost is not a read failure', (
      tester,
    ) async {
      // Recorded, then lost before a transcriber saw it. Ours again, and a
      // different sentence from the microphone case because a different device
      // problem is worth chasing.
      await pump(
        tester,
        serving([
          half(_me, texts: const [], captured: 3, transcribed: 0, lost: 3),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('lost before it could be'), findsOneWidget);
      expect(find.textContaining('Nothing could be read'), findsNothing);
      expect(find.textContaining('did not say anything'), findsNothing);
    });

    testWidgets('a half OUR packer emptied is not blamed on reading', (
      tester,
    ) async {
      // One segment whose text alone will not fit, so the packer drops every
      // segment and the half goes out empty and marked truncated. The words
      // existed and were packed out on the WRITING device; the read that
      // followed worked perfectly. Saying nothing could be read from them
      // blames the reader and sends anyone chasing it to the wrong device.
      await pump(tester, serving([await packedToNothing(_me), half(_peer)]));

      expect(find.textContaining('too long to save'), findsOneWidget);
      expect(find.textContaining('Nothing could be read'), findsNothing);
      expect(find.textContaining('did not say anything'), findsNothing);
      expect(find.textContaining('No transcript from'), findsNothing);
    });

    testWidgets('the same half is not blamed on reading UNDER the timeline '
        'either', (tester) async {
      // The other shape of this screen, which asked the same question through
      // its own copy of the ladder. A copy is a place a cause gets added to one
      // site and not the other, which is exactly how this one survived.
      await pump(
        tester,
        serving([
          await packedToNothing(_me),
          half(_peer, texts: ['muy bien'], atMs: [_callStart]),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      expect(find.textContaining('too long to save'), findsOneWidget);
      expect(find.textContaining('Nothing could be read'), findsNothing);
    });

    testWidgets('an empty half OUR reader shortened is still a reading '
        'failure', (tester) async {
      // The half is empty and its accounting is marked truncated -- by US,
      // because a second event from the same sender would not parse. Reading
      // `truncated` off the accounting would call that "too long to save" and
      // hand the writer the blame for our own trim. The cause is asked of
      // `issue`, which ranks our failures ahead of the writer's admissions.
      await pump(
        tester,
        serving([
          half(_me, texts: const [], captured: 0, transcribed: 0),
          MatrixEvent(
            type: 'm.room.message',
            eventId: r'$not-a-transcript',
            senderId: _me,
            originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
            content: const {'body': 'no soy una transcripcion'},
          ),
          half(_peer),
        ]),
      );

      expect(find.textContaining('Nothing could be read'), findsOneWidget);
      expect(find.textContaining('too long to save'), findsNothing);
    });

    testWidgets('a handover whose sibling never wrote SAYS it is short', (
      tester,
    ) async {
      // The scenario end to end, on the screen. One device transcribed its
      // early chunks and discarded its stop-tail believing a sibling held that
      // stretch; the sibling crashed and published nothing. The words that did
      // arrive are shown -- and until this, so was nothing else: the half read
      // as a clean, complete record, with no note at all, over a stretch that
      // exists in no transcript anywhere.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: const ['hola que tal'],
            captured: 3,
            transcribed: 2,
            discarded: 1,
            deviceId: 'PHONE',
          ),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('hola que tal'), findsOneWidget);
      expect(find.textContaining('may be missing'), findsOneWidget);
    });

    testWidgets('and a handover whose sibling HELD the stretch says nothing of '
        'the kind', (tester) async {
      // The other wrong answer. Two devices, one defers its tail to the other,
      // and the transcript is whole -- telling a learner part of it may be
      // missing on every ordinary two-device call would make the note mean
      // nothing by the time it mattered.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: const ['hola que tal'],
            captured: 3,
            transcribed: 2,
            discarded: 1,
            deviceId: 'PHONE',
            discardedSpans: const [
              CaptureSpan(fromMs: _callStart, toMs: _callStart + 4000),
            ],
          ),
          half(
            _me,
            texts: const ['y despues'],
            // Placed INSIDE the handed-over stretch: coverage now needs a
            // transcribed segment there, not just a kept span, since a kept
            // span the sibling's detector suppressed holds no words.
            atMs: const [_callStart + 2000],
            deviceId: 'LAPTOP',
            keptSpans: const [
              CaptureSpan(fromMs: _callStart - 1000, toMs: _callStart + 20000),
            ],
          ),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('may be missing'), findsNothing);
    });

    testWidgets('but a sibling that wrote WITHOUT holding it still says so', (
      tester,
    ) async {
      // The finding, on the screen. The same two devices, and the second one's
      // half is impeccable -- it just recorded a different part of the call. A
      // head-count of devices cleared the discard here and the learner was
      // shown a clean transcript over a stretch nothing holds.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: const ['hola que tal'],
            captured: 3,
            transcribed: 2,
            discarded: 1,
            deviceId: 'PHONE',
            discardedSpans: const [
              CaptureSpan(fromMs: _callStart, toMs: _callStart + 4000),
            ],
          ),
          half(
            _me,
            texts: const ['y despues'],
            deviceId: 'LAPTOP',
            keptSpans: const [
              CaptureSpan(fromMs: _callStart + 30000, toMs: _callStart + 60000),
            ],
          ),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('hola que tal'), findsOneWidget);
      expect(find.textContaining('may be missing'), findsOneWidget);
    });

    testWidgets('a silent speaker whose audio we DID send still reads as '
        'silent', (tester) async {
      // The answer the fix must not destroy. Every chunk went to a provider and
      // came back with no words, so the emptiness is the speaker's own and
      // saying so is what the empty half was written for.
      await pump(
        tester,
        serving([
          half(_me, texts: const [], captured: 3, transcribed: 0),
          half(_peer, texts: const ['muy bien']),
        ]),
      );

      expect(find.textContaining('did not say anything'), findsOneWidget);
      expect(find.textContaining('sent to be transcribed'), findsNothing);
    });

    testWidgets('an incomplete half shows its words AND says it is short', (
      tester,
    ) async {
      // Both, not either: what was captured is worth reading, and presenting
      // it as the whole of what was said is the failure.
      await pump(
        tester,
        serving([
          half(_me, texts: ['lo que alcance a decir'], drainComplete: false),
          half(_peer),
        ]),
      );

      expect(find.text('lo que alcance a decir'), findsOneWidget);
      expect(find.textContaining('may be missing'), findsOneWidget);
    });

    testWidgets('a complete half carries NO caveat', (tester) async {
      // The caveat must not fire on an ordinary transcript, or it would appear
      // on every call and stop meaning anything.
      await pump(tester, serving([half(_me), half(_peer)]));

      expect(find.textContaining('may be missing'), findsNothing);
      expect(find.textContaining('not shown'), findsNothing);
    });

    testWidgets('a half from an undeclared writer is treated as short', (
      tester,
    ) async {
      await pump(
        tester,
        serving([
          half(_me, texts: ['algo'], declared: false),
          half(_peer),
        ]),
      );

      expect(find.text('algo'), findsOneWidget);
      expect(find.textContaining('may be missing'), findsOneWidget);
    });

    testWidgets('a FAILED read is not presented as an empty transcript', (
      tester,
    ) async {
      // A read that failed and a call where nobody spoke look identical on
      // screen unless they are told apart here, and only one of them means
      // there is nothing to see.
      final f = flaky(1, [half(_me), half(_peer)]);
      await pump(tester, f.fetch);

      expect(find.text('Could not load the transcript'), findsOneWidget);
      expect(find.textContaining('did not say anything'), findsNothing);
      expect(find.textContaining('No transcript from'), findsNothing);
    });

    testWidgets('retrying a failed read actually re-reads', (tester) async {
      final f = flaky(1, [
        half(_me, texts: ['llego a la segunda']),
        half(_peer),
      ]);
      await pump(tester, f.fetch);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // Six, not two: `_load` now walks THREE relation types through this
      // same fetcher -- the transcript's, the per-device recordings', and the
      // merged full-call recording's -- so each of the two attempts below (the
      // failed one and the retry) costs three calls rather than one. The count
      // is still exact, not a floor: it is what proves retrying does not ALSO
      // duplicate a call within one attempt.
      expect(f.calls(), 6);
      expect(find.text('llego a la segunda'), findsOneWidget);
      expect(find.text('Could not load the transcript'), findsNothing);
    });

    testWidgets('a read we cut short says so, and does not claim absence', (
      tester,
    ) async {
      // Stopping early is OUR doing. Reporting the half we never looked at as
      // absent would be a lie about another person.
      final events = [
        for (var i = 0; i < kMaxRelationEvents + 5; i++)
          MatrixEvent(
            type: CallTranscriptContent.relType,
            eventId: '\$filler-$i',
            senderId: _me,
            originServerTs: DateTime.fromMillisecondsSinceEpoch(1000 + i),
            content: {
              'call_key': _callKey,
              'segments': [
                {'text': 'relleno $i'},
              ],
              ...const HalfAccounting(
                chunksCaptured: 1,
                chunksTranscribed: 1,
              ).toJson(),
            },
          ),
      ];
      await pump(tester, serving(events));

      // The one case where the length sentence is the TRUE one: this room is
      // not encrypted and its peer is known, so our own ceiling is the only
      // reason anything is missing.
      expect(find.textContaining('too much to read'), findsOneWidget);
      expect(find.textContaining('could not be unlocked'), findsNothing);
      expect(find.textContaining('not known who else'), findsNothing);
      expect(find.textContaining('No transcript from'), findsNothing);
    });
  });

  group('live transcript refresh', () {
    testWidgets(
      'a half that arrives AFTER the initial load is shown live, without a '
      'manual retry',
      (tester) async {
        // P3: the recording-based half is transcribed POST-hangup, so its
        // `pangea.call_transcript` event can land seconds after the call
        // ends -- while the transcript is already open. Before this fix,
        // `initState` read the relations ONCE and nothing subscribed to a
        // later sync for the TRANSCRIPT itself (only the recordings/merged
        // relations already did), so the screen stayed stuck reporting the
        // peer absent until a manual retry.
        var peerHalfArrived = false;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async => (
          chunk: [
            half(_me, texts: const ['hola']),
            if (peerHalfArrived) half(_peer, texts: const ['que tal']),
          ],
          nextBatch: null,
        );

        await pump(tester, fetch);

        // The peer's half has not arrived yet -- reported absent, not silent.
        expect(find.textContaining('No transcript from'), findsOneWidget);
        expect(find.text('que tal'), findsNothing);

        // The peer's half is published; a sync picks it up live.
        peerHalfArrived = true;
        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        await tester.pumpAndSettle();

        // Shown WITHOUT a manual retry. Mutation: never subscribe the
        // transcript to onSync (or skip re-reading it there) -> this stays
        // absent and the test fails.
        expect(find.textContaining('No transcript from'), findsNothing);
        expect(find.text('que tal'), findsOneWidget);
      },
    );

    testWidgets(
      'a second device from a sender who already has a half is still picked '
      'up live',
      (tester) async {
        // Cold-gate finding: an earlier version stopped the live-refresh
        // loop once every sender's arrival was anything other than
        // [HalfArrival.none] -- but a sender's SECOND device can post its
        // own half well after the first, growing
        // [TranscriptHalf.deviceCount] and its segments, and BOTH senders
        // having "arrived" at all says nothing about whether that is still
        // to come. Both halves are present from the start; only the second
        // device is added later.
        var secondDeviceArrived = false;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async => (
          chunk: [
            half(_me, texts: const ['hola'], deviceId: 'PHONE'),
            if (secondDeviceArrived)
              half(_me, texts: const ['tambien esto'], deviceId: 'LAPTOP'),
            half(_peer, texts: const ['que tal']),
          ],
          nextBatch: null,
        );

        await pump(tester, fetch);

        expect(find.text('hola'), findsOneWidget);
        expect(find.text('que tal'), findsOneWidget);
        expect(find.text('tambien esto'), findsNothing);

        // The second device posts AFTER both senders already had a half --
        // exactly the state a "stop once everyone has arrived" gate would
        // treat as terminal.
        secondDeviceArrived = true;
        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        await tester.pumpAndSettle();

        expect(
          find.text('tambien esto'),
          findsOneWidget,
          reason:
              'a second device joining after both sides had already '
              'arrived must still be picked up live',
        );
      },
    );

    testWidgets(
      'a sync that changes nothing leaves an already-shown transcript alone',
      (tester) async {
        // The other half of the live-refresh contract (and the "must not
        // regress an already-present transcript" requirement): a re-read
        // must not blank or re-shimmer a transcript that is already
        // correctly shown just because a sync arrived. Both halves are
        // present from the start and never change.
        await pump(
          tester,
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
          ]),
        );

        expect(find.text('hola'), findsOneWidget);
        expect(find.text('que tal'), findsOneWidget);

        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        // A single frame first, not straight to `pumpAndSettle`: the words
        // must never even MOMENTARILY disappear while the unchanged re-read
        // is in flight -- `pumpAndSettle` alone would hide a one-frame flash
        // to a stale/absent state if the swap logic ever adopted a read
        // before comparing it.
        await tester.pump();
        expect(find.text('hola'), findsOneWidget);
        expect(find.text('que tal'), findsOneWidget);

        await tester.pumpAndSettle();

        expect(find.text('hola'), findsOneWidget);
        expect(find.text('que tal'), findsOneWidget);
        expect(find.textContaining('No transcript from'), findsNothing);
      },
    );
  });

  group('transcriptChanged', () {
    // Real [CallTranscript]s from the real assembly pipeline
    // ([fetchCallTranscript]), not hand-built [TranscriptHalf]s -- the
    // fixtures a hand-built half would need to stay honest (accounting,
    // arrival, issue all derived/interdependent) are exactly what [half]
    // already produces via the writer's own shapes.
    const roomId = '!c:fakeServer.notExisting';

    Future<CallTranscript> read(List<MatrixEvent> events) =>
        fetchCallTranscript(
          fetch: serving(events),
          roomId: roomId,
          callKey: _callKey,
          selfId: _me,
          expectedSenders: const [_me, _peer],
        );

    test('a positionsMarked flip is a change even with identical segments and '
        'issue', () async {
      // Cold-gate counterexample: both reads carry a valid `at_span_ms`
      // (so `issue` is `timesApproximate` either way -- `issue`'s own
      // ordering checks it before `timesUnstated`), and differ ONLY in
      // whether the writer marks its positions. `_timeKindOf` reads
      // `positionsMarked` directly and would print every one of this
      // half's turns as `unstated` for the first read and `atOrBefore`
      // for the second -- a real render difference `issue` alone hides.
      final a = await read([
        half(
          _me,
          texts: const ['hola'],
          atMs: const [1000],
          spanMs: const [500],
          positionsMarked: false,
        ),
        half(_peer, texts: const ['que tal']),
      ]);
      final b = await read([
        half(
          _me,
          texts: const ['hola'],
          atMs: const [1000],
          spanMs: const [500],
        ),
        half(_peer, texts: const ['que tal']),
      ]);

      expect(
        a.halves.firstWhere((h) => h.senderId == _me).issue,
        b.halves.firstWhere((h) => h.senderId == _me).issue,
        reason: 'the counterexample only works if issue agrees either way',
      );
      expect(transcriptChanged(a, b), isTrue);
    });

    test('an identical re-read is not a change', () async {
      final events = [
        half(_me, texts: const ['hola']),
        half(_peer, texts: const ['que tal']),
      ];
      final a = await read(events);
      final b = await read(events);

      expect(transcriptChanged(a, b), isFalse);
    });
  });

  group('two devices, two clocks', () {
    // The SFU's clock when both devices joined -- two seconds before the first
    // word, which is what an ordinary call looks like.
    const sfuJoin = _callStart - 2000;

    /// A device whose wall clock ran [aheadMs] ahead of the SFU's.
    ClockAnchor skewed(int aheadMs) =>
        ClockAnchor(sfuMs: sfuJoin, deviceMs: sfuJoin + aheadMs);

    // The harm, staged exactly. WE speak first, at the call's start. The PEER
    // replies five seconds later. Our device's clock is thirty seconds fast,
    // so our turn is stamped thirty seconds after the call began and the
    // peer's is stamped five -- and the merge, which compares those absolute
    // values, puts the peer's reply before the greeting it answered.
    List<MatrixEvent> exchange({ClockAnchor? mine, ClockAnchor? theirs}) => [
      half(_me, texts: ['hola'], atMs: [_callStart + 30000], anchor: mine),
      half(
        _peer,
        texts: ['muy bien'],
        atMs: [_callStart + 5000],
        anchor: theirs,
      ),
    ];

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('a thirty-second skew no longer reorders the conversation', (
      tester,
    ) async {
      await pump(
        tester,
        serving(exchange(mine: skewed(30000), theirs: skewed(0))),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      // Spoken first, so drawn first -- which is the opposite of what the raw
      // positions say, and the whole point of the anchor.
      expect(top(tester, 'hola'), lessThan(top(tester, 'muy bien')));
      // And the gap between them is the REAL five seconds, not the
      // twenty-five the two clocks' disagreement made of it.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:05'), findsOneWidget);
    });

    testWidgets('a learner two devices read as ONE side of the conversation', (
      tester,
    ) async {
      // The whole change, end to end and on screen. The learner answered on a
      // phone and a laptop, both recorded, and each wrote its own half. Keyed
      // by the account alone one of those two halves was discarded here and
      // the survivor was drawn as the whole of what they said.
      //
      // The two devices' clocks disagree by forty seconds between them, so the
      // raw stamps put the last thing said first. What orders these three
      // turns is the anchor each device wrote at join -- the same correction
      // that already spans two SPEAKERS, applied between one speaker's own
      // devices.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola'],
            atMs: [_callStart + 30000],
            anchor: skewed(30000),
            deviceId: 'PHONE',
          ),
          half(
            _peer,
            texts: ['muy bien'],
            atMs: [_callStart + 5000],
            anchor: skewed(0),
          ),
          half(
            _me,
            texts: ['adios'],
            atMs: [_callStart],
            anchor: skewed(-10000),
            deviceId: 'LAPTOP',
          ),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      // Neither half was dropped: both of the learner's devices are on screen.
      expect(find.text('hola'), findsOneWidget);
      expect(find.text('adios'), findsOneWidget);
      // In the order they were spoken, across all three devices.
      expect(top(tester, 'hola'), lessThan(top(tester, 'muy bien')));
      expect(top(tester, 'muy bien'), lessThan(top(tester, 'adios')));
      // And on the real clock: 0s, 5s, 10s. The raw stamps say 30s, 5s and 0s.
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:05'), findsOneWidget);
      expect(find.text('0:10'), findsOneWidget);
    });

    testWidgets('the same two devices, unanchored, keep every word', (
      tester,
    ) async {
      // What is lost when the clocks cannot be reconciled, kept as a fixture
      // beside the case above. The words are all still here -- no half is
      // discarded, which is the part that matters -- and what is withheld is
      // the ordering claim: no time is printed, because nothing here can say
      // which device's stamp came first.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola'],
            atMs: [_callStart + 30000],
            anchor: null,
            deviceId: 'PHONE',
          ),
          half(
            _me,
            texts: ['adios'],
            atMs: [_callStart],
            anchor: null,
            deviceId: 'LAPTOP',
          ),
        ]),
      );

      expect(find.text('hola'), findsOneWidget);
      expect(find.text('adios'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('the same halves without anchors still read in device order', (
      tester,
    ) async {
      // The defect itself, kept as a fixture. Nothing on these halves says how
      // either clock stood, so there is nothing to correct by and the reader
      // shows what the devices asserted. It is also what proves the test above
      // is exercising the correction rather than agreeing with the raw data.
      await pump(tester, serving(exchange()));

      expect(find.byType(TurnTimeline), findsOneWidget);
      expect(top(tester, 'muy bien'), lessThan(top(tester, 'hola')));
    });

    testWidgets('ONE anchored half corrects nothing, and no longer hides it', (
      tester,
    ) async {
      // All or nothing. Moving our half by thirty seconds while the peer's
      // stays where their device put it changes their relative order on an
      // offset measured for only one of them -- we cannot say whether that
      // helps or harms, so it is not done. That trade is unchanged.
      //
      // What the screen CLAIMS about the result is what changed. This case used
      // to print plain m:ss on both halves: the reply rendered above the
      // question it answered, with two confident timestamps and no warning,
      // while the two clocks stood thirty seconds apart.
      await pump(tester, serving(exchange(mine: skewed(30000))));

      expect(find.byType(TurnTimeline), findsOneWidget);
      // Still the uncorrected order. It is the limitation the caveat now
      // discloses, rather than one this test pins as intended behaviour.
      expect(top(tester, 'muy bien'), lessThan(top(tester, 'hola')));
      // And no time is vouched for. Both ends of a printed difference have to
      // come off one clock, and here they do not.
      expect(find.text('0:00'), findsNothing);
      expect(find.text('0:25'), findsNothing);
      expect(
        find.textContaining('clocks could not be compared'),
        findsOneWidget,
      );
      // NOT the writer's caveat. Both halves said how exact their times are,
      // so explaining the missing times that way would be a confident,
      // specific, wrong diagnosis -- the failure the rest of this screen is
      // built to avoid.
      expect(find.textContaining('how exact'), findsNothing);
    });

    testWidgets('a call with ONE voice on it still shows its times', (
      tester,
    ) async {
      // The scope of the rule, and why it is not simply !clocksReconcilable.
      // Refusing a time needs a SECOND clock to disagree with. A call where
      // only one person spoke has none -- every turn is a difference between
      // two readings of the same device -- so hedging here would silence a
      // whole transcript to guard against a harm that cannot occur.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola', 'que tal'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart, _callStart + 6000],
            anchor: null,
          ),
          half(
            _peer,
            texts: const [],
            captured: 1,
            transcribed: 0,
            anchor: null,
          ),
        ]),
      );

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:06'), findsOneWidget);
      expect(find.textContaining('clocks could not be compared'), findsNothing);
    });

    testWidgets('two clocks that agreed are left alone', (tester) async {
      // The common case, and the one a correction must not make worse. Both
      // devices were in step, so the offsets cancel and the transcript reads
      // exactly as it did before anchors existed.
      await pump(
        tester,
        serving([
          half(_me, texts: ['hola'], atMs: [_callStart], anchor: skewed(400)),
          half(
            _peer,
            texts: ['muy bien'],
            atMs: [_callStart + 5000],
            anchor: skewed(400),
          ),
        ]),
      );

      expect(top(tester, 'hola'), lessThan(top(tester, 'muy bien')));
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:05'), findsOneWidget);
    });

    testWidgets('a half whose own turns are ordered stays ordered', (
      tester,
    ) async {
      // The render gate is answered on the RAW positions and the shift is
      // applied after it. One constant off every position in a half cannot
      // reorder them, so a half the gate accepted must still read forwards.
      await pump(
        tester,
        serving([
          half(
            _me,
            texts: ['hola', 'que tal'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart + 30000, _callStart + 36000],
            anchor: skewed(30000),
          ),
          half(
            _peer,
            texts: ['muy bien'],
            atMs: [_callStart + 3000],
            anchor: skewed(0),
          ),
        ]),
      );

      expect(find.byType(TurnTimeline), findsOneWidget);
      expect(top(tester, 'hola'), lessThan(top(tester, 'muy bien')));
      expect(top(tester, 'muy bien'), lessThan(top(tester, 'que tal')));
    });
  });

  group('callParticipants', () {
    test('is derived locally and cannot be influenced by room content', () {
      expect(callParticipants(me: _me, peerId: _peer).ids, [_peer, _me]);
    });

    test('with no peer known, no claim is made about a second person', () {
      // Honest degradation: showing only our own half says nothing false
      // about anyone. Filling the gap from the card is what let a stranger in.
      expect(callParticipants(me: _me, peerId: null).ids, [_me]);
    });

    test('is stable across reads, so sections do not reorder', () {
      expect(
        callParticipants(me: _me, peerId: _peer).ids,
        callParticipants(me: _me, peerId: _peer).ids,
      );
    });

    test('a known peer is not an answer while our own id is missing', () {
      // The shape the guard asserted but never checked. It asked only whether
      // the PEER was known, over a list built from the peer AND this account,
      // so this combination reported a one-id list as authoritative -- and an
      // authoritative list with no id of ours in it is one assembly may drop
      // OUR OWN half against, with no section, on a read it calls complete.
      final participants = callParticipants(me: null, peerId: _peer);

      expect(participants.ids, [_peer]);
      expect(participants.known, isFalse);
    });

    test('the list and the claim about it cannot disagree', () {
      // Asserted mechanically over every combination rather than at the one
      // case that was wrong. A hand-picked case is what left the other three
      // unchecked, and this list needs BOTH ids whichever one goes missing.
      for (final me in [_me, null]) {
        for (final peer in [_peer, null]) {
          final participants = callParticipants(me: me, peerId: peer);

          expect(
            participants.known,
            participants.ids.length == 2,
            reason:
                'me=$me peer=$peer: the list is an answer only when both '
                'sides of the call are in it',
          );
        }
      }
    });
  });

  group('callPeerOf', () {
    Room roomWith(Map<String, String> members, {bool direct = false}) {
      client.accountData.remove('m.direct');
      if (direct) {
        client.accountData['m.direct'] = BasicEvent(
          type: 'm.direct',
          content: {
            _peer: ['!c:fakeServer.notExisting'],
          },
        );
      }
      final r = Room(id: '!c:fakeServer.notExisting', client: client);
      members.forEach((id, membership) {
        r.setState(
          Event(
            type: EventTypes.RoomMember,
            stateKey: id,
            content: {'membership': membership},
            senderId: id,
            eventId: '\$m-\$id',
            originServerTs: DateTime.now(),
            room: r,
          ),
        );
      });
      return r;
    }

    test('m.direct wins, and survives the peer leaving', () {
      expect(
        callPeerOf(roomWith({_me: 'join', _peer: 'leave'}, direct: true)),
        _peer,
      );
    });

    test('a pair that once had a third person is still a pair', () {
      // This is the case the transcript reader used to give up on: looking
      // only at everyone who was ever here made a current pair ambiguous, so
      // the peer was left out and their real half vanished with no row.
      expect(
        callPeerOf(
          roomWith({_me: 'join', _peer: 'join', '@gone:example.com': 'leave'}),
        ),
        _peer,
      );
    });

    test('a departed peer is still found when nobody else is here', () {
      expect(callPeerOf(roomWith({_me: 'join', _peer: 'leave'})), _peer);
    });

    test('a room that is genuinely not a pair yields nobody', () {
      // Naming the wrong person is worse than naming none, in both consumers.
      expect(
        callPeerOf(
          roomWith({_me: 'join', _peer: 'join', '@third:example.com': 'join'}),
        ),
        isNull,
      );
    });
  });

  group('what an empty half is told to the learner as', () {
    // MECHANICAL over [MissingAudio], because the defect it replaces is one
    // of coverage rather than of logic: `audioDroppedAtCapture` and
    // `audioHeldByAnotherDevice` were both added to [HalfIssue], both ranked in
    // [TranscriptHalf.issue], and neither ever reached a sentence -- so a
    // learner whose device dropped the audio at capture, or handed it to a
    // sibling, was told their words could not be READ. Nothing had read them;
    // nothing had been sent.
    //
    // Written against the enum so that a cause added to it is asserted here
    // without anybody remembering to. The compiler already refuses a
    // non-exhaustive [emptyHalfNote]; this is the other half of the same
    // guarantee, that the branch somebody is forced to write is not just
    // another way of spelling the generic answer.

    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

    /// The half a device writes when [cause] alone emptied it.
    TranscriptHalf emptiedBy(MissingAudio cause) {
      final accounting = HalfAccounting(
        chunksCaptured: 4,
        chunksLost: cause == MissingAudio.lost ? 1 : 0,
        captureDroppedMs: cause == MissingAudio.droppedAtCapture ? 250 : 0,
        chunksDiscarded: cause == MissingAudio.heldForASibling ? 1 : 0,
        chunksSuppressed: cause == MissingAudio.suppressedByUs ? 1 : 0,
        declared: true,
      );
      return assembleTranscript(
        candidates: [
          TranscriptCandidate(
            senderId: _peer,
            originServerTs: 1000,
            segments: const [],
            accounting: accounting,
          ),
        ],
        expectedSenders: [_peer],
      ).halves.single;
    }

    test('every cause gets a sentence of its own', () {
      final said = <MissingAudio, String>{
        for (final cause in MissingAudio.values)
          cause: emptyHalfNote(emptiedBy(cause), 'Ana', l10n),
      };

      for (final entry in said.entries) {
        expect(
          entry.value,
          isNot(l10n.callTranscriptNothingRead('Ana')),
          reason:
              'a half ${entry.key} emptied never reached a reader, so telling '
              'the learner it could not be read blames the wrong device',
        );
        expect(
          entry.value,
          isNot(l10n.callTranscriptSaidNothing('Ana')),
          reason: '${entry.key} is our doing, never the speaker being silent',
        );
      }

      expect(
        said.values.toSet(),
        hasLength(MissingAudio.values.length),
        reason:
            'two causes sharing a sentence sends whoever chases it to one '
            'device for two different problems',
      );
    });

    test('a stretch left to a device that never wrote gets its own', () {
      // The one shape in which this cause reaches an empty half at all: the
      // chunks that WERE sent came back with no words, so the emptiness is not
      // what the discard explains -- and a stretch still went to a device whose
      // half never arrived. Every other empty half that deferred anything is
      // answered by `audioHeldByAnotherDevice` above it.
      final half = assembleTranscript(
        candidates: const [
          TranscriptCandidate(
            senderId: _peer,
            originServerTs: 1000,
            segments: [],
            accounting: HalfAccounting(
              chunksCaptured: 4,
              chunksTranscribed: 2,
              chunksDiscarded: 1,
              declared: true,
            ),
            deviceId: 'PHONE',
          ),
        ],
        expectedSenders: [_peer],
      ).halves.single;

      expect(half.issue, HalfIssue.audioLeftToADeviceThatDidNotHoldIt);
      expect(
        emptyHalfNote(half, 'Ana', l10n),
        l10n.callTranscriptDeviceNeverWrote('Ana'),
      );
      expect(
        emptyHalfNote(half, 'Ana', l10n),
        isNot(l10n.callTranscriptNothingRead('Ana')),
        reason: 'nothing reached a reader to fail at',
      );
      expect(
        l10n.callTranscriptDeviceNeverWrote('Ana'),
        isNot(l10n.callTranscriptHeldByOtherDevice('Ana')),
        reason:
            'a sibling that never wrote and a sibling holding the words are '
            'different things to go and do something about',
      );
    });

    test('a speaker with no subscription is told so, not that it was lost', () {
      final half = assembleTranscript(
        candidates: const [
          TranscriptCandidate(
            senderId: _peer,
            originServerTs: 1000,
            segments: [],
            accounting: HalfAccounting(
              chunksCaptured: 3,
              chunksLost: 3,
              chunksRefusedUnsubscribed: 3,
              declared: true,
            ),
          ),
        ],
        expectedSenders: [_peer],
      ).halves.single;

      expect(
        emptyHalfNote(half, 'Ana', l10n),
        l10n.callTranscriptNotSubscribed('Ana'),
      );
      expect(
        emptyHalfNote(half, 'Ana', l10n),
        isNot(l10n.callTranscriptAudioLost('Ana')),
      );
    });

    test('a speaker we really did record and hear nothing from is silent', () {
      // The answer none of the above may take away. Every chunk went to a
      // provider and came back with no words.
      final silent = assembleTranscript(
        candidates: const [
          TranscriptCandidate(
            senderId: _peer,
            originServerTs: 1000,
            segments: [],
            accounting: HalfAccounting(chunksCaptured: 3, declared: true),
          ),
        ],
        expectedSenders: [_peer],
      ).halves.single;

      expect(
        emptyHalfNote(silent, 'Ana', l10n),
        l10n.callTranscriptSaidNothing('Ana'),
      );
    });
  });

  group('call recordings', () {
    late SharedPreferences store;

    setUpAll(() async {
      // Only the recordings tests below render an `AudioPlayerWidget`, which
      // reaches for `Matrix.of(context)` -- nothing else in this file does.
      SharedPreferences.setMockInitialValues({});
      store = await SharedPreferences.getInstance();
      MatrixState.pangeaController = FakePangeaController();
    });

    Future<void> pumpWithRecordings(
      WidgetTester tester,
      Room testRoom,
      RelationsFetcher fetcher, {
      // Injected only by the load-state tests below, which drive the "Full
      // call" slot's grace clock deterministically rather than waiting 30s.
      CallRecordingsLoadController? loadController,
      // Injected only by the merged-playback tests below, which stand in for
      // the shared AudioPlayer and control WHEN the merged bytes arrive (there
      // is no audio backend or homeserver under `flutter test`).
      AudioPlayer Function()? audioPlayerFactory,
      Future<MatrixFile> Function(CallAudioMergedRecording row)?
      mergedFileLoader,
      // Injected only by the loading-state tests, to place a recording inside or
      // past the "still transcribing" recency window deterministically.
      DateTime Function()? now,
      // Injected only by the on-demand Transcribe / language picker tests
      // (#8792 task 3), standing in for the whole-call transcriber and the
      // picker's language list with plain fake seams.
      WholeCallTranscriber? transcriber,
      List<LanguageModel>? pickerLanguages,
    }) async {
      await tester.pumpWidget(
        _TestMatrix(
          clients: [client],
          store: store,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            // A fresh `UniqueKey` every call, deliberately, even though most
            // callers pump only once. `showCallTranscript` opens a NEW dialog
            // -- and therefore a NEW `CallTranscriptView` -- every time a
            // learner taps a call card; it never stays mounted and gets
            // handed updated `room`/`fetcher` props the way a persistent
            // widget would. `pumpWidget` reconciles against whatever this
            // helper last built, and without a key that differs, Flutter
            // treats two calls with the same widget TYPE at the same
            // position as one widget being UPDATED: it reuses the existing
            // `State` and calls `didUpdateWidget`, never `initState` again --
            // so `_load()` (which only `initState`/`_retry` invoke) never
            // reruns, and a caller pumping a SECOND time with a different
            // `fetcher` silently keeps rendering the FIRST call's data. A
            // fresh key forces the unmount/remount a fresh dialog-open
            // actually is, so a second `pumpWithRecordings` call in one test
            // -- simulating a second load, not a live update of one -- truly
            // re-reads.
            key: UniqueKey(),
            home: CallTranscriptView(
              room: testRoom,
              callKey: _callKey,
              fetcher: fetcher,
              recordingsLoadController: loadController,
              audioPlayerFactory: audioPlayerFactory,
              mergedFileLoader: mergedFileLoader,
              now: now,
              transcriber: transcriber,
              pickerLanguages: pickerLanguages,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The exact [CallTurn]s `_turnsOf` built for the render under test, read
    /// straight off the [TurnTimeline] widget instance rather than re-derived
    /// from rendered text -- `_turnsOf` is private to `transcript_view.dart`
    /// and cannot be called from this file, and [CallTurn.audioStartMs] /
    /// [CallTurn.audioEndMs] / [CallTurn.identityKey] render as no text of
    /// their own yet (later agents consume them for seek/highlight). This is
    /// the same technique the recordings tests above already use for
    /// [AudioPlayerWidget]'s own fields (`players.map((p) => p.senderId)`).
    List<CallTurn> renderedTurns(WidgetTester tester) =>
        tester.widget<TurnTimeline>(find.byType(TurnTimeline)).turns;

    /// The per-device recording rows are collapsed by default behind the
    /// floating Full-call card's chevron (spec section 2/D3: "Full call is the
    /// hero"), so a test that asserts on those rows opens them first.
    Future<void> expandDeviceRows(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
    }

    /// The floating card's MERGED-recording transport. It is no longer a stock
    /// [AudioPlayerWidget] (the per-device rows still are) but the private
    /// custom control that drives karaoke on card-play, so it is found by
    /// runtime type -- the test cannot import a private widget.
    Finder mergedPlayer() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_MergedFullCallControl',
    );

    testWidgets(
      'our OWN RECENT recording without a transcript reads as loading',
      (tester) async {
        // #8808: right after a call our own recording is in the room but its
        // transcript is one event behind. While the recording is RECENT our own
        // half reads as loading, not "No transcript" -- the read is not
        // exhausted while the transcript is still on its way
        // (voice-video-calls.instructions.md). Our audio is present, our
        // transcript half is not, the peer's transcript is present, and `now` is
        // just after the recording's server time. Lives here, not with the
        // absent/silent tests above, because a recording renders an
        // AudioPlayerWidget that needs this group's MatrixState.
        await pumpWithRecordings(
          tester,
          room(),
          servingByType([
            audioEvent(_me),
            half(_peer, texts: const ['hola']),
          ]),
          // audioEvent's server time is epoch 1000ms; place now one minute
          // later, well inside the recency window.
          now: () => DateTime.fromMillisecondsSinceEpoch(1000 + 60 * 1000),
        );

        expect(find.textContaining('Still transcribing'), findsOneWidget);
        expect(find.textContaining('No transcript from'), findsNothing);
      },
    );

    testWidgets(
      'our OWN OLD recording without a transcript settles to "No transcript"',
      (tester) async {
        // The recency bound: with CALL_RECORDING_TRANSCRIPT off the transcript
        // publishes BEFORE the audio and a failed send is never replayed, so an
        // OLD own-recording with no transcript is a publish that never landed.
        // Past the window it must read as the honest "No transcript", never a
        // "still transcribing" that waits forever. Same fixture as above, but
        // `now` is well past the window.
        await pumpWithRecordings(
          tester,
          room(),
          servingByType([
            audioEvent(_me),
            half(_peer, texts: const ['hola']),
          ]),
          // Six minutes after the recording's epoch-1000ms server time -- past
          // the five-minute window.
          now: () => DateTime.fromMillisecondsSinceEpoch(1000 + 6 * 60 * 1000),
        );

        expect(find.textContaining('No transcript from'), findsOneWidget);
        expect(find.textContaining('Still transcribing'), findsNothing);
      },
    );

    testWidgets(
      'a peer recording without a transcript stays "No transcript", not loading',
      (tester) async {
        // The bound the loading state is deliberately given: only OUR OWN half
        // is shown as loading. Our client always posts a transcript after its
        // audio, but a REMOTE could be a foreign/older client that writes audio
        // and never a transcript -- promising "still transcribing" for one that
        // never arrives would be a permanent loading state hiding a real
        // absence. So a peer with a recording but no transcript keeps the honest
        // "No transcript", and no loading row appears.
        await pumpWithRecordings(
          tester,
          room(),
          servingByType([
            half(_me, texts: const ['hola']),
            audioEvent(_peer),
          ]),
        );

        expect(find.textContaining('No transcript from'), findsOneWidget);
        expect(find.textContaining('Still transcribing'), findsNothing);
      },
    );

    testWidgets('N recordings render N players, each labelled by its speaker', (
      tester,
    ) async {
      // Three events, not two: two of this account's OWN devices each
      // wrote their own half (see `CallAudioContent`'s docs -- one event
      // per DEVICE), plus one from the peer. Speaker-counting would say
      // two; this fixture is only satisfied by counting the EVENTS.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me, deviceId: 'PHONE'),
          audioEvent(_me, deviceId: 'LAPTOP'),
          audioEvent(_peer),
        ]),
      );

      // The per-device rows are collapsed behind the floating card's chevron
      // by default; open them to assert on the players. There is no merged
      // recording in this fixture, so the card header itself holds no player.
      await expandDeviceRows(tester);

      final players = tester
          .widgetList<AudioPlayerWidget>(find.byType(AudioPlayerWidget))
          .toList();
      expect(
        players,
        hasLength(3),
        reason: 'one player per pangea.call_audio event, not per speaker',
      );
      expect(
        players.map((p) => p.senderId).toList()..sort(),
        [_me, _me, _peer]..sort(),
        reason: 'each player is wired to whichever device recorded it',
      );

      // The VISIBLE label, not just the wiring. No `atMs` above, so the
      // timeline is not eligible and both halves render as their own
      // `_HalfSection` -- one "You" header and one peer-name header from
      // the transcript itself -- plus one label per recording row: two
      // more "You" rows and one more peer-name row.
      final peerName = testRoom
          .unsafeGetUserFromMemoryOrFallback(_peer)
          .calcDisplayname();
      expect(find.text('You'), findsNWidgets(3));
      expect(find.text(peerName), findsNWidgets(2));
      // Literal, like every other string this file asserts on -- the ARB
      // source of truth is `lib/l10n/intl_en.arb`'s `callTranscriptRecordings`.
      expect(find.text('Recordings'), findsOneWidget);
    });

    testWidgets('each per-device recording row shows its speaker\'s avatar', (
      tester,
    ) async {
      // Change #3: every per-device row carries its speaker's avatar beside the
      // name, so the expanded dropdown reads as a roster rather than a bare
      // list. No merged recording and no `atMs` here, so the only avatars on
      // screen come from the device rows -- the per-speaker `_HalfSection`
      // carries none, and there is no karaoke timeline (whose turns draw their
      // own). Three recordings, three avatars.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me, deviceId: 'PHONE'),
          audioEvent(_me, deviceId: 'LAPTOP'),
          audioEvent(_peer),
        ]),
      );

      // Collapsed by default: the rows -- and their avatars -- are offstage.
      expect(find.byType(Avatar), findsNothing);

      await expandDeviceRows(tester);

      // One avatar per per-device recording row. Mutation: drop the Avatar from
      // `_recordingsSection` -> this finds none.
      expect(
        find.byType(Avatar),
        findsNWidgets(3),
        reason: 'each per-device recording row shows its speaker\'s avatar',
      );
    });

    testWidgets(
      'a call with no pangea.call_audio events shows no Recordings section '
      'at all',
      (tester) async {
        final testRoom = room();
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
          ]),
        );

        expect(
          find.byType(AudioPlayerWidget),
          findsNothing,
          reason: 'most calls carry no recording',
        );
        expect(
          find.text('Recordings'),
          findsNothing,
          reason: 'the empty state is no header at all, not an empty one',
        );
      },
    );

    testWidgets('a two-half call shows the merged "Full call" row FIRST, above '
        'the per-device halves', (tester) async {
      // Two device halves and one merged full-call recording. The merged row
      // is the PRIMARY: it renders first, above the "Recordings" heading that
      // groups the halves, and is keyed by the merged event's OWN id -- not by
      // either half's -- via the same relabel-to-`m.audio` path the halves use.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me, deviceId: 'PHONE'),
          audioEvent(_peer),
          mergedEvent(_me),
        ]),
      );

      // The merged recording is the hero: its player sits in the floating card
      // (keyed by the merged event's own id), and the per-device halves are
      // collapsed behind the card's chevron until the reader opens them.
      expect(
        mergedPlayer(),
        findsOneWidget,
        reason: 'the merged row is the floating card, keyed by its own id',
      );
      expect(find.text('Full call'), findsOneWidget);
      expect(
        find.text('Recordings'),
        findsNothing,
        reason: 'the per-device rows are collapsed by default',
      );

      await expandDeviceRows(tester);

      // Now the two halves show as their own [AudioPlayerWidget]s. The merged
      // bar is the custom control (asserted above via [mergedPlayer]), NOT an
      // AudioPlayerWidget, so only the two per-device rows count here.
      final players = tester
          .widgetList<AudioPlayerWidget>(find.byType(AudioPlayerWidget))
          .toList();
      expect(players, hasLength(2));
      expect(mergedPlayer(), findsOneWidget);
      expect(find.text('Recordings'), findsOneWidget);
      // The Full-call card header sits ABOVE the revealed per-device rows.
      expect(
        tester.getTopLeft(find.text('Full call')).dy,
        lessThan(tester.getTopLeft(find.text('Recordings')).dy),
        reason: 'the merged full-call recording is first, above the halves',
      );
    });

    testWidgets('the merged recording anchors the turn times to its own start', (
      tester,
    ) async {
      // The times a reader sees have to be positions in the Full-call recording
      // beside them: read 0:06, scrub that player to 0:06, hear that turn. The
      // recording began 6s before the first word -- the ring, then the opening
      // silence -- so the first turn sits at 0:06 in it, not 0:00, and the turn
      // 20s in reads 0:20. The origin every printed time is a difference from is
      // the recording's start (which the merged event carries), not the first
      // word. Bare "0:00" is a player's own position label, so the proof is the
      // shifted values themselves and the ABSENCE of the first-word 0:14.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart + 6000]),
          half(_peer, texts: const ['their turn'], atMs: [_callStart + 20000]),
          audioEvent(_me),
          audioEvent(_peer),
          mergedEvent(_me, mergedStartSfuMs: _callStart),
        ]),
      );

      expect(find.text('0:06'), findsOneWidget);
      expect(find.text('0:20'), findsOneWidget);
      // The first-word origin would have placed "their turn" at 0:14; that it is
      // gone is what proves the anchor moved. Revert the re-anchor and 0:06 is
      // absent and 0:14 is back.
      expect(find.text('0:14'), findsNothing);
    });

    testWidgets('with no merged recording the origin stays the first word', (
      tester,
    ) async {
      // The same call minus the merge: nothing to line the times up against, so
      // the origin is the first turn placed, exactly as before -- "their turn"
      // reads 0:14, and the re-anchored 0:20 never appears.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart + 6000]),
          half(_peer, texts: const ['their turn'], atMs: [_callStart + 20000]),
          audioEvent(_me),
          audioEvent(_peer),
        ]),
      );

      expect(find.text('0:14'), findsOneWidget);
      expect(find.text('0:20'), findsNothing);
    });

    testWidgets('a merged start after the first word is refused, times unchanged', (
      tester,
    ) async {
      // A recording that claims to begin AFTER somebody already spoke is
      // malformed; honouring it would push a real turn to a negative time. The
      // origin falls back to the first word, so the times read as with no merge
      // -- "their turn" at 0:14, never the 0:10 an ungated shift would give it.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart + 6000]),
          half(_peer, texts: const ['their turn'], atMs: [_callStart + 20000]),
          audioEvent(_me),
          audioEvent(_peer),
          mergedEvent(_me, mergedStartSfuMs: _callStart + 10000),
        ]),
      );

      expect(find.text('0:14'), findsOneWidget);
      expect(find.text('0:20'), findsNothing);
      expect(find.text('0:10'), findsNothing);
    });

    testWidgets('a call with MORE THAN TWO halves shows no merged row, even '
        'with a merge present', (tester) async {
      // The enforced v1-scope suppression, on the screen. Three device halves
      // means a mid-call device switch (out of v1 scope), so the player shows
      // NO merged row and lists the individual halves -- EVEN THOUGH a stale
      // two-half merge is in the room. The halves are unaffected.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me, deviceId: 'PHONE'),
          audioEvent(_me, deviceId: 'LAPTOP'),
          audioEvent(_peer),
          mergedEvent(_me),
        ]),
      );

      // More than two halves is a mid-call device switch: the merged row is
      // suppressed, so the bar never shows the merged PLAYER (the "Full call"
      // label is the slot's own, always present) -- even though a stale
      // two-half merge is in the room.
      expect(
        mergedPlayer(),
        findsNothing,
        reason: 'more than two halves suppresses the merged row',
      );
      // And the bar shows the "no recording" note IMMEDIATELY, not a
      // "Preparing" shimmer that waits out the full grace for a merge that can
      // never arrive (the v1 suppression is definitive). Mutation: feed the
      // machine the raw half count for a >2-half call -> pendingMerge shimmer
      // -> this fails.
      expect(find.text('No recording of the full call.'), findsOneWidget);
      expect(
        find.byType(ShimmerBox),
        findsNothing,
        reason: 'a suppressed merge is a definite no, not a pending one',
      );
      // The per-device halves are untouched: three players once revealed, none
      // of them the merged one, under the ordinary "Recordings" heading.
      await expandDeviceRows(tester);
      expect(find.text('Recordings'), findsOneWidget);
      final players = tester
          .widgetList<AudioPlayerWidget>(find.byType(AudioPlayerWidget))
          .toList();
      expect(players, hasLength(3));
      expect(
        players.where((p) => p.eventId == r'$merged'),
        isEmpty,
        reason: 'the suppressed merge must not sneak into the halves either',
      );
    });

    testWidgets(
      'CallTurn.at and turn order follow only the pre-existing re-anchor '
      'formula -- the window fields never perturb it',
      (tester) async {
        // The exact scenario `orderKeyMs` exists to fix (see "an answer
        // bounded to a chunk does not jump ahead of its question" above), run
        // three times: no recordings at all, a merged row that declares no
        // start of its own, and a merged row that DOES declare a start.
        //
        // The first two must agree exactly with each other -- neither a
        // recording being absent nor one being present-but-mute about its
        // own start may move a printed time or reorder a turn. The third
        // DELIBERATELY does not agree with the first two: `_turnsOf` already
        // re-anchors `at` to a declared start when one is on screen (see "the
        // merged recording anchors the turn times to its own start" above,
        // and `f39a11d96a`, which predates the window fields entirely). The
        // claim this run actually pins is narrower than "unaffected" -- it is
        // that the WINDOW computation added alongside `audioStartMs`/
        // `audioEndMs` rides on top of that pre-existing re-anchor without
        // perturbing it OR the order, even though both computations now read
        // the same `mergedStartSfuMs` for different purposes.
        final testRoom = room();
        final halves = [
          half(
            _me,
            texts: const ['si'],
            atMs: [_callStart],
            spanMs: const [45000],
          ),
          half(
            _peer,
            texts: const ['estas de acuerdo'],
            atMs: [_callStart + 30000],
          ),
        ];

        await pumpWithRecordings(tester, testRoom, serving(halves));
        // The origin is 'estas de acuerdo''s own exact word (the smaller of
        // the two vouched keys here, since this fixture -- unlike "a turn
        // bounded to a chunk says 'by', and says why" above -- gives the peer
        // only the one utterance), so it prints 0:00 and 'si' prints fifteen
        // seconds later. Both stamps are asserted, not just 'si''s: a defect
        // that moved the PRECISE turn's own `at` while preserving the 15s gap
        // and the order between the two must not read as passing.
        expect(find.text('0:00'), findsOneWidget);
        expect(find.text('by 0:15'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('estas de acuerdo')).dy,
          lessThan(tester.getTopLeft(find.text('si')).dy),
          reason: 'the question must still come before the answer to it',
        );

        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);

        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            ...halves,
            meAudio,
            peerAudio,
            // No mergedStartSfuMs: the origin must fall back to the
            // first-placed turn exactly as it does with no recording at all.
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId, peerAudio.eventId],
            ),
          ]),
        );
        expect(find.text('0:00'), findsOneWidget);
        expect(find.text('by 0:15'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('estas de acuerdo')).dy,
          lessThan(tester.getTopLeft(find.text('si')).dy),
          reason:
              'a merged row being on screen must not perturb the order '
              'either',
        );
        // A no-start merge is not merely inert on `at`/order -- it must not
        // make any turn window-eligible either, since there is no declared
        // origin for the window to be measured from.
        for (final turn in renderedTurns(tester)) {
          expect(
            turn.audioStartMs,
            isNull,
            reason: 'a merge with no declared start makes no turn eligible',
          );
          expect(turn.audioEndMs, isNull);
        }

        // Now WITH a declared start: `at` moves to the recording-relative
        // values -- 'estas de acuerdo' from 0:00 to 0:30, 'si' from 'by 0:15'
        // to 'by 0:45' -- exactly as "the merged recording anchors the turn
        // times to its own start" above already establishes for a call with
        // no window feature at all. What is new on THIS render is that the
        // window fields are ALSO populated, which is what proves the two
        // computations do not interfere with each other.
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            ...halves,
            meAudio,
            peerAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId, peerAudio.eventId],
              mergedStartSfuMs: _callStart,
            ),
          ]),
        );
        expect(
          find.text('0:30'),
          findsOneWidget,
          reason:
              're-anchored to the declared start, exactly as without the '
              'window feature',
        );
        expect(find.text('by 0:45'), findsOneWidget);
        expect(find.text('by 0:15'), findsNothing);
        expect(
          tester.getTopLeft(find.text('estas de acuerdo')).dy,
          lessThan(tester.getTopLeft(find.text('si')).dy),
          reason:
              'the re-anchor moves both times together and reorders '
              'neither turn',
        );
        for (final turn in renderedTurns(tester)) {
          expect(
            turn.audioStartMs,
            isNotNull,
            reason: 'a declared start makes both halves window-eligible',
          );
          expect(turn.audioEndMs, isNotNull);
        }
      },
    );

    testWidgets(
      'the recording-timeline window is computed per turn and clamped to '
      'the recording',
      (tester) async {
        final testRoom = room();
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            // 'early' sits BEFORE the recording's own start -- its raw
            // window would be negative, which must clamp to zero rather than
            // name a negative position to seek to.
            half(
              _me,
              texts: const ['early', 'hello'],
              captured: 2,
              transcribed: 2,
              atMs: [_callStart - 5000, _callStart + 1000],
            ),
            // 'aproximado' is chunk-bounded (a span is present): its window
            // OPENS at its own atMs and only CLOSES at the chunk's end, so
            // start and end differ. 'lateChunk's end runs past the
            // recording's own duration (8000ms, `mergedEvent`'s fixed value)
            // and must clamp down to it rather than name a position past the
            // end of the audio.
            half(
              _peer,
              texts: const ['aproximado', 'lateChunk'],
              captured: 2,
              transcribed: 2,
              atMs: [_callStart + 500, _callStart + 5000],
              spanMs: const [2500, 5000],
            ),
            meAudio,
            peerAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId, peerAudio.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        CallTurn turnFor(String text) =>
            renderedTurns(tester).singleWhere((t) => t.text == text);

        final early = turnFor('early');
        expect(
          early.audioStartMs,
          0,
          reason: 'a negative raw start clamps to 0',
        );
        expect(early.audioEndMs, 0, reason: 'a precise turn: end equals start');

        final hello = turnFor('hello');
        expect(hello.audioStartMs, 3000);
        expect(
          hello.audioEndMs,
          3000,
          reason: 'a precise turn: end equals start',
        );

        final approx = turnFor('aproximado');
        expect(
          approx.audioStartMs,
          2500,
          reason: 'an approximate window opens at atMs, never orderKeyMs',
        );
        expect(
          approx.audioEndMs,
          5000,
          reason: 'and closes at orderKeyMs -- the chunk end, not the estimate',
        );

        final late = turnFor('lateChunk');
        expect(late.audioStartMs, 7000);
        expect(
          late.audioEndMs,
          8000,
          reason:
              'a window end past the recording\'s own duration clamps down '
              'to it',
        );
      },
    );

    testWidgets(
      'the recording-timeline window subtracts the half\'s own clock shift, '
      'not just the recording\'s origin',
      (tester) async {
        // Every fixture above runs its half's own clock exactly on the SFU's
        // -- the default `anchor` moves nothing, see `half`'s own doc -- so
        // the window math's `- entry.shift` term has been silently correct
        // in every one of them, and a version that dropped it would have
        // passed every one too. This half's DEVICE clock runs 3000ms AHEAD
        // of the SFU's -- the ordinary case any real second device is in --
        // so a version missing the shift is provably wrong here.
        final testRoom = room();
        final aheadBy3s = ClockAnchor(
          sfuMs: _callStart - 2000,
          deviceMs: _callStart + 1000,
        );
        final meAudio = audioEvent(_me);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(
              _me,
              texts: const ['exact', 'approx'],
              captured: 2,
              transcribed: 2,
              // Written on the DEVICE's own (fast) clock, exactly as the
              // real writer does -- `atMs`/`spanMs` are never pre-corrected
              // on the wire, see `_turnsOf`'s own doc.
              atMs: [_callStart + 4000, _callStart + 5000],
              spanMs: const [null, 2000],
              anchor: aheadBy3s,
            ),
            meAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        CallTurn turnFor(String text) =>
            renderedTurns(tester).singleWhere((t) => t.text == text);

        // Moved onto the SFU clock first -- device 4000/5000 less the
        // 3000ms the device runs ahead leaves 1000/2000 on the SFU's own
        // clock -- THEN measured from the recording's start, 2000ms before
        // that: 3000/4000. Neither value exceeds the recording's 8000ms
        // duration, so nothing here is also exercising the clamp.
        final exact = turnFor('exact');
        expect(
          exact.audioStartMs,
          3000,
          reason: 'dropping "- entry.shift" would leave this at 6000',
        );
        expect(exact.audioEndMs, 3000, reason: 'a precise turn: end==start');

        final approx = turnFor('approx');
        expect(approx.audioStartMs, 4000);
        expect(
          approx.audioEndMs,
          6000,
          reason: 'the end term subtracts the same shift as the start does',
        );
      },
    );

    testWidgets(
      'an atMs past the recording\'s own duration clamps audioStartMs '
      'itself, not only audioEndMs',
      (tester) async {
        // The "clamped to the recording" fixture above already covers a
        // window whose END runs past `durationMs` while its START is still
        // inside it ('lateChunk'). This is the case that fixture never
        // reaches: the segment's OWN `atMs` -- not just the far side of its
        // span -- lands after the recording stops, so it is `audioStartMs`'s
        // OWN `.clamp(0, windowDurationMs)` that has to catch it, not
        // `audioEndMs`'s.
        final testRoom = room();
        final meAudio = audioEvent(_me);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            // 12000ms into an 8000ms recording (`mergedEvent`'s fixed
            // duration) -- past the end before this segment even opens.
            half(_me, texts: const ['late'], atMs: [_callStart + 12000]),
            meAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId],
              mergedStartSfuMs: _callStart,
            ),
          ]),
        );

        final late = renderedTurns(tester).single;
        expect(
          late.audioStartMs,
          8000,
          reason:
              'a start past the recording\'s own duration clamps down to '
              'it, the same as a start past it only at the far end of its '
              'span',
        );
        expect(late.audioEndMs, 8000);
      },
    );

    testWidgets('with no merged recording at all, no turn carries a window', (
      tester,
    ) async {
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart]),
          half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
        ]),
      );

      for (final turn in renderedTurns(tester)) {
        expect(turn.audioStartMs, isNull);
        expect(turn.audioEndMs, isNull);
      }
    });

    testWidgets(
      'unreconciled clocks null the window even with a merged recording on '
      'screen',
      (tester) async {
        final testRoom = room();
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(_me, texts: const ['hello'], atMs: [_callStart], anchor: null),
            half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
            meAudio,
            peerAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId, peerAudio.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        for (final turn in renderedTurns(tester)) {
          expect(turn.audioStartMs, isNull);
          expect(turn.audioEndMs, isNull);
        }
      },
    );

    testWidgets(
      'a half with no clock anchor of its own gets no window, even alone '
      'on the call',
      (tester) async {
        // `turnsShareOneClock` is TRUE here -- only one voice on the call, so
        // there is no second clock for it to disagree with (see "a call with
        // ONE voice on it still shows its times" above) -- so this is only
        // reachable at all if the window math also checks THIS speaking
        // half's own anchor, separately from that whole-transcript fact.
        // `clockShiftFor` answers zero for an anchorless half exactly as it
        // does for an unreconciled one, so treating that zero as a real shift
        // would print a confident window measured against a clock this half
        // never read.
        final testRoom = room();
        final meAudio = audioEvent(_me);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(_me, texts: const ['hello'], atMs: [_callStart], anchor: null),
            half(
              _peer,
              texts: const [],
              captured: 1,
              transcribed: 0,
              anchor: null,
            ),
            meAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        final hello = renderedTurns(tester).single;
        expect(hello.text, 'hello');
        expect(hello.audioStartMs, isNull);
        expect(hello.audioEndMs, isNull);
      },
    );

    testWidgets(
      'a half whose audio the merge does not name gets no window, even '
      'though its clock is fine',
      (tester) async {
        final testRoom = room();
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(_me, texts: const ['hello'], atMs: [_callStart]),
            half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
            meAudio,
            peerAudio,
            mergedEvent(
              _me,
              // Only OUR OWN recording is named as a source here -- the
              // peer's audio was never mixed into this recording, even though
              // their transcript half is otherwise perfectly reconciled.
              sourceEventIds: [meAudio.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        final turns = renderedTurns(tester);
        final hello = turns.singleWhere((t) => t.text == 'hello');
        final hi = turns.singleWhere((t) => t.text == 'hi');

        expect(hello.audioStartMs, isNotNull);
        expect(
          hi.audioStartMs,
          isNull,
          reason: 'the merge never named this half\'s recording',
        );
        expect(hi.audioEndMs, isNull);
      },
    );

    testWidgets(
      'a sender with two recordings where the merge names only one gets no '
      'window on ANY of their turns',
      (tester) async {
        // The real defect: `CaptureElection`'s own doc describes a
        // convergence race where two of one account's devices can each start
        // capturing before their rosters converge, and an ordinary capture
        // drop-and-rejoin reaches the same shape -- either way this sender
        // ends up with TWO `pangea.call_audio` recordings for one call. When
        // the merge names only one of them there is no per-segment recording
        // id to say which of this sender's SEGMENTS the excluded recording's
        // audio belongs to, so NONE of their turns may claim a window --
        // never one that might be pointing at audio that was never mixed in.
        //
        // TWO turns from the partially-covered sender, not one -- the title
        // says "ANY of their turns", and a fixture that only ever gives that
        // sender a single turn cannot tell "every turn is suppressed" apart
        // from "the one turn this fixture happens to have is suppressed".
        //
        // The peer speaks but uploads no recording of their own, which keeps
        // this fixture's TOTAL recording count at two. A third recording here
        // would also trip `selectMergedRow`'s unrelated more-than-two-halves
        // v1-scope suppression (`call_audio_merged_selection.dart`) and
        // suppress the merged row entirely -- a different rule, already
        // exercised elsewhere, and not what this test is pinning.
        final testRoom = room();
        final mePhone = audioEvent(_me, deviceId: 'PHONE');
        final meLaptop = audioEvent(_me, deviceId: 'LAPTOP');
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(
              _me,
              texts: const ['hello', 'again'],
              captured: 2,
              transcribed: 2,
              atMs: [_callStart, _callStart + 3000],
            ),
            half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
            mePhone,
            meLaptop,
            mergedEvent(
              _me,
              // Only the phone's recording is named -- the laptop's is not.
              sourceEventIds: [mePhone.eventId],
              mergedStartSfuMs: _callStart - 2000,
            ),
          ]),
        );

        final turns = renderedTurns(tester);
        final hello = turns.singleWhere((t) => t.text == 'hello');
        final again = turns.singleWhere((t) => t.text == 'again');
        final hi = turns.singleWhere((t) => t.text == 'hi');

        for (final turn in [hello, again]) {
          expect(
            turn.audioStartMs,
            isNull,
            reason:
                'one of this sender\'s two recordings is absent from the '
                'merge, so NONE of their turns -- not just the first --  '
                'may window into it',
          );
          expect(turn.audioEndMs, isNull);
        }
        expect(
          hi.audioStartMs,
          isNull,
          reason:
              'a separate, already-correct rule: the peer uploaded no '
              'recording of their own at all, so they were never covered '
              'either',
        );
        expect(hi.audioEndMs, isNull);
      },
    );

    testWidgets('a sender with two recordings where the merge names BOTH stays '
        'window-eligible', (tester) async {
      // The other side of the same rule, pinned separately so a fix that
      // over-corrects -- requiring exactly one recording, say -- would show
      // up here rather than hiding behind the single-recording coverage
      // every other window test in this file already exercises.
      final testRoom = room();
      final mePhone = audioEvent(_me, deviceId: 'PHONE');
      final meLaptop = audioEvent(_me, deviceId: 'LAPTOP');
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart]),
          mePhone,
          meLaptop,
          mergedEvent(
            _me,
            sourceEventIds: [mePhone.eventId, meLaptop.eventId],
            mergedStartSfuMs: _callStart - 2000,
          ),
        ]),
      );

      final hello = renderedTurns(tester).single;
      expect(
        hello.audioStartMs,
        isNotNull,
        reason: 'every one of this sender\'s recordings is named',
      );
      expect(hello.audioEndMs, isNotNull);
    });

    testWidgets(
      'no two turns in a transcript share an identityKey, even when one '
      'sender contributes from two devices',
      (tester) async {
        // The shape `CallTurn.identityKey` exists for: one account, two
        // devices, both recorded and both transcribed -- see "a learner two
        // devices read as ONE side of the conversation" above, which
        // establishes that BOTH of this sender's turns survive assembly
        // under the ONE senderId `assembleTranscript` gives them.
        final testRoom = room();
        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            half(
              _me,
              texts: const ['hola'],
              atMs: [_callStart],
              deviceId: 'PHONE',
            ),
            half(_peer, texts: const ['muy bien'], atMs: [_callStart + 3000]),
            half(
              _me,
              texts: const ['adios'],
              atMs: [_callStart + 6000],
              deviceId: 'LAPTOP',
            ),
          ]),
        );

        final turns = renderedTurns(tester);
        expect(turns, hasLength(3));
        expect(
          turns.map((t) => t.identityKey).toSet(),
          hasLength(3),
          reason:
              'one sender wrote from two devices, and their turns must not '
              'collide just because they share a senderId',
        );
      },
    );

    testWidgets(
      'identityKey survives a second device\'s half joining the same sender '
      'between loads',
      (tester) async {
        // `CallTranscriptView` reads a FINISHED call's transcript once per
        // dialog-open (see `showCallTranscript`'s own doc) and has no
        // live-update path that mutates a half's segment list mid-view, so
        // the exact scenario this guards against -- a late half arriving and
        // shifting an existing segment's INDEX within its (already
        // device-merged) half -- is not reachable today. The key is still
        // built to survive it as cheap insurance against a future
        // live-update path, and the only way to prove that with REAL data is
        // a second DEVICE of the same sender whose one segment sits EARLIER
        // than both of the first device's: `_assembleDevices`
        // (`transcript_assembly.dart`) merges several devices' segments by
        // PLACING them on the shared clock, not by concatenating them (see
        // its own `ordered.sort`), so the new segment is inserted at the
        // FRONT of the merged list and the other two shift down by one
        // index -- a real, reachable case, unlike hand-editing one event's
        // content between two loads (which a homeserver would never permit;
        // Matrix events are immutable, and a genuinely later segment always
        // arrives as a new event).
        //
        // `identityKey` is meant to be a pure function of a segment's OWN
        // content, so two loads of "the same" segment are the right way to
        // ask whether its key moved -- whether or not the two loads share
        // one `State`.
        final testRoom = room();
        final phone = half(
          _me,
          texts: const ['hola', 'adios'],
          captured: 2,
          transcribed: 2,
          atMs: [_callStart, _callStart + 5000],
          deviceId: 'PHONE',
        );

        await pumpWithRecordings(tester, testRoom, serving([phone]));
        final before = {
          for (final turn in renderedTurns(tester)) turn.text: turn.identityKey,
        };

        await pumpWithRecordings(
          tester,
          testRoom,
          serving([
            phone,
            half(
              _me,
              texts: const ['early'],
              captured: 1,
              transcribed: 1,
              atMs: [_callStart - 5000],
              deviceId: 'LAPTOP',
            ),
          ]),
        );
        final afterTurns = renderedTurns(tester);
        final after = {
          for (final turn in afterTurns) turn.text: turn.identityKey,
        };

        // Pins the premise the rest of this test leans on: 'early' must have
        // actually landed AHEAD of 'hola'/'adios' in the half's own segment
        // list, which is what shifts their INDEX and is the only reason an
        // index-based key would have moved. Without this, an assembly that
        // instead APPENDED 'early' to the end would leave 'hola'/'adios' at
        // their original indices, and the old, buggy `senderId#index` key
        // would pass the two equality checks below for the wrong reason --
        // never having been exercised at all.
        expect(
          afterTurns.map((t) => t.text).toList(),
          ['early', 'hola', 'adios'],
          reason:
              '_assembleDevices places the second device\'s earlier segment '
              'at the FRONT of the merged list, not at the end',
        );
        expect(
          after.keys,
          containsAll(['early', 'hola', 'adios']),
          reason: 'the second device\'s segment must still render as a turn',
        );
        expect(
          after['hola'],
          before['hola'],
          reason:
              'the merge moved "hola" from index 0 to 1; its identity must '
              'not have moved with it',
        );
        expect(
          after['adios'],
          before['adios'],
          reason: 'the same, one position further down the merged list',
        );
        expect(
          after.values.toSet(),
          hasLength(3),
          reason:
              '"early" still needs its own key, distinct from the two it '
              'now sits in front of',
        );
      },
    );

    testWidgets('two segments with identical content in one half still get '
        'DIFFERENT identityKeys', (tester) async {
      // Content alone is not injective either: an approximate "yes", a
      // pause, then another "yes" can both be estimated to the identical
      // chunk, so two genuinely distinct turns can share senderId, atMs,
      // spanMs AND text all at once. `identityKey` keys a `GlobalKey`
      // (build step 3's karaoke auto-scroll/highlight), and two widgets
      // sharing one `GlobalKey` throws -- so this has to resolve to two
      // distinct keys even though nothing about their CONTENT tells them
      // apart.
      final testRoom = room();
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(
            _me,
            texts: const ['yes', 'yes'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart, _callStart],
          ),
        ]),
      );

      final turns = renderedTurns(tester);
      expect(turns, hasLength(2));
      expect(
        turns.map((t) => t.identityKey).toSet(),
        hasLength(2),
        reason:
            'two genuinely distinct turns must not collide just because '
            'they share every content field',
      );
    });

    testWidgets('identityKey ordinals continue past two duplicates, and the '
        'duplicate group\'s key set does not drift across a rebuild that '
        'inserts unrelated content', (tester) async {
      // Closes two gaps the two-duplicate test above leaves open on its
      // own: (a) it only ever proves ordinals 0 and 1 differ, never that a
      // THIRD occurrence keeps counting rather than colliding back onto an
      // earlier one; (b) it never rebuilds, so it cannot show the
      // duplicate group's ordinals come out the SAME way twice rather than
      // drifting (accumulating) across builds -- which is what would
      // happen if the ordinal counter were ever hoisted out of [_turnsOf]
      // into persistent State instead of a fresh local `Map` per call.
      //
      // Deliberately NOT claimed: that any ONE of the three 'yes'
      // segments keeps "its own" ordinal across the rebuild. That is
      // undefined for content-identical segments -- nothing observable
      // (not even `identityKey` itself) distinguishes "the first yes"
      // from "the second" once they are equal in every field, so there is
      // no experiment that could tell three duplicates apart before and
      // after to check which one moved. What IS real and worth pinning:
      // the SAME three-element key set comes out both times, proving the
      // map starts fresh each build rather than carrying a count forward
      // from the last one (which would instead print `#3`, `#4`, `#5` the
      // second time).
      final testRoom = room();
      final phone = half(
        _me,
        texts: const ['yes', 'yes', 'yes'],
        captured: 3,
        transcribed: 3,
        atMs: [_callStart, _callStart, _callStart],
        deviceId: 'PHONE',
      );

      await pumpWithRecordings(tester, testRoom, serving([phone]));
      final beforeYesKeys = [
        for (final turn in renderedTurns(tester))
          if (turn.text == 'yes') turn.identityKey,
      ];
      expect(
        beforeYesKeys,
        hasLength(3),
        reason: 'all three duplicates must still render as their own turn',
      );
      expect(
        beforeYesKeys.toSet(),
        hasLength(3),
        reason:
            'a third duplicate must get its own ordinal, not collide '
            'back onto the first or second',
      );

      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          phone,
          // A second device, one segment, EARLIER than all three
          // duplicates -- `_assembleDevices` places it at the FRONT of the
          // merged list (see "identityKey survives a second device's half
          // joining..." above).
          half(
            _me,
            texts: const ['early'],
            atMs: [_callStart - 5000],
            deviceId: 'LAPTOP',
          ),
        ]),
      );
      final afterTurns = renderedTurns(tester);

      // Pins that the rebuild actually took effect, rather than trusting
      // the assertions below to fail some OTHER way if the second pump
      // silently kept rendering the first call's data or assembly dropped
      // the laptop half: exactly one new turn, and it leads the other
      // three -- the same "inserted at the FRONT" premise the existing
      // second-device test above pins for non-duplicate content.
      expect(
        afterTurns,
        hasLength(4),
        reason: 'the second device\'s "early" segment must also render',
      );
      expect(afterTurns.where((t) => t.text == 'early'), hasLength(1));
      expect(
        afterTurns.first.text,
        'early',
        reason:
            '_assembleDevices places the earlier second-device segment '
            'at the FRONT of the merged list, ahead of all three '
            'duplicates',
      );

      final afterYesKeys = [
        for (final turn in afterTurns)
          if (turn.text == 'yes') turn.identityKey,
      ];
      // SET equality, deliberately not List equality: this claims exactly
      // what the doc comment above claims and no more. Nothing observable
      // ties a particular ordinal to a particular one of the three
      // content-identical segments, so a hypothetical merge that validly
      // reordered them relative to each other -- while still assigning the
      // same {#0, #1, #2} as a group -- would be a fact about
      // `_assembleDevices`'s ordering, not a defect in `identityKey`, and
      // must not fail this test.
      expect(
        afterYesKeys.toSet(),
        beforeYesKeys.toSet(),
        reason:
            'the duplicate group\'s key SET must come out identical both '
            'times -- {#0, #1, #2} again, not {#3, #4, #5} -- proving the '
            'ordinal counter is a fresh map per build rather than state '
            'that accumulates across one',
      );
      expect(
        afterTurns.map((t) => t.identityKey).toSet(),
        hasLength(afterTurns.length),
        reason:
            'the new "early" turn must still get its own distinct key '
            'alongside the three duplicates',
      );
    });

    // ---- The pinned "Full call" slot's load states (spec section 3) -------

    testWidgets(
      'the floating card shows a shimmer while the reads are in flight',
      (tester) async {
        // The transcript resolves so the body renders, but the recordings and
        // merged reads never land -- so the bar is stuck LOADING, which is a
        // shimmer with no "Preparing" caption (that is pendingMerge's).
        RelationsFetcher transcriptOnly(List<MatrixEvent> transcript) =>
            ({
              required String roomId,
              required String eventId,
              required String relType,
              String? from,
            }) {
              if (relType == CallTranscriptContent.relType) {
                return Future.value((chunk: transcript, nextBatch: null));
              }
              // The audio reads hang, holding the machine in `loading`.
              return Completer<({List<MatrixEvent> chunk, String? nextBatch})>()
                  .future;
            };

        await pumpWithRecordings(
          tester,
          room(),
          transcriptOnly([
            half(_me, texts: const ['hola']),
          ]),
        );

        expect(find.byType(ShimmerBox), findsOneWidget);
        expect(find.byType(AudioPlayerWidget), findsNothing);
        expect(find.text('Preparing the full recording…'), findsNothing);
        expect(find.text('No recording of the full call.'), findsNothing);
      },
    );

    testWidgets(
      'the floating card shows a "preparing" shimmer while a merge is still '
      'pending',
      (tester) async {
        // Reads done, a half present, no merge yet, grace not elapsed:
        // pendingMerge -> shimmer WITH the "Preparing" caption.
        await pumpWithRecordings(
          tester,
          room(),
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
            audioEvent(_me),
            audioEvent(_peer),
          ]),
        );

        expect(find.byType(ShimmerBox), findsOneWidget);
        expect(find.text('Preparing the full recording…'), findsOneWidget);
        expect(mergedPlayer(), findsNothing);
      },
    );

    testWidgets('the floating card shows the merged player when ready', (
      tester,
    ) async {
      final meAudio = audioEvent(_me);
      final peerAudio = audioEvent(_peer);
      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          meAudio,
          peerAudio,
          mergedEvent(
            _me,
            sourceEventIds: [meAudio.eventId, peerAudio.eventId],
          ),
        ]),
      );

      expect(mergedPlayer(), findsOneWidget);
      expect(find.byType(ShimmerBox), findsNothing);
      expect(find.text('No recording of the full call.'), findsNothing);
    });

    testWidgets('the floating card shows the "no recording" note when there is '
        'none, without a retry', (tester) async {
      // Zero halves: nothing is coming, so the note shows IMMEDIATELY and
      // offers no retry (spec section 3's NONE bullet).
      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
        ]),
      );

      expect(find.text('No recording of the full call.'), findsOneWidget);
      expect(find.byType(ShimmerBox), findsNothing);
      expect(find.byType(AudioPlayerWidget), findsNothing);
      expect(
        find.widgetWithText(TextButton, 'Try again'),
        findsNothing,
        reason: 'none offers no retry -- nothing is coming',
      );
    });

    testWidgets('the floating card shows the note WITH a retry once the grace '
        'has elapsed', (tester) async {
      // A half present, no merge, and the grace run out -> unavailable: the
      // note plus a retry. The grace clock is injected so the ~30s window is
      // elapsed deterministically rather than waited out.
      var elapsed = Duration.zero;
      final controller = CallRecordingsLoadController(
        elapsed: () => elapsed,
        // The captured callback is never fired here; the test drives the
        // transition with a fresh `update` once the clock is past the grace.
        // The returned timer fires a harmless no-op and is cancelled on
        // dispose, so nothing is left pending.
        scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
      );

      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me),
          audioEvent(_peer),
        ]),
        loadController: controller,
      );

      // The reads landed while the clock read zero, stamping the grace start
      // there; it is pendingMerge until the grace elapses.
      expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

      elapsed = kCallMergeGrace + const Duration(seconds: 1);
      controller.update(readsInFlight: false, halfCount: 2, hasMerge: false);
      await tester.pumpAndSettle();

      expect(controller.state.value, CallRecordingsLoadState.unavailable);
      expect(find.text('No recording of the full call.'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Try again'),
        findsOneWidget,
        reason: 'unavailable offers a retry',
      );
    });

    testWidgets('the chevron expands and collapses the per-device rows', (
      tester,
    ) async {
      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hola']),
          half(_peer, texts: const ['que tal']),
          audioEvent(_me),
          audioEvent(_peer),
        ]),
      );

      // Collapsed by default: no "Recordings" heading, no per-device players.
      expect(find.text('Recordings'), findsNothing);
      expect(find.byType(AudioPlayerWidget), findsNothing);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.text('Recordings'), findsOneWidget);
      expect(find.byType(AudioPlayerWidget), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      expect(find.text('Recordings'), findsNothing);
      expect(find.byType(AudioPlayerWidget), findsNothing);

      // Collapse HIDES the rows without unmounting them: the two per-device
      // players are still in the tree (offstage), so they are never disposed
      // -- which is what stops the collapse from leaking their shared-player
      // listeners or clearing ownership mid-unmount. Mutation: collapse to
      // `SizedBox.shrink()` instead of `Offstage` -> this finds 0.
      expect(
        find.byType(AudioPlayerWidget, skipOffstage: false),
        findsNWidgets(2),
        reason: 'collapsed rows stay mounted (offstage), never disposed',
      );
    });

    // ---- Karaoke wiring (spec section 4) ----------------------------------

    testWidgets('with a merged recording the timeline is wired for karaoke, '
        'and tapping a turn seeks it', (tester) async {
      final testRoom = room();
      final meAudio = audioEvent(_me);
      final peerAudio = audioEvent(_peer);
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart + 6000]),
          half(_peer, texts: const ['their turn'], atMs: [_callStart + 20000]),
          meAudio,
          peerAudio,
          mergedEvent(
            _me,
            sourceEventIds: [meAudio.eventId, peerAudio.eventId],
            mergedStartSfuMs: _callStart,
          ),
        ]),
      );

      // The timeline is handed a live controller's outputs, not the null
      // gate: highlight, playing state and seek are all wired.
      final timeline = tester.widget<TurnTimeline>(find.byType(TurnTimeline));
      expect(timeline.activeIndex, isNotNull);
      expect(timeline.isPlaying, isNotNull);
      expect(timeline.onSeekTurn, isNotNull);

      final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
      // Capture the FIRST ownership the tap claims. The seek claims the merged
      // event synchronously (before its own load), but the load then FAILS in
      // this homeserver-less test, which releases ownership again -- so the
      // durable proof the seek fired is the claim itself, recorded the instant
      // it happens rather than read after the fact.
      String? claimedByTap;
      matrixState.voiceMessageEventId.addListener(() {
        claimedByTap ??= matrixState.voiceMessageEventId.value;
      });
      expect(matrixState.voiceMessageEventId.value, isNot(r'$merged'));

      await tester.tap(find.text('0:06'));
      await tester.pumpAndSettle();

      expect(
        claimedByTap,
        r'$merged',
        reason: 'the seek claimed the shared player for the merged recording',
      );

      // The failed load already released ownership and disposed the player it
      // created, so nothing is left pending; belt-and-suspenders in case a
      // future change leaves it owned.
      matrixState.audioPlayer?.dispose();
      matrixState.audioPlayer = null;
      matrixState.voiceMessageEventId.value = null;
      await tester.pumpAndSettle();
    });

    testWidgets('the timeline and the karaoke controller share ONE turn order '
        '(interleaved speakers), so highlight/seek index the same turn', (
      tester,
    ) async {
      // `_turnsOf` yields turns GROUPED by half, but TurnTimeline renders them
      // sorted by time and its activeIndex/onSeekTurn are indices into THAT
      // order. The integration must sort ONCE and hand the same list to both
      // the controller and the timeline; otherwise an interleaved conversation
      // highlights and seeks the wrong turn. Two speakers whose turns
      // interleave in time but not by half: me speaks first and last, the peer
      // in between.
      final testRoom = room();
      final meAudio = audioEvent(_me);
      final peerAudio = audioEvent(_peer);
      await pumpWithRecordings(
        tester,
        testRoom,
        serving([
          half(
            _me,
            texts: const ['first', 'third'],
            captured: 2,
            transcribed: 2,
            atMs: [_callStart, _callStart + 20000],
          ),
          half(_peer, texts: const ['second'], atMs: [_callStart + 10000]),
          meAudio,
          peerAudio,
          mergedEvent(
            _me,
            sourceEventIds: [meAudio.eventId, peerAudio.eventId],
            mergedStartSfuMs: _callStart,
          ),
        ]),
      );

      // The list handed to TurnTimeline (and, identically, to the controller)
      // is time-sorted, NOT half-grouped. Mutation: drop the sort in
      // `_syncPlayback`/build and this reads ['first','third','second'].
      expect(
        renderedTurns(tester).map((t) => t.text).toList(),
        ['first', 'second', 'third'],
        reason:
            'the controller and the timeline must index the SAME '
            'time-sorted order, not the speaker-grouped one',
      );
    });

    testWidgets('with no merged recording the timeline is NOT wired for '
        'karaoke -- it renders exactly as today', (tester) async {
      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart]),
          half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
        ]),
      );

      final timeline = tester.widget<TurnTimeline>(find.byType(TurnTimeline));
      expect(
        timeline.activeIndex,
        isNull,
        reason: 'the master gate is null with no merged recording on screen',
      );
      expect(timeline.isPlaying, isNull);
      expect(timeline.onSeekTurn, isNull);
    });

    testWidgets('the load controller is disposed when the dialog closes', (
      tester,
    ) async {
      final controller = CallRecordingsLoadController();
      final meAudio = audioEvent(_me);
      final peerAudio = audioEvent(_peer);
      await pumpWithRecordings(
        tester,
        room(),
        serving([
          half(_me, texts: const ['hello'], atMs: [_callStart]),
          half(_peer, texts: const ['hi'], atMs: [_callStart + 1000]),
          meAudio,
          peerAudio,
          mergedEvent(
            _me,
            sourceEventIds: [meAudio.eventId, peerAudio.eventId],
            mergedStartSfuMs: _callStart,
          ),
        ]),
        loadController: controller,
      );

      // A merged row is on screen, so BOTH the load controller and the
      // playback controller are live. Closing the dialog runs the state's
      // dispose, which tears the playback controller down (its own disposal is
      // unit-tested) and then disposes this load controller.
      expect(controller.state.value, CallRecordingsLoadState.ready);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(
        () => controller.state.addListener(() {}),
        throwsA(anything),
        reason: 'a disposed ValueNotifier rejects new listeners',
      );
    });

    // ---- Bar-play drives karaoke, and the merged-playback lifecycle ---------

    /// The merged-playback fixture used by the bar-play / lifecycle tests: two
    /// timeline-eligible turns whose audio windows sit INSIDE the merge's 8s
    /// duration (so neither clamps), plus the two source recordings and the
    /// merge covering both.
    List<MatrixEvent> karaokeFixture(
      MatrixEvent meAudio,
      MatrixEvent peerAudio,
    ) => [
      half(_me, texts: const ['hello'], atMs: [_callStart + 1000]),
      half(_peer, texts: const ['their turn'], atMs: [_callStart + 5000]),
      meAudio,
      peerAudio,
      mergedEvent(
        _me,
        sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        mergedStartSfuMs: _callStart,
      ),
    ];

    MatrixFile emptyMergedFile() =>
        MatrixFile(bytes: Uint8List(0), name: 'm.wav', mimeType: 'audio/wav');

    testWidgets(
      'pressing the Full-call card play drives the karaoke highlight, and '
      'pause pauses -- with no prior turn tap',
      (tester) async {
        // The owner-decided behaviour (F4a): the bar's OWN play must drive
        // karaoke. A stock AudioPlayerWidget could not (it creates its player
        // only after an async download this widget cannot observe), so the bar
        // is a custom control whose play routes through the transcript's
        // merged-playback path -- claiming ownership and attaching observation
        // SYNCHRONOUSLY.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        // The load's bytes are gated on this completer: while it is pending the
        // download hangs -- but ownership is claimed and observation ATTACHED
        // synchronously first (before the await), which is exactly the part
        // under test. It is deliberately NOT pumpAndSettle-d: the pending
        // download shows an indeterminate spinner that never settles, and the
        // temp-file write it does on completion is real dart:io async.
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        // The bar shows the custom control, and nothing is highlighted yet.
        expect(mergedPlayer(), findsOneWidget);
        TurnTimeline timeline() =>
            tester.widget<TurnTimeline>(find.byType(TurnTimeline));
        expect(timeline().activeIndex!.value, isNull);

        // Press the bar's OWN play button -- no turn was ever tapped. This runs
        // `_startMergedPlayer`'s synchronous prefix in the (fake-async) test
        // zone: it claims ownership and attaches observation, then suspends on
        // the pending download.
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();

        // Observation is attached, so a faked position past 'their turn' (5s)
        // makes the controller resolve its active index: the highlight FOLLOWS
        // the recording -- a bar-started playback drives karaoke. Mutation: drop
        // `_attachObservation` in `_startMergedPlayer` -> activeIndex stays null
        // and this fails.
        fake.emitPosition(const Duration(milliseconds: 6000));
        await tester.pump();
        expect(
          timeline().activeIndex!.value,
          1,
          reason:
              'bar-started playback drives the highlight to the playing turn',
        );

        // And it moves BACK with the position, proving it is following, not a
        // one-shot.
        fake.emitPosition(const Duration(milliseconds: 1500));
        await tester.pump();
        expect(timeline().activeIndex!.value, 0);

        // Let the download finish so playback actually starts (its temp-file
        // write is real dart:io async, which only advances under runAsync);
        // interleave fake-async flushes until the control shows a pause
        // affordance.
        loader.complete(emptyMergedFile());
        for (
          var i = 0;
          i < 20 && find.byIcon(Icons.pause_circle).evaluate().isEmpty;
          i++
        ) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pump();
        expect(find.byIcon(Icons.pause_circle), findsOneWidget);

        // Tapping the pause affordance pauses the shared player.
        await tester.tap(find.byIcon(Icons.pause_circle));
        await tester.pump();
        expect(fake.pauseCount, greaterThan(0));

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a merge arriving AFTER the initial load flips the bar shimmer to the '
      'player on a sync, without a manual retry',
      (tester) async {
        // F5: live auto-refresh. initState reads the relations once; without a
        // sync subscription a merge that lands after the screen opened would sit
        // in the pendingMerge shimmer until the grace expired, then flip to a
        // FALSE "No recording" + retry.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        var mergePresent = false;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async {
          if (relType == CallTranscriptContent.relType) {
            return (
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            );
          }
          if (relType == CallAudioContent.relType) {
            return (chunk: [meAudio, peerAudio], nextBatch: null);
          }
          return (
            chunk: mergePresent ? [merged] : <MatrixEvent>[],
            nextBatch: null,
          );
        }

        // A frozen clock (grace never elapses on its own) so this test isolates
        // the merge-arrival flip from the grace timeout.
        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Reads landed: two halves, no merge yet -> pendingMerge shimmer.
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);
        expect(find.byType(ShimmerBox), findsOneWidget);
        expect(mergedPlayer(), findsNothing);

        // The merge is published; a sync picks it up live.
        mergePresent = true;
        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        await tester.pumpAndSettle();

        // The bar flipped to the player, WITHOUT a manual retry. Mutation: never
        // subscribe to onSync (or re-read on it) -> stays on the shimmer.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
        expect(find.byType(ShimmerBox), findsNothing);
        expect(find.widgetWithText(TextButton, 'Try again'), findsNothing);
      },
    );

    testWidgets('a no-merge sync mid-grace does NOT extend the deadline', (
      tester,
    ) async {
      // F5: the earlier live-refresh raced because it re-ran `_load`, which
      // re-stamps `readsInFlight: true` and RESETS the grace each sync -- so
      // under steady traffic the timeout never fired. The fix FEEDS the
      // controller (`readsInFlight: false`) instead, leaving the monotonic
      // grace running from the ORIGINAL read completion.
      var elapsed = Duration.zero;
      final controller = CallRecordingsLoadController(
        elapsed: () => elapsed,
        scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
      );
      Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
        required String roomId,
        required String eventId,
        required String relType,
        String? from,
      }) async {
        if (relType == CallTranscriptContent.relType) {
          return (
            chunk: [
              half(_me, texts: const ['hola']),
              half(_peer, texts: const ['que tal']),
            ],
            nextBatch: null,
          );
        }
        if (relType == CallAudioContent.relType) {
          return (chunk: [audioEvent(_me), audioEvent(_peer)], nextBatch: null);
        }
        // A merge never arrives in this fixture.
        return (chunk: <MatrixEvent>[], nextBatch: null);
      }

      await pumpWithRecordings(
        tester,
        room(),
        fetch,
        loadController: controller,
      );

      // Reads landed at elapsed 0 -> the grace is stamped there.
      expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

      // A no-merge sync at 20s must NOT re-stamp the grace.
      elapsed = const Duration(seconds: 20);
      client.onSync.add(SyncUpdate(nextBatch: 's20'));
      await tester.pumpAndSettle();
      expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

      // A further no-merge sync just past the ORIGINAL 30s grace resolves
      // unavailable -- proving the 20s sync did not push the deadline out.
      // Mutation: re-run `_load` on sync -> the grace resets each sync -> this
      // stays pendingMerge and the test fails.
      elapsed = kCallMergeGrace + const Duration(seconds: 1);
      client.onSync.add(SyncUpdate(nextBatch: 's31'));
      await tester.pumpAndSettle();
      expect(controller.state.value, CallRecordingsLoadState.unavailable);
      expect(find.text('No recording of the full call.'), findsOneWidget);
    });

    testWidgets(
      'closing the dialog while it owns the merged player stops it and '
      'releases the shared player',
      (tester) async {
        // The merged bar is our own control now, not an AudioPlayerWidget (whose
        // dispose used to pause+dispose the owned player and clear ownership).
        // So closing the dialog must itself release a merged playback THIS
        // screen started -- otherwise the audio keeps playing and the shared
        // player stays owned after the screen is gone, and a reopened screen\'s
        // turn tap would see the event "owned" and seek a dead player.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        // The download HANGS and is never completed: the release under test is
        // the DISPOSE-time one, so nothing else (no post-download early return)
        // can clear ownership instead.
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        // Read straight off the shared notifier, which survives MatrixState
        // teardown (it is not disposed there).
        final ownership = matrixState.voiceMessageEventId;

        // Tap a turn -> the merged player is created and claims the shared
        // player (observation attached), then blocks on the hanging download.
        await tester.tap(find.text('0:01'));
        await tester.pump();
        expect(ownership.value, r'$merged');
        expect(identical(matrixState.audioPlayer, fake), isTrue);

        // Close the dialog while it still owns the merged player.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        // The shared player was STOPPED (paused), disposed and released.
        // Mutation: drop `_releaseMergedPlayerIfOwned()` from dispose ->
        // ownership stays '$merged' and the player is left playing/undisposed.
        expect(ownership.value, isNull);
        expect(matrixState.audioPlayer, isNull);
        expect(fake.disposed, isTrue);
        // The pause() the release issues is what actually stops audio (a real
        // just_audio dispose stops too); asserting it substantiates "stopped"
        // rather than merely "references cleared".
        expect(fake.pauseCount, greaterThan(0));
      },
    );

    testWidgets(
      'a failing merged download aborts the seek -- it never seeks or plays a '
      'newer player under the same event id',
      (tester) async {
        // F2: a failed `_startMergedPlayer` must ABORT the controller's seek
        // transaction, never return as success. When its identity guard SKIPS
        // the release (a fresh player took over the same event id mid-download),
        // returning normally would let the failed action seek+play THAT newer
        // player to the wrong position.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final p1 = _FakeAudioPlayer();
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => p1,
          mergedFileLoader: (_) => loader.future,
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));

        // Tap a turn -> startMergedPlayer(p1) claims $merged and blocks on the
        // (hanging) download.
        await tester.tap(find.text('0:01'));
        await tester.pump();
        expect(matrixState.voiceMessageEventId.value, r'$merged');
        expect(identical(matrixState.audioPlayer, p1), isTrue);

        // Stage the race the rethrow defends against: a FRESH player becomes the
        // shared player under the SAME event id while p1's download is still in
        // flight. (The in-flight guard prevents this via the normal paths; here
        // it is injected directly to exercise the identity-guard-skips branch.)
        final p2 = _FakeAudioPlayer();
        matrixState.audioPlayer = p2;

        // p1's download now FAILS.
        loader.completeError(Exception('merged download failed'));
        await tester.pumpAndSettle();

        // The failed start rethrew, so the seek transaction aborted BEFORE
        // seeking/playing: p2 was never driven to the failed turn's position.
        // Mutation: swallow instead of rethrow -> seekToTurn proceeds and
        // hijacks p2 (seekCount/playCount > 0).
        expect(
          p2.seekCount,
          0,
          reason: 'a failed start must not seek the newer player',
        );
        expect(
          p2.playCount,
          0,
          reason: 'a failed start must not play the newer player',
        );
        // The identity guard left p2 (which never owned p1) in place, untouched.
        expect(identical(matrixState.audioPlayer, p2), isTrue);
        expect(matrixState.voiceMessageEventId.value, r'$merged');

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await p1.dispose();
        await p2.dispose();
      },
    );

    testWidgets(
      'a refresh whose recordings read fails does NOT degrade the load state',
      (tester) async {
        // A live refresh must never SHRINK what is shown: halves only
        // accumulate, so a smaller count is a transient read failure, not a
        // deletion. Feeding it would flip the machine to a false `none` (and, in
        // the UI, unmount -- and stop -- a per-device row that might be playing).
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        var recordingsCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async {
          if (relType == CallTranscriptContent.relType) {
            return (
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            );
          }
          if (relType == CallAudioContent.relType) {
            recordingsCalls++;
            // Initial read succeeds with two halves; the refresh read FAILS.
            if (recordingsCalls > 1) throw Exception('transient network');
            return (chunk: [meAudio, peerAudio], nextBatch: null);
          }
          return (chunk: <MatrixEvent>[], nextBatch: null);
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Two halves, no merge -> pendingMerge.
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

        // A sync whose recordings read fails must NOT flip the machine to
        // `none`. Mutation: drop the `recs.length < _shownHalfCount` guard ->
        // the empty (failed) read feeds halfCount 0 -> `none`.
        client.onSync.add(SyncUpdate(nextBatch: 's-fail'));
        await tester.pumpAndSettle();
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);
      },
    );

    testWidgets(
      'closing the dialog does NOT clear another surface\'s ownership claim',
      (tester) async {
        // The dispose-time release must require we still OWN the merged id, not
        // merely that the shared player is the instance we observed. In the
        // no-timeline case there is no karaoke ownership listener to detach us,
        // so a per-device widget that took the shared player (claiming ITS id,
        // disposing but not nulling our old player) would otherwise have its
        // claim wrongly cleared on close.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        final loader = Completer<MatrixFile>();
        // NO atMs -> not timeline-eligible -> no turns -> no ownership listener.
        await pumpWithRecordings(
          tester,
          room(),
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
            meAudio,
            peerAudio,
            mergedEvent(
              _me,
              sourceEventIds: [meAudio.eventId, peerAudio.eventId],
            ),
          ]),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        final ownership = matrixState.voiceMessageEventId;

        // Bar-play claims the merged id (download hangs, observation attached).
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();
        expect(ownership.value, r'$merged');

        // A per-device widget takes over: it claims ITS own id and disposes our
        // merged player but leaves that same instance in `matrix.audioPlayer`
        // (mirrors `audio_player.dart` `_onButtonTap`, which does not null it
        // until after its own download).
        ownership.value = r'$audio-$device';

        // Close the transcript.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();

        // The other surface's claim is INTACT -- dispose saw it no longer owned
        // the merged id and left it alone. Mutation: drop the owner-id check in
        // `_releaseMergedPlayerIfOwned` (identity only) -> this reads null.
        expect(ownership.value, r'$audio-$device');

        matrixState.audioPlayer = null;
        ownership.value = null;
        await fake.dispose();
      },
    );

    testWidgets(
      'the bar control clears its retry once merged playback recovers',
      (tester) async {
        // A bar-start failure shows "Try again". If the merge then recovers by
        // ANOTHER path (a turn tap this control never saw), the bar must not
        // stay stuck showing "Try again" over a recording that is now playing.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        // Bar-play, then the download fails -> the control shows a retry.
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();
        loader.completeError(Exception('load failed'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Try again'), findsOneWidget);

        // Merged playback recovers by another path (modelled by a fresh owned,
        // playing shared player under the merged id).
        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        final recovered = _FakeAudioPlayer();
        matrixState.audioPlayer = recovered;
        matrixState.voiceMessageEventId.value = r'$merged';
        recovered.emitPlaying(true);
        await tester.pump();

        // The bar shows the playing control, NOT a stuck retry. Mutation: gate
        // the retry on `_loadFailed` instead of `showRetry` (which is false
        // while we own a live player) -> "Try again" stays shown.
        expect(find.widgetWithText(TextButton, 'Try again'), findsNothing);
        expect(find.byIcon(Icons.pause_circle), findsOneWidget);

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await fake.dispose();
        await recovered.dispose();
      },
    );

    testWidgets(
      'a live merge arrival shows the player with no false "No recording" flash',
      (tester) async {
        // The refresh swaps the displayed futures; an ordinary (even already
        // completed) future makes FutureBuilder render one `waiting` frame,
        // during which the bar would flash a FALSE "No recording" note (the
        // controller already latched `ready`). A SynchronousFuture swap avoids
        // the waiting frame.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        var mergePresent = false;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async {
          if (relType == CallTranscriptContent.relType) {
            return (
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            );
          }
          if (relType == CallAudioContent.relType) {
            return (chunk: [meAudio, peerAudio], nextBatch: null);
          }
          return (
            chunk: mergePresent ? [merged] : <MatrixEvent>[],
            nextBatch: null,
          );
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

        // The merge arrives; pump one frame at a time until the player shows,
        // watching EVERY intermediate frame for a false "No recording" note.
        mergePresent = true;
        client.onSync.add(SyncUpdate(nextBatch: 's-flash'));
        var sawNoRecording = false;
        for (var i = 0; i < 12 && mergedPlayer().evaluate().isEmpty; i++) {
          await tester.pump();
          if (find
              .text('No recording of the full call.')
              .evaluate()
              .isNotEmpty) {
            sawNoRecording = true;
          }
        }

        // The player appeared and no frame in the transition flashed the false
        // "No recording" note. Mutation: swap ordinary futures instead of
        // SynchronousFuture -> a `waiting` frame flashes "No recording".
        expect(mergedPlayer(), findsOneWidget);
        expect(
          sawNoRecording,
          isFalse,
          reason: 'no false-error flash during the live merge transition',
        );
      },
    );

    // ---- Start concurrency, refresh coordination, control EOF/replay -------

    testWidgets(
      'a turn tapped while the bar-start is still loading waits for it, then '
      'seeks the tapped turn (not 0)',
      (tester) async {
        // D1: ownership is claimed SYNCHRONOUSLY at the top of the merged
        // start's load, so a turn tapped while the bar's own play is mid-
        // download finds the merged event "owned" and routes straight to the
        // seek -- on a player with no source yet, which just_audio ignores,
        // starting playback at 0. The seek must WAIT for the in-flight start,
        // then seek the now-loaded player.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        // Bar-start in flight: it claims ownership + attaches, then hangs on
        // the pending download.
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();
        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        expect(matrixState.voiceMessageEventId.value, r'$merged');

        // Tap the 'me' turn (audioStart 1000ms) WHILE the start is loading.
        await tester.tap(find.text('0:01'));
        await tester.pump();

        // The seek has NOT fired yet -- it is waiting for the in-flight load.
        // Mutation: drop `await _mergedStartFuture` in `_seekSharedPlayer` ->
        // the seek runs now on the loading player -> seekCount == 1 -> RED.
        expect(
          fake.seekCount,
          0,
          reason:
              'the seek must wait for the in-flight start, not run on a '
              'still-loading player',
        );

        // Let the download finish: the start resolves, the deferred seek then
        // runs on the now-loaded player and lands on the tapped turn (1000ms).
        loader.complete(emptyMergedFile());
        for (var i = 0; i < 20 && fake.seekCount == 0; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        await tester.pump();
        expect(fake.seekCount, greaterThan(0));
        expect(
          fake.position,
          const Duration(milliseconds: 1000),
          reason: 'the deferred seek lands on the tapped turn, not the start',
        );

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a sync before the initial reads settle does not drop their merge',
      (tester) async {
        // D2: an early refresh that swaps the displayed futures before the
        // initial reads settle would make `_feedLoadController`'s future-
        // identity guard reject the initial reads' OWN merge. The refresh is
        // gated on the initial reads settling, so the merge (present from the
        // start) still shows.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        final recInitial =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final recRefresh =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final mergedInitial =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final mergedRefresh =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        var recCalls = 0;
        var mergedCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) {
          if (relType == CallTranscriptContent.relType) {
            return Future.value((
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            ));
          }
          if (relType == CallAudioContent.relType) {
            recCalls++;
            return recCalls == 1 ? recInitial.future : recRefresh.future;
          }
          mergedCalls++;
          return mergedCalls == 1 ? mergedInitial.future : mergedRefresh.future;
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // The audio reads are still pending -> the bar shimmers, the initial
        // reads have NOT settled.
        expect(mergedPlayer(), findsNothing);

        // A sync fires an early refresh (before the initial reads settle). With
        // the gate it is a no-op; on the mutation it starts its own reads.
        client.onSync.add(SyncUpdate(nextBatch: 's-early'));
        await tester.pump();

        // The refresh's reads land FIRST, reading the halves but (transiently)
        // no merge -- and, on the mutation, swap the displayed futures.
        recRefresh.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        mergedRefresh.complete((chunk: <MatrixEvent>[], nextBatch: null));
        await tester.pumpAndSettle();

        // Now the initial reads land WITH the merge.
        recInitial.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        mergedInitial.complete((chunk: [merged], nextBatch: null));
        await tester.pumpAndSettle();

        // The merge still shows. Mutation: remove the `_initialReadsSettled`
        // gate -> the early refresh clobbers the initial feed (identity guard
        // drops it) and the displayed futures hold the no-merge refresh -> the
        // player is dropped and the machine never reaches ready.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
      },
    );

    testWidgets(
      'a merge arriving before the initial reads settle is shown once they '
      'settle (deferred refresh)',
      (tester) async {
        // D2 corollary: the initial reads do NOT guarantee they capture a merge
        // published after their request went out -- the initial merged read can
        // return empty while a merge arrives moments later. An early sync must
        // therefore be DEFERRED, not dropped, and run once the initial reads
        // settle; otherwise the merge stays hidden until another sync.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        final recInitial =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final mergedInitial =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        var recCalls = 0;
        var mergedCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) {
          if (relType == CallTranscriptContent.relType) {
            return Future.value((
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            ));
          }
          if (relType == CallAudioContent.relType) {
            recCalls++;
            // Initial read is gated (pending); the deferred refresh reads the
            // halves immediately.
            return recCalls == 1
                ? recInitial.future
                : Future.value((chunk: [meAudio, peerAudio], nextBatch: null));
          }
          mergedCalls++;
          // Initial merged read returns EMPTY (the merge did not exist yet when
          // it was dispatched); the deferred refresh reads the merge.
          return mergedCalls == 1
              ? mergedInitial.future
              : Future.value((chunk: [merged], nextBatch: null));
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Initial reads still pending -> shimmer, not settled.
        expect(mergedPlayer(), findsNothing);

        // A sync arrives before the initial reads settle: it is DEFERRED.
        client.onSync.add(SyncUpdate(nextBatch: 's-early'));
        await tester.pump();

        // The initial reads settle WITHOUT a merge (stale empty snapshot); the
        // deferred refresh then runs and reads the merge that has since arrived.
        recInitial.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        mergedInitial.complete((chunk: <MatrixEvent>[], nextBatch: null));
        await tester.pumpAndSettle();

        // The merge shows via the deferred refresh. Mutation: drop the early
        // sync instead of deferring it -> the deferred refresh never runs -> the
        // merge stays hidden and the machine sits at pendingMerge.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
      },
    );

    testWidgets(
      'a refresh whose halves read fails still shows a merge read on the same '
      'sync',
      (tester) async {
        // D3: a transient halves-read failure (-> empty) must not suppress a
        // merge the same sync read successfully. The merge is evaluated against
        // the last-known half count and still shown; the shrunk list is never
        // adopted.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        var recCalls = 0;
        var mergedCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) async {
          if (relType == CallTranscriptContent.relType) {
            return (
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            );
          }
          if (relType == CallAudioContent.relType) {
            recCalls++;
            // Initial read: two halves. Refresh read: FAILS (transient).
            if (recCalls > 1) throw Exception('transient network');
            return (chunk: [meAudio, peerAudio], nextBatch: null);
          }
          mergedCalls++;
          // No merge initially; the merge lands on the refresh read.
          return (
            chunk: mergedCalls > 1 ? [merged] : <MatrixEvent>[],
            nextBatch: null,
          );
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Two halves, no merge yet -> pendingMerge, no player.
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);
        expect(mergedPlayer(), findsNothing);

        // A sync: the halves read fails (empty) but the merged read succeeds.
        client.onSync.add(SyncUpdate(nextBatch: 's-merge'));
        await tester.pumpAndSettle();

        // The merge is shown despite the flaky halves read. Mutation: keep the
        // blanket `if (recs.length < _shownHalfCount) return;` -> the whole
        // refresh is dropped -> no player, still pendingMerge.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
      },
    );

    testWidgets(
      'a superseded merged start detaches its observation of the old player',
      (tester) async {
        // D4: when a fresh player takes the shared slot under the SAME merged
        // id mid-download, the failing start's `_releaseIfCurrent` must not
        // clear the (foreign) shared ownership -- but it must still detach OUR
        // observation of the superseded player, or its subscriptions leak and
        // its later position events keep driving the karaoke highlight. (Not
        // reachable via the normal single-owner bar; the swap is injected here
        // to exercise the identity-guard-skips branch.)
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final p1 = _FakeAudioPlayer();
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => p1,
          mergedFileLoader: (_) => loader.future,
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));

        // Tap a turn: startMergedPlayer(p1) claims $merged, attaches
        // observation to p1, then blocks on the hanging download.
        await tester.tap(find.text('0:01'));
        await tester.pump();
        expect(identical(matrixState.audioPlayer, p1), isTrue);

        // A fresh player takes the shared slot under the SAME merged id.
        final p2 = _FakeAudioPlayer();
        matrixState.audioPlayer = p2;

        // p1's download fails -> the start aborts. `_releaseIfCurrent` sees p1
        // is no longer current (p2 took over) so it does NOT clear shared
        // ownership, but it DOES detach our observation of p1.
        loader.completeError(Exception('merged download failed'));
        await tester.pumpAndSettle();

        // p2 (which we never owned) is left untouched, ownership intact.
        expect(identical(matrixState.audioPlayer, p2), isTrue);
        expect(matrixState.voiceMessageEventId.value, r'$merged');

        // A later position on the superseded p1 must NOT drive the karaoke
        // highlight -- our observation of it was detached. Mutation: drop the
        // `if (identical(_observedPlayer, player)) _detachObservation();` -> p1
        // stays observed -> this position resolves an active index.
        p1.emitPosition(const Duration(milliseconds: 6000));
        await tester.pump();
        final timeline = tester.widget<TurnTimeline>(find.byType(TurnTimeline));
        expect(
          timeline.activeIndex!.value,
          isNull,
          reason:
              'a superseded player we detached must no longer drive the '
              'highlight',
        );

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await p1.dispose();
        await p2.dispose();
      },
    );

    testWidgets(
      'a completed merged track with unknown duration shows play and replays '
      'from the start',
      (tester) async {
        // E1: a track that reached ProcessingState.completed with a null
        // duration must read as at-end -- show the play affordance and, on tap,
        // replay from 0 -- not show pause over silence and resume at EOF. The
        // owned, completed player is installed directly (as the "clears its
        // retry" test above does), so the assertion turns on `_isAtEnd`'s
        // processing-state check, not the load dance.
        //
        // The merge is served with NO per-device recordings, deliberately: the
        // stock per-device AudioPlayerWidgets stay mounted (offstage) and, on a
        // shared-player `completed`, seek it back to 0 -- which would consume
        // the completed state before this control saw it. That is a real "merge
        // shown, no per-device rows" shape (a merge whose recordings read
        // flaked, see D3), and it isolates THIS control's `_isAtEnd`.
        await pumpWithRecordings(
          tester,
          room(),
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
            mergedEvent(_me),
          ]),
        );
        expect(mergedPlayer(), findsOneWidget);

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        final fake = _FakeAudioPlayer();
        matrixState.audioPlayer = fake;
        matrixState.voiceMessageEventId.value = r'$merged';
        // The track ran to the end: completed, playing flag still set, duration
        // unknown (the fake reports null).
        fake.emitCompleted();
        await tester.pump();

        // The bar shows PLAY, not pause. Mutation: revert `_isAtEnd` to the
        // duration-only check -> null duration reads as not-at-end -> pause.
        expect(find.byIcon(Icons.play_circle), findsOneWidget);
        expect(find.byIcon(Icons.pause_circle), findsNothing);

        // Tapping replays from 0: it seeks to zero before resuming.
        final seeksBefore = fake.seekCount;
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();
        expect(
          fake.seekCount,
          greaterThan(seeksBefore),
          reason: 'a completed track replays from 0 (seek), not resume at EOF',
        );
        expect(fake.position, Duration.zero);

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
        await fake.dispose();
      },
    );

    testWidgets(
      'a rejected replay seek is handled and does not resume at EOF',
      (tester) async {
        // E2: the replay path awaits seek(0) inside a caught transaction and
        // only resumes after it -- so a rejected seek aborts the replay (no
        // unhandled async error, no resume at EOF) rather than firing seek-
        // then-resume blind. Merge served with NO per-device rows (see E1) so
        // nothing else consumes the completed state.
        await pumpWithRecordings(
          tester,
          room(),
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
            mergedEvent(_me),
          ]),
        );
        expect(mergedPlayer(), findsOneWidget);

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        final fake = _FakeAudioPlayer();
        matrixState.audioPlayer = fake;
        matrixState.voiceMessageEventId.value = r'$merged';
        // Completed (so the tap takes the replay path), and the next seek will
        // REJECT.
        fake.emitCompleted();
        await tester.pump();
        final playsBefore = fake.playCount;
        fake.failSeek = true;

        // Tap to replay: the seek rejects. The failure is caught (no unhandled
        // async error fails the test) and playback does NOT resume at EOF.
        // Mutation: revert to unawaited-seek-then-resume -> the rejected seek
        // is an unhandled async error AND onResume still fires (playCount up).
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pumpAndSettle();
        expect(
          fake.playCount,
          playsBefore,
          reason: 'a rejected replay seek must abort the replay, not resume',
        );

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
        await fake.dispose();
      },
    );

    // ---- Structural convergence round: class-level invariants ---------------

    testWidgets('G-1: a turn-tap seek awaiting an in-flight start never seeks a player '
        'once the shared player has been replaced under it', (tester) async {
      // Class 1, seek path ("re-validate (player,eventId) AFTER every await"):
      // the D1 fix made `_seekSharedPlayer` await the in-flight start before
      // seeking. If the shared player is REPLACED during that await, no seek
      // must run on the merged player it captured. The single `_isCurrentMerged`
      // predicate enforces this: the in-flight start aborts (it re-checks the
      // predicate after its own load), and the seek re-checks it again after
      // the await. Mutation: neuter `_isCurrentMerged` (make it always true) ->
      // the start no longer aborts on the swap and the seek runs on the stale
      // captured player -> p1.seekCount > 0 -> RED.
      //
      // (Note: the seek-site recheck is belt-and-braces with the start's own
      // superseded-abort -- both use the ONE predicate -- so this proves the
      // predicate, the actual structural fix, is load-bearing on the seek
      // path; dropping ONLY the seek-site line stays green because the start
      // still aborts, which is why the mutation targets the shared predicate.)
      final meAudio = audioEvent(_me);
      final peerAudio = audioEvent(_peer);
      final p1 = _FakeAudioPlayer();
      final loader = Completer<MatrixFile>();
      await pumpWithRecordings(
        tester,
        room(),
        serving(karaokeFixture(meAudio, peerAudio)),
        audioPlayerFactory: () => p1,
        mergedFileLoader: (_) => loader.future,
      );

      final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));

      // Bar-start in flight: it claims $merged + attaches to p1, then hangs on
      // the download.
      await tester.tap(find.byIcon(Icons.play_circle));
      await tester.pump();
      expect(matrixState.voiceMessageEventId.value, r'$merged');
      expect(identical(matrixState.audioPlayer, p1), isTrue);

      // Tap the 'me' turn while the start loads: `_seekSharedPlayer` captures
      // (p1, $merged) and awaits the in-flight start.
      await tester.tap(find.text('0:01'));
      await tester.pump();

      // A DIFFERENT merged player becomes the shared player while the start is
      // still loading. Complete the download so the start settles and the
      // deferred seek resumes.
      final p2 = _FakeAudioPlayer();
      matrixState.audioPlayer = p2;
      loader.complete(emptyMergedFile());
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();

      // Neither the captured merged player p1 nor the replacement p2 is
      // seeked: the swap made p1 no longer current, so the transaction aborts.
      expect(
        p1.seekCount,
        0,
        reason:
            'a seek must not run on the merged player it captured once '
            'that player has been replaced under it',
      );
      expect(
        p2.seekCount,
        0,
        reason:
            'a seek must never act on the player that replaced the one it '
            'awaited a start for',
      );

      matrixState.audioPlayer = null;
      matrixState.voiceMessageEventId.value = null;
      await tester.pumpAndSettle();
      await p1.dispose();
      await p2.dispose();
    });

    testWidgets(
      'G-2: a pause tap landing between a replay seek and its resume wins '
      '(no resume)',
      (tester) async {
        // Class 1, replay branch: `_replayFromStart` awaits seek(0) then resumes.
        // A pause tap landing in that window must WIN -- the replay must not
        // resume over it. A monotonic tap generation captured at the replay's
        // start and re-checked after the seek invalidates the resume when a newer
        // tap occurs. Served with NO per-device rows (as E1/E2) so nothing else
        // consumes the completed state.
        await pumpWithRecordings(
          tester,
          room(),
          serving([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
            mergedEvent(_me),
          ]),
        );
        expect(mergedPlayer(), findsOneWidget);

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        final fake = _FakeAudioPlayer();
        matrixState.audioPlayer = fake;
        matrixState.voiceMessageEventId.value = r'$merged';
        // The track ran to the end -> the bar shows play, and a tap replays.
        fake.emitCompleted();
        await tester.pump();
        expect(find.byIcon(Icons.play_circle), findsOneWidget);

        // Gate the replay's seek(0) so a second tap can land mid-replay.
        fake.seekGate = Completer<void>();
        await tester.tap(find.byIcon(Icons.play_circle));
        await tester.pump();

        // Between the replay's seek and its resume, the player is now playing
        // mid-track -> the bar shows pause, and a tap is a PAUSE.
        fake.emitPlaying(true);
        fake.emitPosition(const Duration(milliseconds: 2000));
        await tester.pump();
        expect(find.byIcon(Icons.pause_circle), findsOneWidget);
        final playsBefore = fake.playCount;
        await tester.tap(find.byIcon(Icons.pause_circle));
        await tester.pump();
        expect(fake.pauseCount, greaterThan(0));

        // Let the replay's gated seek complete. Its resume must be abandoned --
        // a newer (pause) tap bumped the generation.
        fake.seekGate!.complete();
        await tester.pumpAndSettle();

        // The pause won: the replay did NOT resume. Mutation: drop the
        // generation recheck in `_replayFromStart` -> it resumes over the pause
        // (onResume -> play) -> playCount increases -> RED.
        expect(
          fake.playCount,
          playsBefore,
          reason:
              'a pause tap between a replay seek and resume must not be '
              'overridden by the resume',
        );

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
        await fake.dispose();
      },
    );

    testWidgets(
      'F-1: a merge-bearing sync arriving DURING an in-flight refresh is not '
      'lost (drained after)',
      (tester) async {
        // Class 2 ("a sync arriving while busy is always remembered and drained
        // once"): a sync that lands while a refresh read is in flight must not be
        // dropped. The single trailing-edge coalescer loops as long as a sync
        // re-armed the request, so the merge the second sync carries is drained
        // on the next pass -- no manual retry, no waiting for a third sync.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        // Pass-1 refresh reads are gated so a SECOND sync lands while they are in
        // flight; pass-2 reads (after the loop re-arms) return the merge.
        final pass1Rec =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final pass1Merged =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        var recCalls = 0;
        var mergedCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) {
          if (relType == CallTranscriptContent.relType) {
            return Future.value((
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            ));
          }
          if (relType == CallAudioContent.relType) {
            recCalls++;
            if (recCalls == 2) return pass1Rec.future; // in-flight refresh pass
            return Future.value((chunk: [meAudio, peerAudio], nextBatch: null));
          }
          mergedCalls++;
          // Initial + pass-1: no merge yet. Pass-2 (after the second sync
          // re-arms the coalescer): the merge is now published.
          if (mergedCalls == 1) {
            return Future.value((chunk: <MatrixEvent>[], nextBatch: null));
          }
          if (mergedCalls == 2) return pass1Merged.future;
          return Future.value((chunk: [merged], nextBatch: null));
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Two halves, no merge yet -> pendingMerge, no player.
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);
        expect(mergedPlayer(), findsNothing);

        // Sync 1 -> a refresh pass starts and hangs on its gated reads.
        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        await tester.pump();

        // Sync 2 lands WHILE pass 1 is in flight (the merge is now published).
        client.onSync.add(SyncUpdate(nextBatch: 's2'));
        await tester.pump();

        // Pass 1 completes with no merge; the coalescer, having been re-armed by
        // sync 2, drains a second pass -- which reads the merge.
        pass1Rec.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        pass1Merged.complete((chunk: <MatrixEvent>[], nextBatch: null));
        await tester.pumpAndSettle();

        // The merge shows without a further sync or a manual retry. Mutation:
        // make the drain a single pass (no loop / no re-check of the request)
        // -> sync 2 is dropped -> stays pendingMerge, no player -> RED.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
      },
    );

    testWidgets(
      'G-3: a rejecting stop/dispose on the teardown path produces no unhandled '
      'async error',
      (tester) async {
        // Class 3: every fired-and-forgotten player future on the teardown/abort
        // paths carries an error handler, so a rejected pause/stop/dispose does
        // not surface as an unhandled async error. Here the dispose-time release
        // (`_releaseMergedPlayerIfOwned`) fires pause()+dispose(), both of which
        // reject. Mutation: drop the error handler on either -> the rejection is
        // unhandled -> the test's error zone fails -> RED.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        final fake = _FakeAudioPlayer();
        // The download hangs so the release under test is the dispose-time one.
        final loader = Completer<MatrixFile>();
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
          audioPlayerFactory: () => fake,
          mergedFileLoader: (_) => loader.future,
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));

        // Tap a turn -> the merged player is created, claims $merged and is
        // observed, then blocks on the hanging download.
        await tester.tap(find.text('0:01'));
        await tester.pump();
        expect(matrixState.voiceMessageEventId.value, r'$merged');
        expect(identical(matrixState.audioPlayer, fake), isTrue);

        // Its teardown will REJECT.
        fake.failTeardown = true;

        // Close the dialog while it owns the merged player -> the dispose-time
        // release fires pause()+dispose(), both rejecting. With error handlers
        // the rejections are caught and the test sees no unhandled async error.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // The release still ran (ownership cleared, teardown recorded) -- the
        // rejection did not abort it -- and produced no unhandled error.
        expect(matrixState.voiceMessageEventId.value, isNull);
        expect(matrixState.audioPlayer, isNull);
        expect(fake.disposed, isTrue);
        expect(fake.pauseCount, greaterThan(0));
      },
    );

    testWidgets(
      'G-1 (cont): a same-id player swap DURING the seek await aborts the play '
      'rather than playing the replacement',
      (tester) async {
        // Class 1, seek->play transaction: `_seekSharedPlayer` re-validates after
        // its OWN seek await too (not just the start await), and THROWS on a
        // mismatch so the abort PROPAGATES to the controller -- whose post-seek
        // check inspects only ownership, which a same-id player swap leaves
        // unchanged. Without that, the controller would play the replacement.
        // Mutation: drop the post-`await player.seek(...)` recheck (or make it
        // `return` instead of throw) -> the controller plays p2 -> RED.
        final meAudio = audioEvent(_me);
        final peerAudio = audioEvent(_peer);
        await pumpWithRecordings(
          tester,
          room(),
          serving(karaokeFixture(meAudio, peerAudio)),
        );

        final matrixState = tester.state<MatrixState>(find.byType(_TestMatrix));
        // Install an owned, loaded merged player directly (as E1/E2 do).
        final p1 = _FakeAudioPlayer();
        matrixState.audioPlayer = p1;
        matrixState.voiceMessageEventId.value = r'$merged';

        // Tap the 'me' turn -> the controller seeks p1; gate the seek so a swap
        // can land while it is in flight.
        p1.seekGate = Completer<void>();
        await tester.tap(find.text('0:01'));
        await tester.pump();

        // A DIFFERENT player takes the shared slot under the SAME merged id while
        // the seek is in flight (ownership unchanged).
        final p2 = _FakeAudioPlayer();
        matrixState.audioPlayer = p2;

        // Complete the gated seek: the post-seek recheck sees p1 is no longer
        // current and throws, so the transaction aborts before play.
        p1.seekGate!.complete();
        await tester.pumpAndSettle();

        expect(
          p2.playCount,
          0,
          reason:
              'a same-id swap during the seek await must abort the play, '
              'never play the replacement',
        );

        matrixState.audioPlayer = null;
        matrixState.voiceMessageEventId.value = null;
        await tester.pumpAndSettle();
        await p1.dispose();
        await p2.dispose();
      },
    );

    testWidgets(
      'F-1 (cont): a retry landing during an in-flight refresh drain does not '
      'strand the retried epoch',
      (tester) async {
        // Class 2, coalescer settle-gate: a drain still looping from a PRIOR
        // epoch must not run a pass after `_retry` reset `_initialReadsSettled`
        // -- such a pass swaps the displayed futures and makes the retried
        // epoch's own initial feed fail its future-identity guard, leaving
        // `_initialReadsSettled` false forever so no later sync ever drains. The
        // loop re-checks the settle gate on every pass and preserves the request
        // for `_feedLoadController` to restart. Mutation: drop the in-loop
        // `if (!_initialReadsSettled) return;` -> the prior drain clobbers the
        // retried feed -> the merge never shows -> RED.
        final meAudio = audioEvent(_me, deviceId: 'PHONE');
        final peerAudio = audioEvent(_peer);
        final thirdAudio = audioEvent(_me, deviceId: 'LAPTOP');
        final merged = mergedEvent(
          _me,
          sourceEventIds: [meAudio.eventId, peerAudio.eventId],
        );
        // Gated reads: #2 = the epoch-1 drain pass; #3 = the retried epoch's
        // initial reads. #4 (only reached WITHOUT the settle-gate) is the
        // clobbering pass -- it reads a GROWN half count so it swaps the futures.
        final recDrain1 =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final mergedDrain1 =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final recEpoch2 =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        final mergedEpoch2 =
            Completer<({List<MatrixEvent> chunk, String? nextBatch})>();
        var transcriptCalls = 0;
        var recCalls = 0;
        var mergedCalls = 0;
        Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
          required String roomId,
          required String eventId,
          required String relType,
          String? from,
        }) {
          if (relType == CallTranscriptContent.relType) {
            transcriptCalls++;
            // Epoch 1's transcript read FAILS (so the retry button shows);
            // the retried read succeeds.
            if (transcriptCalls == 1) {
              return Future.error(Exception('transcript read failed'));
            }
            return Future.value((
              chunk: [
                half(_me, texts: const ['hola']),
                half(_peer, texts: const ['que tal']),
              ],
              nextBatch: null,
            ));
          }
          if (relType == CallAudioContent.relType) {
            recCalls++;
            if (recCalls == 1) {
              return Future.value((
                chunk: [meAudio, peerAudio],
                nextBatch: null,
              ));
            }
            if (recCalls == 2) return recDrain1.future;
            if (recCalls == 3) return recEpoch2.future;
            // Only reached by a clobbering pass (mutation): a GROWN half count.
            return Future.value((
              chunk: [meAudio, peerAudio, thirdAudio],
              nextBatch: null,
            ));
          }
          mergedCalls++;
          if (mergedCalls == 1) {
            return Future.value((chunk: <MatrixEvent>[], nextBatch: null));
          }
          if (mergedCalls == 2) return mergedDrain1.future;
          if (mergedCalls == 3) return mergedEpoch2.future;
          return Future.value((chunk: <MatrixEvent>[], nextBatch: null));
        }

        final controller = CallRecordingsLoadController(
          elapsed: () => Duration.zero,
          scheduleTimer: (_, _) => Timer(Duration.zero, () {}),
        );
        await pumpWithRecordings(
          tester,
          room(),
          fetch,
          loadController: controller,
        );

        // Epoch 1: the transcript failed -> the retry button shows; the audio
        // reads settled with no merge.
        expect(find.text('Try again'), findsOneWidget);
        expect(controller.state.value, CallRecordingsLoadState.pendingMerge);

        // Sync 1 -> an epoch-1 drain pass starts and hangs on its gated reads.
        client.onSync.add(SyncUpdate(nextBatch: 's1'));
        await tester.pump();

        // Retry lands WHILE that drain is in flight: a fresh epoch begins, its
        // own initial reads gated.
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        // Sync 2 arrives in the new epoch before its initial reads settle.
        client.onSync.add(SyncUpdate(nextBatch: 's2'));
        await tester.pump();

        // The epoch-1 drain's gated reads complete (no merge, dropped by
        // controller identity). WITHOUT the in-loop settle-gate, the loop now
        // runs a clobbering pass against the retried epoch.
        recDrain1.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        mergedDrain1.complete((chunk: <MatrixEvent>[], nextBatch: null));
        await tester.pump();

        // The retried epoch's initial reads settle WITH the merge.
        recEpoch2.complete((chunk: [meAudio, peerAudio], nextBatch: null));
        mergedEpoch2.complete((chunk: [merged], nextBatch: null));
        await tester.pumpAndSettle();

        // The merge shows: the retried epoch's feed was not clobbered. Mutation:
        // the prior drain's clobbering pass swaps the futures, the retried feed
        // fails its identity guard, `_initialReadsSettled` stays false, and the
        // merge never appears.
        expect(controller.state.value, CallRecordingsLoadState.ready);
        expect(mergedPlayer(), findsOneWidget);
      },
    );

    group('whole-call transcript paywall (#8792 task 3)', () {
      // Isolated from every test above (and from each other): the shared
      // `MatrixState.pangeaController` this whole file's `setUpAll` installs
      // once has no subscription state worth mutating in place, so each test
      // here installs its OWN `FakePangeaController`, and `tearDown` restores
      // the neutral (subscribed) default so a later test in this file never
      // inherits an unsubscribed viewer it never asked for.
      tearDown(() => MatrixState.pangeaController = FakePangeaController());

      testWidgets(
        'an unsubscribed viewer sees the locked banner and zero words',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(
            subscribed: false,
          );
          await pumpWithRecordings(
            tester,
            room(),
            servingByType([
              half(_me, texts: const ['hola']),
              half(_peer, texts: const ['que tal']),
            ]),
          );

          // Mutation: gating on `true` (or not gating at all) renders the
          // words for an unsubscribed viewer -> RED.
          expect(find.byType(LockedPreviewBanner), findsOneWidget);
          expect(find.textContaining('hola'), findsNothing);
          expect(find.textContaining('que tal'), findsNothing);
        },
      );

      testWidgets('a subscribed viewer sees the words, not the banner', (
        tester,
      ) async {
        MatrixState.pangeaController = FakePangeaController(subscribed: true);
        await pumpWithRecordings(
          tester,
          room(),
          servingByType([
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
          ]),
        );

        expect(find.byType(LockedPreviewBanner), findsNothing);
        expect(find.textContaining('hola'), findsOneWidget);
        expect(find.textContaining('que tal'), findsOneWidget);
      });

      testWidgets(
        'a subscribed->unsubscribed downgrade re-locks on the next rebuild',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final events = [
            half(_me, texts: const ['hola']),
            half(_peer, texts: const ['que tal']),
          ];
          await pumpWithRecordings(tester, room(), servingByType(events));

          expect(find.textContaining('hola'), findsOneWidget);
          expect(find.byType(LockedPreviewBanner), findsNothing);

          // Downgrade, then force a genuine IN-PLACE rebuild through the
          // screen's OWN sync-driven live refresh -- not a fresh dialog-open
          // -- by mutating the transcript so `transcriptChanged` sees a real
          // difference and calls `setState`. Mutation: reading
          // `showSubscriptionGatedContent` once and caching it (instead of
          // live, in `_bodySection`, on every build) would leave the words on
          // screen here -> RED.
          MatrixState.pangeaController = FakePangeaController(
            subscribed: false,
          );
          events.removeWhere(
            (e) =>
                e.type == CallTranscriptContent.relType && e.senderId == _peer,
          );
          events.add(half(_peer, texts: const ['que tal, otra vez']));
          client.onSync.add(SyncUpdate(nextBatch: 'downgrade'));
          await tester.pumpAndSettle();

          expect(find.byType(LockedPreviewBanner), findsOneWidget);
          expect(find.textContaining('hola'), findsNothing);
          expect(find.textContaining('que tal'), findsNothing);
        },
      );
    });

    group('on-demand transcribe + language picker (#8792 task 3)', () {
      tearDown(() => MatrixState.pangeaController = FakePangeaController());

      /// A [WholeCallTranscriber] built from plain fake seams -- the same
      /// shape `whole_call_transcriber_test.dart` uses to test the producer
      /// itself -- so these tests exercise the VIEW's WIRING (does tapping
      /// the button call the right method with the right arguments, and
      /// react correctly to true/false) without a real STT pipeline,
      /// homeserver, or subscription controller. [_peer] always has exactly
      /// one manifest recording on offer; [_me]/[_peer] are always absent in
      /// [readTranscript]'s answer, which is what lets the on-demand path
      /// proceed (see `WholeCallTranscriber._skip`).
      WholeCallTranscriber buildFakeTranscriber({
        Future<({String? l1, String? l2})> Function(String)?
        resolvePeerLanguages,
        Future<Uint8List> Function(Uri)? download,
        ManifestDiscoverer? discover,
        TranscriptReader? readTranscript,
        required PeerHalfPoster post,
      }) => WholeCallTranscriber(
        selfUserId: _me,
        participants: const {_me, _peer},
        isEnabled: () => true,
        discover:
            discover ??
            (callKey) async => WholeCallManifest(
              resolved: true,
              recordings: [
                CallAudioRecording(
                  eventId: r'$audio-peer-',
                  senderId: _peer,
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
                  content: CallAudioContent(
                    callKey: _callKey,
                    url: 'mxc://fakeServer.notExisting/AUDIO',
                    mimetype: 'audio/wav',
                    codec: kCallAudioCodec,
                    size: 1000,
                    durationMs: 4000,
                    sampleRate: 16000,
                    channels: 1,
                  ),
                ),
              ],
            ),
        readTranscript:
            readTranscript ??
            (callKey) async => assembleTranscript(
              candidates: const [],
              expectedSenders: const [_me, _peer],
            ),
        download:
            download ?? (uri) async => Uint8List.fromList(const [1, 2, 3, 4]),
        transcribe:
            (
              bytes, {
              required String l1,
              required String l2,
              required int startedAtMs,
              required int durationMs,
            }) async => [TranscriptSegment('que tal', atMs: startedAtMs)],
        resolvePeerLanguages:
            resolvePeerLanguages ?? (_) async => (l1: 'en', l2: 'es'),
        post: post,
        wait: (d) async {},
      );

      testWidgets(
        'subscribed + a known recording + absent half shows a Transcribe '
        'button',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          await pumpWithRecordings(
            tester,
            room(),
            servingByType([
              half(_me, texts: const ['hola']),
              audioEvent(_peer),
            ]),
          );

          expect(find.text('Transcribe'), findsOneWidget);
        },
      );

      testWidgets(
        'absent + no recording shows the plain note, never a button',
        (tester) async {
          // Mutation: showing the button for every absent half, regardless of
          // whether a recording exists, would leave "Transcribe" findable
          // here -> RED.
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          await pumpWithRecordings(
            tester,
            room(),
            servingByType([
              half(_me, texts: const ['hola']),
            ]),
          );

          expect(find.textContaining('No transcript from'), findsOneWidget);
          expect(find.text('Transcribe'), findsNothing);
        },
      );

      testWidgets(
        'tapping Transcribe shimmers while running and fills in the half on '
        'success',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final events = [
            half(_me, texts: const ['hola']),
            audioEvent(_peer),
          ];
          final downloadGate = Completer<Uint8List>();
          final posted = <String>[];
          final fake = buildFakeTranscriber(
            download: (uri) => downloadGate.future,
            post:
                ({
                  required callKey,
                  required spokenBy,
                  required sourceAudioEventId,
                  required deviceId,
                  required langCode,
                  required clockAnchor,
                  required segments,
                }) async {
                  posted.add(spokenBy);
                  events.add(half(_peer, texts: const ['que tal']));
                },
          );

          await pumpWithRecordings(
            tester,
            room(),
            servingByType(events),
            transcriber: fake,
          );

          expect(find.text('Transcribe'), findsOneWidget);
          await tester.tap(find.text('Transcribe'));
          await tester.pump();

          // In flight: the button is gone, replaced by the same shimmer the
          // "still transcribing" recency window uses. Mutation: never
          // switching to the loading state while a request runs would leave
          // "Transcribe" tappable a second time here -> RED.
          expect(find.text('Transcribe'), findsNothing);
          expect(find.textContaining('Still transcribing'), findsOneWidget);

          downloadGate.complete(Uint8List.fromList(const [1, 2, 3, 4]));
          await tester.pumpAndSettle();

          expect(posted, [_peer]);
          expect(find.textContaining('que tal'), findsOneWidget);
          expect(find.text('Transcribe'), findsNothing);
          expect(find.textContaining('Still transcribing'), findsNothing);
        },
      );

      testWidgets(
        'a download failure surfaces as "audio unavailable", never a stuck '
        'button',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final fake = buildFakeTranscriber(
            download: (uri) async => throw Exception('network gone'),
            post:
                ({
                  required callKey,
                  required spokenBy,
                  required sourceAudioEventId,
                  required deviceId,
                  required langCode,
                  required clockAnchor,
                  required segments,
                }) async {
                  fail(
                    'must not post a half over a download that never landed',
                  );
                },
          );

          await pumpWithRecordings(
            tester,
            room(),
            servingByType([
              half(_me, texts: const ['hola']),
              audioEvent(_peer),
            ]),
            transcriber: fake,
          );

          await tester.tap(find.text('Transcribe'));
          await tester.pumpAndSettle();

          // Mutation: treating UNAVAILABLE-TERMINAL as retryable (leaving the
          // ordinary button back in place) would find "Transcribe" here,
          // exactly the "button that cannot work" the design forbids -> RED.
          expect(find.text('Transcribe'), findsNothing);
          expect(
            find.textContaining('could not be downloaded'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'an unresolved peer language opens the picker, and the choice is '
        'forwarded',
        (tester) async {
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final events = [
            half(_me, texts: const ['hola']),
            audioEvent(_peer),
          ];
          String? postedLangCode;
          final fake = buildFakeTranscriber(
            resolvePeerLanguages: (_) async => (l1: null, l2: null),
            post:
                ({
                  required callKey,
                  required spokenBy,
                  required sourceAudioEventId,
                  required deviceId,
                  required langCode,
                  required clockAnchor,
                  required segments,
                }) async {
                  postedLangCode = langCode;
                  events.add(half(_peer, texts: const ['bonjour']));
                },
          );

          await pumpWithRecordings(
            tester,
            room(),
            servingByType(events),
            transcriber: fake,
            pickerLanguages: [
              LanguageModel(langCode: 'fr', displayName: 'French'),
            ],
          );

          await tester.tap(find.text('Transcribe'));
          await tester.pumpAndSettle();

          // Mutation: calling `transcribeHalfOnDemand` straight away instead
          // of opening the picker on an unresolved pair would find no dialog
          // here -> RED.
          expect(find.text('What language was spoken?'), findsOneWidget);
          expect(find.text('French'), findsOneWidget);

          await tester.tap(find.text('French'));
          await tester.pumpAndSettle();

          expect(postedLangCode, 'fr');
          expect(find.textContaining('bonjour'), findsOneWidget);
        },
      );

      testWidgets(
        'a not-yet-visible manifest leaves the button retryable, never '
        'marked unavailable',
        (tester) async {
          // discover comes back UNRESOLVED -- the peer's merge is still in
          // flight, a transient miss, NOT the saved audio being unusable.
          // Mutation: collapsing the typed result to a bool marks EVERY
          // non-produce unavailable, so this transient would wrongly drop the
          // button and show the terminal note -> RED.
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final fake = buildFakeTranscriber(
            discover: (_) async => WholeCallManifest.absent,
            post:
                ({
                  required callKey,
                  required spokenBy,
                  required sourceAudioEventId,
                  required deviceId,
                  required langCode,
                  required clockAnchor,
                  required segments,
                }) async => fail('must not post when no manifest is visible'),
          );

          await pumpWithRecordings(
            tester,
            room(),
            servingByType([
              half(_me, texts: const ['hola']),
              audioEvent(_peer),
            ]),
            transcriber: fake,
          );

          await tester.tap(find.text('Transcribe'));
          await tester.pumpAndSettle();

          expect(find.text('Transcribe'), findsOneWidget);
          expect(find.textContaining('could not be downloaded'), findsNothing);
        },
      );

      testWidgets(
        'a half that already landed refreshes into view, never marked '
        'unavailable',
        (tester) async {
          // The peer's own half lands between render and the skip check: the
          // check sees it (alreadyPresent, no produce), and it is now among the
          // served events so the refresh shows it.
          // Mutation: collapsing the typed result to a bool marks this
          // alreadyPresent unavailable instead of refreshing -> "ya estaba" is
          // never shown and the terminal note appears -> RED.
          MatrixState.pangeaController = FakePangeaController(subscribed: true);
          final events = [
            half(_me, texts: const ['hola']),
            audioEvent(_peer),
          ];
          final fake = buildFakeTranscriber(
            readTranscript: (_) async {
              events.add(half(_peer, texts: const ['ya estaba']));
              return assembleTranscript(
                candidates: [
                  TranscriptCandidate(
                    senderId: _peer,
                    eventId: r'$peer-authentic',
                    originServerTs: 2000,
                    segments: [TranscriptSegment('ya estaba', atMs: 2000)],
                    accounting: const HalfAccounting(),
                  ),
                ],
                expectedSenders: const [_me, _peer],
              );
            },
            post:
                ({
                  required callKey,
                  required spokenBy,
                  required sourceAudioEventId,
                  required deviceId,
                  required langCode,
                  required clockAnchor,
                  required segments,
                }) async => fail('must not post when a half already exists'),
          );

          await pumpWithRecordings(
            tester,
            room(),
            servingByType(events),
            transcriber: fake,
          );

          await tester.tap(find.text('Transcribe'));
          await tester.pumpAndSettle();

          expect(find.textContaining('ya estaba'), findsOneWidget);
          expect(find.textContaining('could not be downloaded'), findsNothing);
        },
      );
    });
  });
}
