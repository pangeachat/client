import 'dart:async';

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

    test('a fetch that throws PROPAGATES from the guard -- the real production '
        'caller (runVoiceTranscriptEnrichment) wraps showFeedback in its own catch '
        'and swallows+logs it (see stt_send_path_test HIGH-3), so it never '
        'escapes the fire-and-forget nor affects recording', () async {
      await expectLater(
        guardedAnalyticsFeedbackCounts(
          isMounted: () => true,
          fetchGrammar: () async => throw Exception('boom'),
          fetchVocab: () async => 5,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('guardFeedbackDispatch (H2: flag-OFF feedback cannot escape)', () {
    test('a throwing feedback is swallowed + logged; the future completes '
        'normally', () async {
      Object? logged;
      // Must NOT throw (a bare fire-and-forget would otherwise become an
      // unhandled async error on the flag-OFF analytics path).
      await guardFeedbackDispatch(
        () async => throw Exception('overlay/count failed'),
        (e, _) => logged = e,
      );
      expect(logged, isA<Exception>());
    });

    test('a successful feedback runs and does not log', () async {
      var shown = false;
      var logged = false;
      await guardFeedbackDispatch(
        () async => shown = true,
        (_, _) => logged = true,
      );
      expect(shown, isTrue);
      expect(logged, isFalse);
    });

    test('a throwing feedback with an ASYNC-throwing logger (Future.error, like '
        'ErrorHandler.logError) leaks NO unhandled async error', () async {
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        await guardFeedbackDispatch(
          () async => throw Exception('overlay/count failed'),
          // Returns a Future that rejects -- must be contained, not discarded.
          (_, _) => Future<void>.error(Exception('async logger')),
        );
      }, (e, s) => unhandled.add(e));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Teeth: without `if (r is Future) unawaited(r.catchError(...))` in the
      // guard, the logger's rejection escapes to the zone -> RED.
      expect(unhandled, isEmpty);
    });
  });
}
