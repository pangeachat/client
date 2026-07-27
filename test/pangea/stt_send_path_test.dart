import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';

/// P1b.4 — the flag-gated send path's background coordinator, analytics
/// recorder, and interim embed.
///
/// The coordinator (`runVoiceTranscriptEnrichment`) OWNS the orchestration
/// (real-event sender lookup, record, feedback dispatch, attach) and ALL
/// error-wrapping, so it is unit-tested with teeth here; chat.dart is left as
/// thin wiring. Every dependency is injected, so these run deterministically
/// with no Matrix/widget harness.

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

SpeechToTextResponseModel _skipTokenizeBase() {
  final raw = File(
    'test/pangea/stt_golden/choreo_response_skip_tokenize.json',
  ).readAsStringSync();
  return SpeechToTextResponseModel.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
}

SpeechToTextResponseModel _rich() =>
    _skipTokenizeBase().withFirstTranscriptTokens([
      STTToken(token: _token('hola', 0)),
      STTToken(token: _token('mundo', 5)),
    ]);

const _snapshot = SttLangSnapshot(
  fullText: 'hola mundo',
  langCode: 'es',
  senderL1: 'en',
  senderL2: 'es',
);

const _me = '@me:server';

Future<String?> _ownSender() async => _me;

/// A no-op `VoiceAnalyticsSink` for the routing-predicate tests (the predicate
/// only checks presence). A function declaration -- not a variable -- so its
/// closure param types are inferred from the return context with no extra
/// import.
VoiceAnalyticsSink _noopSink() => (_, _, _) async {};

