import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';

/// P1b.2 — token-aware read (`selectUsableStt(preferTokens:)`) + the shared
/// token-repair primitive (`repairSttTokens`).
///
/// The R0 default (`preferTokens:false`) is covered byte-identically by the
/// untouched `stt_local_fallthrough_test.dart`; here we pin the NEW
/// token-preferring behaviour and the repair semantics that back the toolbar
/// (requireTokens:true) vs the text-only translation path (requireTokens:false).

PangeaToken _token(String content, int offset) => PangeaToken.fromJson({
  'text': {'content': content, 'offset': offset, 'length': content.length},
  'lemma': {'text': content, 'save_vocab': true, 'form': content},
  'pos': 'NOUN',
  'morph': <String, dynamic>{},
});

SpeechToTextResponseModel _textOnly(String text) => SpeechToTextResponseModel(
  results: [
    SpeechToTextResult(
      transcripts: [
        Transcript(
          text: text,
          confidence: 94,
          sttTokens: const [],
          langCode: 'es',
          wordsPerHr: 120,
        ),
      ],
    ),
  ],
);

SpeechToTextResponseModel _withTokens(String text) => _textOnly(
  text,
).withFirstTranscriptTokens([STTToken(token: _token(text, 0))]);

void main() {
  group('selectUsableStt(preferTokens:)', () {
    test('a token-less embed falls through to a token-rich representation', () {
      final rep = _withTokens('hola');
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: _textOnly('hola'),
        representation: () => rep,
        preferTokens: true,
      );
      expect(selected, same(rep));
    });

    test('a token-rich embed wins without evaluating the representation', () {
      final embed = _withTokens('hola');
      var evaluated = false;
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: embed,
        representation: () {
          evaluated = true;
          return _withTokens('rep');
        },
        preferTokens: true,
      );
      expect(selected, same(embed));
      expect(evaluated, isFalse);
    });

    test('falls back to the text-usable embed when no token-rich rep exists '
        '(never null while a text embed exists)', () {
      final embed = _textOnly('hola');
      final selected = PangeaMessageEvent.selectUsableStt(
        embedded: embed,
        representation: () => _textOnly('rep'), // also token-less
        preferTokens: true,
      );
      expect(selected, same(embed));
    });

    test(
      'the DEFAULT (text consumers) returns the fast token-less embed and never '
      'evaluates the representation',
      () {
        final embed = _textOnly('hola');
        var evaluated = false;
        final selected = PangeaMessageEvent.selectUsableStt(
          embedded: embed,
          representation: () {
            evaluated = true;
            return _withTokens('rep');
          },
        );
        expect(selected, same(embed));
        expect(evaluated, isFalse);
      },
    );
  });

  group('repairSttTokens', () {
    SttLangSnapshot snapshot() => const SttLangSnapshot(
      fullText: 'hola',
      langCode: 'es',
      senderL1: 'en',
      senderL2: 'es',
    );

    test(
      'requireTokens:false on a token-less embed returns it fast and NEVER '
      'tokenizes (the requestSttTranslation caller-safety guarantee)',
      () async {
        var enrichCalls = 0;
        var attachCalls = 0;
        final local = _textOnly('hola');
        final result = await repairSttTokens(
          local: local,
          requireTokens: false,
          snapshot: snapshot(),
          enrich: (base, snap) async {
            enrichCalls++;
            return base;
          },
          attach: (rich) async {
            attachCalls++;
            return null;
          },
        );
        expect(result, same(local));
        expect(enrichCalls, 0, reason: 'text-only path must not tokenize');
        expect(attachCalls, 0);
      },
    );

    test(
      'requireTokens:true on a token-less embed enriches + attaches and returns '
      'the token-rich result',
      () async {
        var enrichCalls = 0;
        var attachCalls = 0;
        final rich = _withTokens('hola');
        final result = await repairSttTokens(
          local: _textOnly('hola'),
          requireTokens: true,
          snapshot: snapshot(),
          enrich: (base, snap) async {
            enrichCalls++;
            return rich;
          },
          attach: (r) async {
            attachCalls++;
            return null; // a null attach is non-fatal
          },
        );
        expect(result, same(rich));
        expect(result.hasUsableTokens, isTrue);
        expect(enrichCalls, 1);
        expect(attachCalls, 1);
      },
    );

    test('requireTokens:true on an already token-rich embed returns it without '
        'tokenizing again (no duplicate work on re-view)', () async {
      var enrichCalls = 0;
      final rich = _withTokens('hola');
      final result = await repairSttTokens(
        local: rich,
        requireTokens: true,
        snapshot: snapshot(),
        enrich: (base, snap) async {
          enrichCalls++;
          return base;
        },
        attach: (r) async => null,
      );
      expect(result, same(rich));
      expect(enrichCalls, 0);
    });
  });
}
