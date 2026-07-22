import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/voice_analytics_feedback.dart';

/// Fix 2 — the analytics-feedback overlay must NEVER touch a disposed context
/// after an await. `guardedAnalyticsFeedbackCounts` re-checks `mounted` after
/// each fetch and bails cleanly (null), so navigation during the two awaits can
/// never throw a late-context error.

void main() {
  group('guardedAnalyticsFeedbackCounts', () {
    test(
      'returns both counts when the widget stays mounted throughout',
      () async {
        final counts = await guardedAnalyticsFeedbackCounts(
          isMounted: () => true,
          fetchGrammar: () async => 3,
          fetchVocab: () async => 5,
        );
        expect(counts, isNotNull);
        expect(counts!.grammar, 3);
        expect(counts.vocab, 5);
      },
    );

    test(
      'disposed DURING the first fetch -> bails null and never runs the second '
      'fetch (never reaches the context-touching render)',
      () async {
        var mounted = true;
        var vocabFetched = false;
        final counts = await guardedAnalyticsFeedbackCounts(
          isMounted: () => mounted,
          fetchGrammar: () async {
            mounted = false; // navigate away mid-await
            return 3;
          },
          fetchVocab: () async {
            vocabFetched = true;
            return 5;
          },
        );
        // Teeth: without the post-await mounted re-check this would return
        // counts and the caller would touch a defunct context.
        expect(counts, isNull);
        expect(vocabFetched, isFalse);
      },
    );

    test('disposed DURING the second fetch -> bails null', () async {
      var mounted = true;
      final counts = await guardedAnalyticsFeedbackCounts(
        isMounted: () => mounted,
        fetchGrammar: () async => 3,
        fetchVocab: () async {
          mounted = false;
          return 5;
        },
      );
      expect(counts, isNull);
    });

    test(
      'a fetch that throws propagates (best-effort caller catches)',
      () async {
        await expectLater(
          guardedAnalyticsFeedbackCounts(
            isMounted: () => true,
            fetchGrammar: () async => throw Exception('boom'),
            fetchVocab: () async => 5,
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
