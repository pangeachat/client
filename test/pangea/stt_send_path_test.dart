import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';

/// P1b.4 — the flag-gated send path's background coordinator + interim embed.
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

const _snapshot = SttLangSnapshot(
  fullText: 'hola mundo',
  langCode: 'es',
  senderL1: 'en',
  senderL2: 'es',
);

void main() {
  group('interim user_stt embed (flag ON)', () {
    test('built from the skip_tokenize response: text + word_timings + '
        'stt_tokens:[], and re-parses (bot-parseable)', () {
      // The embed the client writes to the m.audio event is exactly the
      // skip_tokenize response serialized -- no new golden fixture needed.
      final embed = _skipTokenizeBase().toJson();
      final transcript =
          (embed['results'][0]['transcripts'][0]) as Map<String, dynamic>;

      expect(transcript['stt_tokens'], isEmpty);
      expect(transcript['transcript'], 'hola mundo');
      expect(transcript['lang_code'], 'es');
      expect(transcript['word_timings'], isNotNull);

      // The bot re-parses the embed via the same model; it must be usable
      // text (so the bot replies) but carry no tokens yet.
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
      final base = _skipTokenizeBase();

      final future = runVoiceTranscriptEnrichment(
        baseStt: base,
        snapshot: _snapshot,
        isOwnMessage: true,
        enrich: (_, _) => enrichGate.future,
        recordAnalytics: (_) async => analyticsCalls++,
        attach: (_) async => null,
      );

      // Nothing has been recorded while enrich is still pending.
      await Future<void>.delayed(Duration.zero);
      expect(analyticsCalls, 0);

      enrichGate.complete(
        base.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
      );
      await future;
      expect(analyticsCalls, 1);
    });

    test(
      'lifecycle-independence: enrich resolving AFTER the widget is "disposed" '
      'still records analytics',
      () async {
        final enrichGate = Completer<SpeechToTextResponseModel>();
        var disposed = false;
        var analyticsCalls = 0;
        final base = _skipTokenizeBase();

        final future = runVoiceTranscriptEnrichment(
          baseStt: base,
          snapshot: _snapshot,
          isOwnMessage: true,
          enrich: (_, _) => enrichGate.future,
          // The coordinator holds this closure directly -- it never consults a
          // BuildContext -- so a disposed widget cannot suppress the recording.
          recordAnalytics: (_) async {
            expect(
              disposed,
              isTrue,
              reason: 'recording must survive the widget being disposed',
            );
            analyticsCalls++;
          },
          attach: (_) async => null,
        );

        // Simulate navigating away / disposing the chat BEFORE enrich resolves.
        disposed = true;
        enrichGate.complete(
          base.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
        );
        await future;
        expect(analyticsCalls, 1);
      },
    );

    test(
      'analytics fires once for own message even when attach returns null',
      () async {
        var analyticsCalls = 0;
        var attachCalls = 0;
        final base = _skipTokenizeBase();

        await runVoiceTranscriptEnrichment(
          baseStt: base,
          snapshot: _snapshot,
          isOwnMessage: true,
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
      'does NOT record analytics for a viewed other-sender message',
      () async {
        var analyticsCalls = 0;
        final base = _skipTokenizeBase();

        await runVoiceTranscriptEnrichment(
          baseStt: base,
          snapshot: _snapshot,
          isOwnMessage: false,
          enrich: (b, _) async =>
              b.withFirstTranscriptTokens([STTToken(token: _token('hola', 0))]),
          recordAnalytics: (_) async => analyticsCalls++,
          attach: (_) async => null,
        );

        expect(analyticsCalls, 0);
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
          isOwnMessage: true,
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

      // A missing key stays null so the dotenv default (false) governs.
      expect(
        AppConfigOverride.fromJson(const {}).voiceTranscriptDecoupleEnabled,
        isNull,
      );
    });
  });
}
