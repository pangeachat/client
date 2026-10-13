import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

const _room = '!room:example.com';
const _callKey = '\$membership:example.com';
const alice = '@alice:example.com';
const bob = '@bob:example.com';

MatrixEvent _mergedEvent(
  String sender, {
  String eventId = '\$merged:example.com',
  String callKey = _callKey,
  String type = CallAudioMergedContent.relType,
  int ts = 1000,
  List<String> sourceEventIds = const ['\$a:example.com', '\$b:example.com'],
}) => MatrixEvent(
  type: type,
  eventId: eventId,
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
  content: CallAudioMergedContent(
    callKey: callKey,
    url: 'mxc://example.com/merged123',
    mimetype: 'audio/wav',
    size: 8192,
    durationMs: 60000,
    sampleRate: 48000,
    channels: 1,
    codec: kCallAudioCodec,
    sourceEventIds: sourceEventIds,
  ).toJson(),
);

/// A fetcher serving fixed pages, recording how many times it was called.
///
/// Mirrors `transcript_repo_test.dart`'s own `_pages` helper exactly -- same
/// shape, same assertions on the query -- since [fetchCallAudioMerged] reads
/// through the identical [RelationsFetcher] seam.
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
    // Asserted, not ignored -- a fake that answers whatever it is asked would
    // let the reader query the wrong anchor or relation type and still pass.
    expect(roomId, _room);
    expect(eventId, _callKey);
    expect(relType, CallAudioMergedContent.relType);
    froms.add(from);
    final page = pages[index.clamp(0, pages.length - 1)];
    index++;
    return (chunk: page.chunk, nextBatch: page.next);
  }

  return (fetch: fetch, froms: froms);
}

