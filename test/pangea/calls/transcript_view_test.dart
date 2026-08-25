import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_view.dart';
import '../get_test_client.dart';

const _callKey = r'$membership:fakeServer.notExisting';
const _me = '@test:fakeServer.notExisting';
const _peer = '@peer:fakeServer.notExisting';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    bool drainComplete = true,
    bool declared = true,
  }) => MatrixEvent(
    type: CallTranscriptContent.relType,
    eventId: '\$half-$sender',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    content: {
      'call_key': _callKey,
      'segments': [
        for (final t in texts) {'text': t},
      ],
      // From the writer's own serialiser, so a fixture cannot drift out of the
      // declaration contract when a field is added to it.
      if (declared)
        ...HalfAccounting(
          chunksCaptured: captured,
          chunksTranscribed: transcribed,
          chunksLost: lost,
          captureRefused: false,
          drainComplete: drainComplete,
        ).toJson(),
    },
  );

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
        find.textContaining('not shown'),
        findsOneWidget,
        reason: 'the screen admits it could not read all of this call',
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

      expect(find.textContaining('not shown'), findsOneWidget);
      expect(find.textContaining('No transcript from'), findsNothing);
    });
  });

  group('callParticipants', () {
    test('is derived locally and cannot be influenced by room content', () {
      expect(callParticipants(me: _me, peerId: _peer), [_peer, _me]);
    });

    test('with no peer known, no claim is made about a second person', () {
      // Honest degradation: showing only our own half says nothing false
      // about anyone. Filling the gap from the card is what let a stranger in.
      expect(callParticipants(me: _me, peerId: null), [_me]);
    });

    test('is stable across reads, so sections do not reorder', () {
      expect(
        callParticipants(me: _me, peerId: _peer),
        callParticipants(me: _me, peerId: _peer),
      );
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
