import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/repo/token_api_models.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';

/// P1b.3 — the two decoupled helpers.
///
/// `enrichSttWithTokens` is the SINGLE tokenize step: it must return a result
/// byte-identical to the skip-tokenize base EXCEPT its `stt_tokens`, and it must
/// surface a tokenizer error without dereferencing an error [Result].
/// `attachSttRepresentation` writes the token-rich STT as a
/// `pangea.representation`; a null/failed send is non-fatal.

SpeechToTextResponseModel _skipTokenizeBase() {
  final raw = File(
    'test/pangea/stt_golden/choreo_response_skip_tokenize.json',
  ).readAsStringSync();
  return SpeechToTextResponseModel.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
}

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

TokensResponseModel _tokensResponse(List<PangeaToken> tokens) =>
    TokensResponseModel(tokens: tokens, lang: 'es', detections: const []);

/// Strips `stt_tokens` from every transcript so two serializations can be
/// compared for equality on EVERY OTHER field.
Map<String, dynamic> _withoutSttTokens(SpeechToTextResponseModel model) {
  final json = jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>;
  for (final result in json['results'] as List) {
    for (final t in (result as Map<String, dynamic>)['transcripts'] as List) {
      (t as Map<String, dynamic>).remove('stt_tokens');
    }
  }
  return json;
}

void main() {
  group('enrichSttWithTokens', () {
    test(
      'richStt equals baseStt in every field except stt_tokens '
      '(service/confidence/wordsPerHr/word_timings/lang_code preserved)',
      () async {
        final base = _skipTokenizeBase();
        expect(base.transcript.sttTokens, isEmpty);
        expect(base.transcript.wordTimings, isNotNull);

        final rich = await enrichSttWithTokens(
          base,
          SttLangSnapshot.fromBaseStt(base, speakerL1: 'en'),
          tokenFetcher: (_) async => Result.value(
            _tokensResponse([_token('hola', 0), _token('mundo', 5)]),
          ),
        );

        // Only stt_tokens changed.
        expect(rich.transcript.sttTokens, hasLength(2));
        expect(
          _withoutSttTokens(rich),
          equals(_withoutSttTokens(base)),
          reason: 'enrich must preserve every field except stt_tokens',
        );

        // Spell out the individual field guarantees too.
        expect(rich.service, base.service);
        expect(rich.transcript.text, base.transcript.text);
        expect(rich.transcript.confidence, base.transcript.confidence);
        expect(rich.transcript.langCode, base.langCode);
        expect(rich.transcript.wordsPerHr, base.transcript.wordsPerHr);
        expect(rich.transcript.wordTimings, base.transcript.wordTimings);
        expect(rich.hasUsableTokens, isTrue);
      },
    );

    test(
      'defensive no-op on a non-usable (exhausted-fallback) baseStt: returns it '
      'unchanged, never tokenizes, never dereferences the missing transcript',
      () async {
        final empty = SpeechToTextResponseModel(results: const []);
        var fetchCalls = 0;

        final result = await enrichSttWithTokens(
          empty,
          const SttLangSnapshot(
            fullText: '',
            langCode: 'es',
            senderL1: 'en',
            senderL2: 'es',
          ),
          tokenFetcher: (_) async {
            fetchCalls++;
            return Result.value(_tokensResponse([_token('hola', 0)]));
          },
        );

        // Teeth: without the hasUsableTranscript guard this either tokenizes
        // empty text or throws on results.first.transcripts.first.
        expect(result, same(empty));
        expect(fetchCalls, 0);
      },
    );

    test('tokens are attached with null timings', () async {
      final base = _skipTokenizeBase();
      final rich = await enrichSttWithTokens(
        base,
        SttLangSnapshot.fromBaseStt(base, speakerL1: 'en'),
        tokenFetcher: (_) async =>
            Result.value(_tokensResponse([_token('hola', 0)])),
      );
      final token = rich.transcript.sttTokens.single;
      expect(token.startTime, isNull);
      expect(token.endTime, isNull);
      expect(token.confidence, isNull);
    });

    test(
      'snapshot anchors the tokenize request to the message language',
      () async {
        final base = _skipTokenizeBase();
        late TokensRequestModel captured;
        await enrichSttWithTokens(
          base,
          SttLangSnapshot.fromBaseStt(base, speakerL1: 'en'),
          tokenFetcher: (req) async {
            captured = req;
            return Result.value(_tokensResponse([_token('hola', 0)]));
          },
        );
        // lang_code + sender_l2 come from the transcript (es), sender_l1 from the
        // audio event's speaker_l1 (en) -- never from current user settings.
        expect(captured.langCode, 'es');
        expect(captured.senderL2, 'es');
        expect(captured.senderL1, 'en');
        expect(captured.fullText, 'hola mundo');
      },
    );

    test(
      'a tokenizer error is surfaced without dereferencing result!',
      () async {
        final base = _skipTokenizeBase();
        await expectLater(
          enrichSttWithTokens(
            base,
            SttLangSnapshot.fromBaseStt(base, speakerL1: 'en'),
            tokenFetcher: (_) async => Result.error(Exception('boom')),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('attachSttRepresentation / buildSttRepresentation', () {
    test(
      'builds a non-original representation carrying the token-rich STT',
      () {
        final base = _skipTokenizeBase();
        final rich = base.withFirstTranscriptTokens([
          STTToken(token: _token('hola', 0)),
        ]);
        final rep = buildSttRepresentation(rich);
        expect(rep.originalSent, isFalse);
        expect(rep.originalWritten, isFalse);
        expect(rep.langCode, rich.langCode);
        expect(rep.text, rich.transcript.text);
        expect(rep.speechToText, same(rich));

        // The serialized representation carries the STT under the `stt` key and
        // the tokens survive the round trip.
        final json = rep.toJson();
        expect(json['stt'], isNotNull);
        final parsed = SpeechToTextResponseModel.fromJson(
          Map<String, dynamic>.from(json['stt'] as Map),
        );
        expect(parsed.hasUsableTokens, isTrue);
      },
    );

    test('writes a representation related to the parent event', () async {
      final base = _skipTokenizeBase();
      final rich = base.withFirstTranscriptTokens([
        STTToken(token: _token('hola', 0)),
      ]);

      Map<String, dynamic>? sentContent;
      String? sentType;
      String? sentParent;
      final result = await attachSttRepresentation(
        parentEventId: r'$audio:server',
        richStt: rich,
        send:
            ({required content, required parentEventId, required type}) async {
              sentContent = content;
              sentParent = parentEventId;
              sentType = type;
              return null; // simulate a swallowed/failed send
            },
      );

      // A null return is non-fatal: no throw, caller decides.
      expect(result, isNull);
      expect(sentParent, r'$audio:server');
      expect(sentType, 'pangea.representation');
      expect(sentContent!['stt'], isNotNull);
    });
  });
}
