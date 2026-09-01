import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_view.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';
import '../get_test_client.dart';

const _callKey = r'$membership:fakeServer.notExisting';

/// A real wall-clock instant, because that is what a position IS.
///
/// 2026-08-26T09:00:00Z. Using 0 here would quietly make every fixture agree
/// with a screen that never converted absolute time to elapsed.
const _callStart = 1787994000000;
const _me = '@test:fakeServer.notExisting';
const _peer = '@peer:fakeServer.notExisting';

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
  }) => MatrixEvent(
    type: CallTranscriptContent.relType,
    eventId: '\$half-$sender',
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
      if (positionsMarked) 'positions_marked': true,
      // From the writer's own serialiser, so a fixture cannot drift out of the
      // declaration contract when a field is added to it.
      if (declared)
        ...HalfAccounting(
          chunksCaptured: captured,
          chunksTranscribed: transcribed,
          chunksLost: lost,
          chunksSuppressed: suppressed,
          captureRefused: captureRefused,
          drainComplete: drainComplete,
        ).toJson(),
      ...?anchor?.toJson(),
    },
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
      segments: [TranscriptSegment('a' * 2000)],
      chunksCaptured: 1,
      chunksTranscribed: 1,
      chunksLost: 0,
      chunksSuppressed: 0,
      chunksDiscarded: 0,
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

      expect(f.calls(), 2);
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
}
