import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

const _room = '!room:example.com';
const _callKey = '\$membership:example.com';
const alice = '@alice:example.com';
const bob = '@bob:example.com';

MatrixEvent _half(
  String sender, {
  List<String> texts = const ['hola'],
  String callKey = _callKey,
  String type = CallTranscriptContent.relType,
  int ts = 1000,
}) => MatrixEvent(
  type: type,
  eventId: '\$ev-$sender-$ts',
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  content: {
    'call_key': callKey,
    'segments': [
      for (final t in texts) {'text': t},
    ],
    // Spread from the writer's OWN serializer rather than hand-rolled. A
    // hand-written copy of the wire shape falls out of the declaration
    // contract the moment a field is added to it, and it does so silently:
    // the half reads undeclared, and the failure surfaces as an unrelated
    // "why is this incomplete" somewhere else.
    ...const HalfAccounting(
      chunksCaptured: 2,
      chunksTranscribed: 2,
      chunksLost: 0,
      drainComplete: true,
    ).toJson(),
  },
);

/// A fetcher serving fixed pages, recording how many times it was called.
({RelationsFetcher fetch, List<String?> froms}) _pages(
  List<({List<MatrixEvent> chunk, String? next})> pages,
) {
  final froms = <String?>[];
  var index = 0;
  Future<({List<MatrixEvent> chunk, String? nextBatch})> fetch({
    required String roomId,
    required String eventId,
    required String relType,
    String? from,
  }) async {
    // Asserted, not ignored. A fake that answers whatever it is asked would let
    // the reader query the wrong anchor or relation type and still pass every
    // test, while production found no halves and called both people absent.
    expect(roomId, _room);
    expect(eventId, _callKey);
    expect(relType, CallTranscriptContent.relType);
    froms.add(from);
    final page = pages[index.clamp(0, pages.length - 1)];
    index++;
    return (chunk: page.chunk, nextBatch: page.next);
  }

  return (fetch: fetch, froms: froms);
}

TranscriptHalf _halfFor(CallTranscript t, String sender) =>
    t.halves.firstWhere((h) => h.senderId == sender);

void main() {
  group('fetchCallTranscript', () {
    test('reads both halves and reports them present', () async {
      final p = _pages([
        (chunk: [_half(alice), _half(bob)], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice, bob]);
      expect(
        transcript.halves.map((h) => h.state),
        everyElement(HalfState.present),
      );
    });

    test('pages until the server says there is no more', () async {
      final p = _pages([
        (chunk: [_half(alice)], next: 'tok1'),
        (chunk: [_half(bob)], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(p.froms, [null, 'tok1'], reason: 'the token must be carried');
      expect(transcript.halves.map((h) => h.state), [
        HalfState.present,
        HalfState.present,
      ]);
    });

    test('a half only reachable on a LATER page is still found', () async {
      // Stopping at the first page would report bob absent -- saying he was
      // silent when we simply had not looked yet.
      final p = _pages([
        (chunk: [_half(alice)], next: 'tok1'),
        (chunk: [_half(bob)], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, isNot(HalfState.absent));
      expect(_halfFor(transcript, bob).segments, isNotEmpty);
    });

    test('absence is only concluded from an EXHAUSTED read', () async {
      final p = _pages([
        (chunk: [_half(alice)], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, HalfState.absent);
      expect(transcript.readerStoppedEarly, isFalse);
    });

    test('hitting the PAGE cap reports incomplete, never absent', () async {
      // A room member can write endlessly related events. Stopping is correct;
      // calling the result "absent" would blame the other person for our cap.
      final p = _pages([
        (chunk: [_half(alice)], next: 'more'),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
        maxPages: 3,
      );

      expect(p.froms, hasLength(3), reason: 'stops at the cap');
      expect(_halfFor(transcript, bob).state, HalfState.incomplete);
      expect(_halfFor(transcript, alice).state, HalfState.incomplete);
      expect(transcript.readerStoppedEarly, isTrue);
    });

    test('hitting the EVENT cap reports incomplete, never absent', () async {
      final p = _pages([
        (chunk: [for (var i = 0; i < 50; i++) _half(alice, ts: i)], next: 'm'),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
        maxEvents: 10,
      );

      expect(_halfFor(transcript, bob).state, HalfState.incomplete);
      expect(transcript.readerStoppedEarly, isTrue);
    });

    test('a cap hit inside the LAST page is not exhaustion', () async {
      // The page has no next token, so the read looks finished -- but the cap
      // stopped it part-way through, and the half it never reached must not be
      // reported as someone having said nothing.
      final p = _pages([
        (
          chunk:
              [for (var i = 0; i < 20; i++) _half(alice, ts: i)] + [_half(bob)],
          next: null,
        ),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
        maxEvents: 5,
      );

      expect(_halfFor(transcript, bob).state, HalfState.incomplete);
      expect(transcript.readerStoppedEarly, isTrue);
    });

    test('an event of the wrong TYPE under this relation is ignored', () async {
      // A relation of our type carrying some other event type is not a
      // transcript; parsing it as one would invent content.
      final p = _pages([
        (
          chunk: [
            _half(alice),
            _half(bob, type: 'm.room.message', texts: ['not a transcript']),
          ],
          next: null,
        ),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, HalfState.absent);
    });

    test('a half naming a DIFFERENT call is ignored', () async {
      final p = _pages([
        (
          chunk: [
            _half(alice),
            _half(bob, callKey: '\$other:example.com'),
          ],
          next: null,
        ),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, bob).state, HalfState.absent);
      expect(_halfFor(transcript, alice).segments, isNotEmpty);
    });

    test('a malformed half does not take the read down', () async {
      final broken = MatrixEvent(
        type: CallTranscriptContent.relType,
        eventId: '\$broken',
        senderId: bob,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
        content: const {'nothing': 'useful'},
      );
      final p = _pages([
        (chunk: [_half(alice), broken], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice, bob],
      );

      expect(_halfFor(transcript, alice).segments, isNotEmpty);
      expect(_halfFor(transcript, bob).state, HalfState.absent);
    });

    test('a non-participant who wrote a half gets no section', () async {
      final p = _pages([
        (chunk: [_half(alice), _half('@mallory:evil.com')], next: null),
      ]);

      final transcript = await fetchCallTranscript(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        expectedSenders: [alice],
      );

      expect(transcript.halves.map((h) => h.senderId), [alice]);
    });
  });
}
