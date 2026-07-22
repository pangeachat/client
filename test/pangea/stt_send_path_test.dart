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
/// The coordinator (`runVoiceTranscriptEnrichment`) carries all of D7's
/// analytics semantics; it is fully injectable so these run deterministically
/// with no Matrix/widget harness (mirroring R0's isolation of the Matrix
/// plumbing behind a pure seam).

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
        senderId: _me,
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
      'BLOCKER guard: an exhausted-fallback (empty results) baseStt is a total '
      'no-op -- no enrich, no analytics, no attach, no crash',
      () async {
        var enrichCalls = 0;
        var analyticsCalls = 0;
        var attachCalls = 0;

        await runVoiceTranscriptEnrichment(
          // results: [] -> no usable transcript; reading .transcript would throw.
          baseStt: SpeechToTextResponseModel(results: const []),
          snapshot: _snapshot,
          senderId: _me,
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
          senderId: _me,
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

    test('own-ness is bound to identity: a FOREIGN senderId does NOT record '
        '(and attach still runs, best-effort display repair)', () async {
      var analyticsCalls = 0;
      var attachCalls = 0;

      await runVoiceTranscriptEnrichment(
        baseStt: _skipTokenizeBase(),
        snapshot: _snapshot,
        senderId: '@someone-else:server',
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
    });

    test(
      'a tokenizer error is caught: no analytics, no attach, no crash',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;
        Object? loggedError;

        await runVoiceTranscriptEnrichment(
          baseStt: _skipTokenizeBase(),
          snapshot: _snapshot,
          senderId: _me,
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
