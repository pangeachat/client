import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Voice (STT) messages must yield the same vocab construct uses that typed
/// messages do, so spoken target vocab is counted as "used" (issue #7659).
/// This pins `SpeechToTextResponseModel.constructs()` — the audio branch of
/// `PangeaMessageEvent.constructUses`, which `_updateUsedVocab` intersects
/// with the activity's target vocab to drive the used-vocab checklist and the
/// gold highlight.
PangeaToken _token(String content, {bool saveVocab = true}) => PangeaToken(
  text: PangeaTokenText.fromJson({'content': content, 'offset': 0}),
  lemma: Lemma(text: content, saveVocab: saveVocab, form: content),
  pos: 'NOUN',
  morph: const {},
);

SpeechToTextResponseModel _stt(List<PangeaToken> tokens) =>
    SpeechToTextResponseModel(
      results: [
        SpeechToTextResult(
          transcripts: [
            Transcript(
              text: tokens.map((t) => t.text.content).join(' '),
              confidence: 100,
              sttTokens: [for (final t in tokens) STTToken(token: t)],
              langCode: 'es',
              wordsPerHr: null,
            ),
          ],
        ),
      ],
    );

void main() {
  test('spoken vocab tokens produce vocab construct uses scored as pvm', () {
    final uses = _stt([
      _token('hola'),
      _token('gracias'),
    ]).constructs('!room:test', r'$event');

    final vocabUses = uses
        .where((u) => u.identifier.type == ConstructTypeEnum.vocab)
        .toList();

    expect(vocabUses.map((u) => u.identifier.lemma).toSet(), {
      'hola',
      'gracias',
    });
    // Spoken production scores as pvm (parity with the send-path voice
    // analytics), not the typed `wa`.
    expect(
      vocabUses.every((u) => u.useType == ConstructUseTypeEnum.pvm),
      isTrue,
    );
  });

  test('tokens flagged not to save vocab produce no uses (saveVocab gate)', () {
    final uses = _stt([
      _token('the', saveVocab: false),
    ]).constructs('!room:test', r'$event');
    expect(uses, isEmpty);
  });

  test('uses carry the room and event ids they were built with', () {
    final uses = _stt([_token('hola')]).constructs('!room:test', r'$evt');
    expect(uses, isNotEmpty);
    expect(uses.first.metadata.roomId, '!room:test');
    expect(uses.first.metadata.eventId, r'$evt');
  });
}