void main() {
  group('fetchCallAudioMerged', () {
    test('an empty relation set returns an empty list', () async {
      final p = _pages([(chunk: <MatrixEvent>[], next: null)]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, isEmpty);
    });

    test(
      'a valid merged recording is read with its sender and timestamp',
      () async {
        final p = _pages([
          (chunk: [_mergedEvent(alice, ts: 500)], next: null),
        ]);

        final recordings = await fetchCallAudioMerged(
          fetch: p.fetch,
          roomId: _room,
          callKey: _callKey,
        );

        expect(recordings, hasLength(1));
        final recording = recordings.single;
        expect(recording.eventId, '\$merged:example.com');
        expect(recording.senderId, alice);
        expect(
          recording.originServerTs,
          DateTime.fromMillisecondsSinceEpoch(500),
        );
        expect(recording.content.callKey, _callKey);
        expect(recording.content.sourceEventIds, [
          '\$a:example.com',
          '\$b:example.com',
        ]);
      },
    );

    test('a malformed merge is skipped, not fatal to the rest', () async {
      // Mirrors fetchCallAudio's own tolerance of a bad half: one unreadable
      // event under this call's anchor must not take the whole read down.
      //
      // The broken event comes FIRST and the valid one SECOND, on purpose: an
      // incorrect early `return` on a parse failure (instead of `continue`)
      // would still pass this test if the valid recording were seen before
      // the broken one, since it would already be in the list by the time the
      // (wrong) early return fired. Ordering it this way means only a genuine
      // "skip and keep going" produces the valid recording at all.
      final broken = MatrixEvent(
        type: CallAudioMergedContent.relType,
        eventId: '\$broken',
        senderId: bob,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1),
        content: const {'nothing': 'useful'},
      );
      final p = _pages([
        (chunk: [broken, _mergedEvent(alice)], next: null),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, hasLength(1));
      expect(recordings.single.senderId, alice);
    });

    test('an event of the wrong TYPE under this relation is ignored', () async {
      // A relation of our type carrying some other event type is not a
      // merged recording; parsing it as one would invent content. The wrong-
      // type event otherwise carries OTHERWISE-VALID merged content (built
      // through the same helper, just with `type` overridden): if it were
      // ONLY the parse-skip catching this event, removing the type check
      // entirely would still leave this test green, since malformed content
      // is skipped either way. Valid content behind the wrong type means the
      // type check itself -- not the parser -- is what this test pins.
      //
      // It also comes FIRST, valid event SECOND -- the same ordering reason
      // as the malformed-merge test above: with the wrong-type event second,
      // a `continue` mistakenly replaced by an early `return` would still
      // pass, since the valid recording is already collected by the time the
      // (wrong) return fires.
      final p = _pages([
        (
          chunk: [
            _mergedEvent(
              bob,
              eventId: '\$notmerged',
              type: 'm.room.message',
              ts: 2,
            ),
            _mergedEvent(alice),
          ],
          next: null,
        ),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, hasLength(1));
      expect(recordings.single.senderId, alice);
    });

    test('a merge naming a DIFFERENT call is ignored', () async {
      // Rejected event FIRST, valid event SECOND -- same reasoning as above:
      // rules out a `continue` mistakenly replaced by an early `return`.
      final p = _pages([
        (
          chunk: [
            _mergedEvent(
              bob,
              eventId: '\$otherMerge',
              callKey: '\$other-call:example.com',
            ),
            _mergedEvent(alice),
          ],
          next: null,
        ),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, hasLength(1));
      expect(recordings.single.senderId, alice);
    });

    test('a rejected event still consumes the EVENT ceiling budget', () async {
      // `seen` is incremented for EVERY event examined, before any of the
      // type/parse/call-key checks run -- so a page mixing rejected and
      // valid events must not let a rejected one "not count" and leave more
      // budget for the valid ones than the ceiling actually allows. None of
      // the tests above prove this: each puts only ONE rejected event
      // alongside untouched-by-the-ceiling valid ones. Here, with
      // maxEvents=2, a rejected event followed by two otherwise-valid ones
      // must leave room for only ONE of them.
      final p = _pages([
        (
          chunk: [
            _mergedEvent(bob, eventId: '\$rejected', type: 'm.room.message'),
            _mergedEvent(alice, eventId: '\$m1', ts: 2),
            _mergedEvent(alice, eventId: '\$m2', ts: 3),
          ],
          next: 'more',
        ),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        maxEvents: 2,
      );

      expect(recordings, hasLength(1));
      expect(recordings.single.eventId, '\$m1');
    });

    test('pages until the server says there is no more', () async {
      final p = _pages([
        (chunk: [_mergedEvent(alice, eventId: '\$m1', ts: 1)], next: 'tok1'),
        (chunk: [_mergedEvent(bob, eventId: '\$m2', ts: 2)], next: null),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(p.froms, [null, 'tok1'], reason: 'the token must be carried');
      expect(recordings.map((r) => r.senderId), [alice, bob]);
    });

    test('the default PAGE ceiling is exactly kMaxRelationPages, not a '
        'smaller or larger hardcoded value', () async {
      // maxPages is omitted here on purpose -- every other page-ceiling
      // test above passes an explicit, smaller cap, so none of them
      // exercise the DEFAULT (`kMaxRelationPages`, the same shared
      // constant `fetchCallAudio` itself defaults to). One MORE page than
      // the ceiling is offered, each with a single valid event, so the
      // exact truncation point pins the exact default: a smaller default
      // stops with fewer recordings than expected, a larger (or missing)
      // default reads all `kMaxRelationPages + 1` pages instead of
      // stopping at the true ceiling.
      final p = _pages([
        for (var page = 0; page < kMaxRelationPages + 1; page++)
          (
            chunk: [_mergedEvent(alice, eventId: '\$p$page', ts: page)],
            next: page < kMaxRelationPages ? 'tok$page' : null,
          ),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, hasLength(kMaxRelationPages));
      expect(p.froms, hasLength(kMaxRelationPages));
    });

    test('the default EVENT ceiling is exactly kMaxRelationEvents, not a '
        'smaller or larger hardcoded value', () async {
      // Same reasoning as the page-ceiling test above, for maxEvents:
      // kMaxRelationEvents + 1 valid events in a single page pins the
      // exact default truncation point.
      final events = [
        for (var i = 0; i < kMaxRelationEvents + 1; i++)
          _mergedEvent(alice, eventId: '\$e$i', ts: i),
      ];
      final p = _pages([(chunk: events, next: null)]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
      );

      expect(recordings, hasLength(kMaxRelationEvents));
    });

    test('reading stops at the PAGE ceiling', () async {
      // A room member can write endlessly related events; stopping is the
      // reader's own doing and must not hang the caller.
      final p = _pages([
        (chunk: [_mergedEvent(alice, eventId: '\$m1', ts: 1)], next: 'more'),
      ]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        maxPages: 3,
      );

      expect(p.froms, hasLength(3), reason: 'stops at the cap');
      expect(recordings, hasLength(3));
    });

    test('reading stops at the EVENT ceiling, mid-page', () async {
      final events = [
        for (var i = 0; i < 10; i++)
          _mergedEvent(alice, eventId: '\$m$i', ts: i),
      ];
      final p = _pages([(chunk: events, next: 'more')]);

      final recordings = await fetchCallAudioMerged(
        fetch: p.fetch,
        roomId: _room,
        callKey: _callKey,
        maxEvents: 4,
      );

      expect(recordings, hasLength(4));
      // The cap was hit inside the FIRST page, so a second page must never be
      // requested -- otherwise the ceiling exists only in name.
      expect(p.froms, [null]);
    });
  });
}
