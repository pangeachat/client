import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_selection.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';

const _callKey = r'$membership:example.com';
const _sender = '@alice:example.com';

/// A merged recording carrying real [CallAudioMergedContent], so
/// `coverageCardinality` and `coverageHash` are the values the player's own
/// dedup computes -- never stubbed -- and a test that turns on one of them is
/// exercising the same code the app does.
CallAudioMergedRecording rec({
  required String eventId,
  required List<String> sourceEventIds,
}) => CallAudioMergedRecording(
  eventId: eventId,
  senderId: _sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
  content: CallAudioMergedContent(
    callKey: _callKey,
    url: 'mxc://example.com/merged',
    mimetype: 'audio/wav',
    size: 8192,
    durationMs: 60000,
    sampleRate: 48000,
    channels: 1,
    codec: kCallAudioCodec,
    sourceEventIds: sourceEventIds,
  ),
);

void main() {
  group('selectMergedRow', () {
    test('more than two halves suppresses the row, even with a merge present', () {
      // The enforced v1-scope guarantee: a mid-call device switch (>2 halves)
      // gets NO merged row, EVEN IF a stale two-half merge was already posted.
      // The suppression is about the number of halves the room shows, not about
      // what merged events happen to exist.
      final merged = [
        rec(eventId: r'$m', sourceEventIds: [r'$a', r'$b']),
      ];

      expect(selectMergedRow(merged, 3), isNull);
      expect(selectMergedRow(merged, 4), isNull);
    });

    test('no merged events yields no row', () {
      expect(selectMergedRow(const [], 2), isNull);
      // And an empty list is not rescued by a small half count either.
      expect(selectMergedRow(const [], 0), isNull);
    });

    test('exactly two halves with one merge shows that merge', () {
      final only = rec(eventId: r'$m', sourceEventIds: [r'$a', r'$b']);

      expect(selectMergedRow([only], 2), same(only));
    });

    test('a single half does not suppress the row', () {
      // Only MORE THAN TWO halves suppresses; one visible half with a merge
      // present (a half still loading, say) is not the switched-call case.
      final only = rec(eventId: r'$m', sourceEventIds: [r'$a', r'$b']);

      expect(selectMergedRow([only], 1), same(only));
      expect(selectMergedRow([only], 0), same(only));
    });

    test('the greatest coverage cardinality wins', () {
      // Two merges of the same call: one covers three halves, one covers two.
      // The fuller recording wins on cardinality alone -- and the loser is
      // given the LOWER event id, so a comparator that dropped cardinality and
      // fell to the id tiebreak would pick the wrong one.
      final fuller = rec(
        eventId: r'$z-fuller',
        sourceEventIds: [r'$a', r'$b', r'$c'],
      );
      final smaller = rec(
        eventId: r'$a-smaller',
        sourceEventIds: [r'$a', r'$b'],
      );

      expect(fuller.content.coverageCardinality, 3);
      expect(smaller.content.coverageCardinality, 2);
      // Order in the input puts the loser first, so a function that just
      // returned `first` without sorting would also fail.
      expect(selectMergedRow([smaller, fuller], 2), same(fuller));
    });

    test('a cardinality tie breaks to the LOWER coverage hash', () {
      // Same cardinality, different coverage -> different, stable hashes. The
      // lower hash wins. The event ids are assigned so the LOWER-hash row has
      // the GREATER event id: only the hash rule picks it, and a comparator
      // that dropped the hash key (falling straight to the id) would pick the
      // other one instead -- the mutation this test exists to catch.
      const setOne = [r'$p', r'$q'];
      const setTwo = [r'$r', r'$s'];
      final hashOne = rec(
        eventId: r'$probe',
        sourceEventIds: setOne,
      ).content.coverageHash;
      final hashTwo = rec(
        eventId: r'$probe',
        sourceEventIds: setTwo,
      ).content.coverageHash;
      expect(
        hashOne,
        isNot(hashTwo),
        reason: 'two different coverage sets must hash differently',
      );

      // The lower-hash row is the winner; give it the GREATER event id so the
      // id tiebreak points the OTHER way.
      final lowerIsOne = hashOne.compareTo(hashTwo) < 0;
      final lowerHash = rec(
        eventId: r'$zzz',
        sourceEventIds: lowerIsOne ? setOne : setTwo,
      );
      final higherHash = rec(
        eventId: r'$aaa',
        sourceEventIds: lowerIsOne ? setTwo : setOne,
      );
      expect(
        lowerHash.content.coverageCardinality,
        higherHash.content.coverageCardinality,
        reason: 'the cardinality must be tied for the hash rule to decide',
      );

      expect(selectMergedRow([higherHash, lowerHash], 2), same(lowerHash));
    });

    test('a hash tie breaks to the LOWER event id', () {
      // Identical coverage -> identical cardinality AND identical hash, so only
      // the event id is left to decide. The lower id wins; a comparator that
      // swapped the id direction would return the other.
      const coverage = [r'$a', r'$b'];
      final lowerId = rec(eventId: r'$aaa', sourceEventIds: coverage);
      final higherId = rec(eventId: r'$bbb', sourceEventIds: coverage);
      expect(
        lowerId.content.coverageHash,
        higherId.content.coverageHash,
        reason: 'identical coverage must produce an identical hash',
      );

      expect(selectMergedRow([higherId, lowerId], 2), same(lowerId));
    });

    test('the input list is not mutated', () {
      // Ordered so the winner is NOT already first: selecting it must sort a
      // copy, never reorder the caller's own list.
      final smaller = rec(eventId: r'$a', sourceEventIds: [r'$a', r'$b']);
      final fuller = rec(eventId: r'$b', sourceEventIds: [r'$a', r'$b', r'$c']);
      final input = [smaller, fuller];
      final orderBefore = List.of(input);

      final winner = selectMergedRow(input, 2);

      expect(winner, same(fuller));
      expect(
        input,
        orderEquals(orderBefore),
        reason: 'selection sorts a copy and leaves the input untouched',
      );
    });
  });
}

/// Matches a list whose elements are `identical` to [expected], in order --
/// so the no-mutation test asserts the exact objects stayed put, not merely
/// that an equal-looking list came back.
Matcher orderEquals(List<Object?> expected) =>
    predicate<List<Object?>>((actual) {
      if (actual.length != expected.length) return false;
      for (var i = 0; i < actual.length; i++) {
        if (!identical(actual[i], expected[i])) return false;
      }
      return true;
    }, 'is the same objects in the same order');