void main() {
  group('interim user_stt embed (flag ON)', () {
    test('built from the skip_tokenize response: text + word_timings + '
        'stt_tokens:[], and re-parses (bot-parseable)', () {
      final embed = _skipTokenizeBase().toJson();
      final transcript =
          (embed['results'][0]['transcripts'][0]) as Map<String, dynamic>;

      expect(transcript['stt_tokens'], isEmpty);
      expect(transcript['transcript'], 'hola mundo');
      expect(transcript['lang_code'], 'es');
      expect(transcript['word_timings'], isNotNull);

      final reparsed = SpeechToTextResponseModel.fromJson(
        Map<String, dynamic>.from(embed),
      );
      expect(reparsed.hasUsableTranscript, isTrue);
      expect(reparsed.hasUsableTokens, isFalse);
    });
  });

  group('runVoiceTranscriptEnrichment (D7 analytics semantics)', () {
    test('returns/records only after enrich resolves; not before', () async {
      final enrichGate = Completer<SpeechToTextResponseModel>();
      var analyticsCalls = 0;

      final future = runVoiceTranscriptEnrichment(
        baseStt: _skipTokenizeBase(),
        snapshot: _snapshot,
        resolveSenderId: _ownSender,
        clientUserId: _me,
        enrich: (_, _) => enrichGate.future,
        recordAnalytics: (_) async => analyticsCalls++,
        attach: (_) async => null,
      );

      await Future<void>.delayed(Duration.zero);
      expect(analyticsCalls, 0);

      enrichGate.complete(_rich());
      await future;
      expect(analyticsCalls, 1);
    });

    test(
      'INDEPENDENCE (i): a never-completing ATTACH does NOT block the analytics '
      'chain -- record still runs to completion',
      () async {
        final neverAttach = Completer<void>(); // gate: attach hangs forever
        final recorded = Completer<void>();

        // Fire-and-forget: do NOT await the coordinator (it stays pending on the
        // hung attach branch). We assert only that the OTHER branch completed.
        unawaited(
          runVoiceTranscriptEnrichment(
            baseStt: _skipTokenizeBase(),
            snapshot: _snapshot,
            resolveSenderId: _ownSender,
            clientUserId: _me,
            enrich: (b, _) async => b.withFirstTranscriptTokens([
              STTToken(token: _token('hola', 0)),
            ]),
            recordAnalytics: (_) async => recorded.complete(),
            attach: (_) async {
              await neverAttach.future;
              return null;
            },
          ),
        );

        // Teeth: a sequential attach-then-analytics chain would gate record on
        // the hung attach -> recorded never completes -> timeout -> RED.
        await recorded.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'analytics was gated on the hung attach (branches not independent)',
          ),
        );
        expect(recorded.isCompleted, isTrue);
      },
    );

    test(
      'INDEPENDENCE (ii): a never-completing SENDER LOOKUP does NOT block attach '
      '-- token persistence still completes',
      () async {
        final neverLookup = Completer<String?>(); // resolveSenderId hangs
        final attached = Completer<void>();

        unawaited(
          runVoiceTranscriptEnrichment(
            baseStt: _skipTokenizeBase(),
            snapshot: _snapshot,
            resolveSenderId: () => neverLookup.future,
            clientUserId: _me,
            enrich: (b, _) async => b.withFirstTranscriptTokens([
              STTToken(token: _token('hola', 0)),
            ]),
            recordAnalytics: (_) async {},
            attach: (_) async {
              attached.complete();
              return null;
            },
          ),
        );

        // Teeth: a sender lookup that gates enrich/attach (or an analytics-first
        // chain) would leave attach unrun -> attached never completes -> RED.
        await attached.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'attach was gated on the hung sender lookup (branches not '
            'independent)',
          ),
        );
        expect(attached.isCompleted, isTrue);
      },
    );

    test(
      'BLOCKER guard: an exhausted-fallback (empty results) baseStt is a total '
      'no-op -- no lookup, no enrich, no analytics, no attach, no crash',
      () async {
        var lookupCalls = 0;
        var enrichCalls = 0;
        var analyticsCalls = 0;
        var attachCalls = 0;

        await runVoiceTranscriptEnrichment(
          // results: [] -> no usable transcript; reading .transcript would throw.
          baseStt: SpeechToTextResponseModel(results: const []),
          snapshot: _snapshot,
          resolveSenderId: () async {
            lookupCalls++;
            return _me;
          },
          clientUserId: _me,
          enrich: (_, _) async {
            enrichCalls++;
            return _rich();
          },
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async {
            attachCalls++;
            return null;
          },
        );

        expect(lookupCalls, 0);
        expect(enrichCalls, 0);
        expect(analyticsCalls, 0);
        expect(attachCalls, 0);
      },
    );

    test(
      'analytics fires once for own message even when attach returns null',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async {
            attachCalls++;
            return null; // sendPangeaEvent can return null after delivering
          },
        );

        expect(
          analyticsCalls,
          1,
          reason: 'analytics gates on enrich, not attach',
        );
        expect(attachCalls, 1);
      },
    );

    test(
      'own-ness is bound to the RESOLVED event sender: a FOREIGN senderId does '
      'NOT record (attach still runs)',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: () async => '@someone-else:server',
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async {
            attachCalls++;
            return null;
          },
        );

        expect(analyticsCalls, 0, reason: 'never record a foreign sender');
        expect(attachCalls, 1);
      },
    );

    test(
      'HIGH-2: a THROWING sender lookup is caught (routed to onError), the '
      'future completes normally, and nothing records (senderId null -> not own)',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;
        Object? loggedError;

        // Must complete without throwing (no unhandled async error escapes).
        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: () async => throw Exception('getEventById failed'),
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async {
            attachCalls++;
            return null;
          },
          onError: (e, _) => loggedError = e,
        );

        expect(loggedError, isA<Exception>());
        expect(analyticsCalls, 0, reason: 'lookup failed -> senderId null');
        // Enrich + attach are independent of the lookup; attach still runs.
        expect(attachCalls, 1);
      },
    );

    test(
      'HIGH-3: a THROWING feedback is swallowed (routed to onError); recording '
      'STILL happened and the future completes normally',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;
        Object? loggedError;

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => analyticsCalls++,
          showFeedback: (_) async => throw Exception('overlay/count failed'),
          attach: (_) async {
            attachCalls++;
            return null;
          },
          onError: (e, _) => loggedError = e,
        );

        expect(analyticsCalls, 1, reason: 'feedback failure must not abort it');
        expect(loggedError, isA<Exception>());
        expect(attachCalls, 1);
      },
    );

    test(
      'feedback runs for an own message AFTER recording, and NOT for a foreign '
      'one',
      () async {
        final order = <String>[];

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => order.add('record'),
          showFeedback: (_) async => order.add('feedback'),
          attach: (_) async => null,
        );
        expect(order, ['record', 'feedback']);

        final foreign = <String>[];
        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: () async => '@other:server',
          clientUserId: _me,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => foreign.add('record'),
          showFeedback: (_) async => foreign.add('feedback'),
          attach: (_) async => null,
        );
        expect(foreign, isEmpty);
      },
    );

    test(
      'a tokenizer error is caught: no analytics, no attach, no crash',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;
        Object? loggedError;

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (_, _) async => throw Exception('tokenize failed'),
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async {
            attachCalls++;
            return null;
          },
          onError: (e, _) => loggedError = e,
        );

        expect(analyticsCalls, 0);
        expect(attachCalls, 0);
        expect(loggedError, isA<Exception>());
      },
    );

    test(
      'SF: a SYNC-throwing onError logger does not reject the coordinator',
      () async {
        // Must complete without throwing even though enrich fails AND the
        // logger itself throws synchronously.
        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (_, _) async => throw Exception('tokenize failed'),
          recordAnalytics: (_) async {},
          attach: (_) async => null,
          onError: (_, _) => throw Exception('logger blew up'),
        );
        expect(true, isTrue); // reaching here == no rethrow
      },
    );

    test('SF: an ASYNC-throwing onError logger (returns Future.error, like '
        'ErrorHandler.logError) leaks NO unhandled async error', () async {
      final unhandled = <Object>[];

      await runZonedGuarded(() async {
        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          resolveSenderId: _ownSender,
          clientUserId: _me,
          enrich: (_, _) async => throw Exception('tokenize failed'),
          recordAnalytics: (_) async {},
          attach: (_) async => null,
          // Mirrors production `(e,s) => ErrorHandler.logError(...)` which
          // returns a Future<void>. Teeth: without the `if (r is Future)`
          // containment this rejection escapes to the zone -> RED.
          onError: (_, _) => Future<void>.error(Exception('async logger')),
        );
      }, (e, s) => unhandled.add(e));

      // Drain microtasks so any leaked rejection would have surfaced.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(unhandled, isEmpty);
    });
  });

  group('isOwnSender (analytics gate identity)', () {
    test('true only when a non-null senderId equals clientUserId', () {
      expect(isOwnSender(_me, _me), isTrue);
      expect(isOwnSender('@other:server', _me), isFalse);
      expect(isOwnSender(null, _me), isFalse);
      expect(isOwnSender(_me, null), isFalse);
      expect(isOwnSender(null, null), isFalse);
    });
  });

  group('shouldScheduleDecoupledEnrichment (flag routing decision)', () {
    test(
      'flag ON + snapshot + sink -> true (take the background enrichment path)',
      () {
        expect(
          shouldScheduleDecoupledEnrichment(
            decoupleFlag: true,
            snapshot: _snapshot,
            sink: _noopSink(),
          ),
          isTrue,
        );
      },
    );

    test('flag OFF -> false (take the legacy inline analytics path)', () {
      expect(
        shouldScheduleDecoupledEnrichment(
          decoupleFlag: false,
          snapshot: _snapshot,
          sink: _noopSink(),
        ),
        isFalse,
      );
    });

    test(
      'flag ON but NULL snapshot -> false (non-usable transcript: no background '
      'work)',
      () {
        expect(
          shouldScheduleDecoupledEnrichment(
            decoupleFlag: true,
            snapshot: null,
            sink: _noopSink(),
          ),
          isFalse,
        );
      },
    );

    test('flag ON but NULL sink -> false', () {
      expect(
        shouldScheduleDecoupledEnrichment(
          decoupleFlag: true,
          snapshot: _snapshot,
          sink: null,
        ),
        isFalse,
      );
    });
  });

  group('buildVoiceAnalyticsRecorder — lifecycle independence', () {
    test('records via the sink CAPTURED at build even after the widget is '
        'disposed; a late context read would have thrown', () async {
      final ctx = _AnalyticsContext();

      // PRODUCTION pattern (chat.dart): resolve the analytics sink while the
      // widget is live and CAPTURE it into the recorder.
      final recorder = buildVoiceAnalyticsRecorder(
        roomId: '!r:server',
        eventId: r'$audio:server',
        sink: ctx.sink,
      );

      // Navigate away / dispose the chat BEFORE the tokenize resolves.
      ctx.disposed = true;

      // The recorder still records: it holds the captured sink, not a context.
      await recorder(_rich());
      expect(ctx.calls, 1);

      // Teeth: had the recorder read the context LATE (post-dispose) instead
      // of capturing, it would have thrown -- exactly the regression the
      // capture prevents.
      expect(() => ctx.sink, throwsStateError);
    });

    test('no-ops when the enriched STT has no usable tokens', () async {
      final ctx = _AnalyticsContext();
      final recorder = buildVoiceAnalyticsRecorder(
        roomId: '!r:server',
        eventId: r'$audio:server',
        sink: ctx.sink,
      );
      // A token-less STT: nothing to score.
      await recorder(_skipTokenizeBase());
      expect(ctx.calls, 0);
    });
  });

  group('voiceTranscriptDecoupleEnabled flag plumbing', () {
    test('AppConfigOverride defaults the flag to null (off)', () {
      expect(const AppConfigOverride().voiceTranscriptDecoupleEnabled, isNull);
    });

    test('the flag round-trips through AppConfigOverride JSON', () {
      final override = AppConfigOverride.fromJson(const {
        'voiceTranscriptDecoupleEnabled': true,
      });
      expect(override.voiceTranscriptDecoupleEnabled, isTrue);
      expect(override.toJson()['voiceTranscriptDecoupleEnabled'], isTrue);
      expect(
        AppConfigOverride.fromJson(const {}).voiceTranscriptDecoupleEnabled,
        isNull,
      );
    });
  });
}

/// Mirrors `Matrix.of(context).analyticsDataService`: the sink is readable only
/// while "live"; a read after [disposed] throws, exactly as a defunct
/// `BuildContext` does. Capturing [sink] BEFORE dispose is what makes recording
/// lifecycle-independent.
class _AnalyticsContext {
  bool disposed = false;
  int calls = 0;

  VoiceAnalyticsSink get sink {
    if (disposed) {
      throw StateError('context defunct — Matrix.of(context) would throw here');
    }
    return (_, _, _) async => calls++;
  }
}
