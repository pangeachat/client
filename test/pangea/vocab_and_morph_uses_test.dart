import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';

/// XP-integrity tests for [PangeaRepresentation.vocabAndMorphUses] token
/// filtering (#7665): text inserted by accepting an orchestrator suggestion
/// chip must be excluded from construct-use scoring exactly like pasted text,
/// while genuinely typed tokens keep scoring as written-active (`wa`).
PangeaToken _token(String content, int offset) => PangeaToken(
  text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
  lemma: Lemma(text: content, saveVocab: true, form: content),
  pos: 'NOUN',
  morph: const {},
);

ChoreoRecordModel _record() =>
    ChoreoRecordModel(choreoSteps: [], openMatches: [], originalText: '');

void main() {
  final representation = PangeaRepresentation(
    langCode: 'es',
    text: 'hola quiero un café',
    originalSent: true,
    originalWritten: true,
  );
  final metadata = ConstructUseMetaData(
    roomId: '!room:test',
    eventId: r'$event',
    timeStamp: DateTime(2026, 7, 15),
  );

  List<OneConstructUse> vocabAndMorphUses({
    required List<PangeaToken> tokens,
    ChoreoRecordModel? choreo,
  }) => representation.vocabAndMorphUses(
    tokens: tokens,
    choreo: choreo,
    metadata: metadata,
  );

  test('without choreo, tokens score as written-active (wa)', () {
    final uses = vocabAndMorphUses(tokens: [_token('hola', 0)]);
    expect(uses, isNotEmpty);
    expect(uses.every((u) => u.useType == ConstructUseTypeEnum.wa), isTrue);
    expect(uses.first.xp, ConstructUseTypeEnum.wa.pointValue);
  });

  test(
    'accepted-suggestion tokens produce suggestion uses; typed tokens still score',
    () {
      final choreo = _record()..addSuggestionString('quiero un café');
      final suggestionUses = vocabAndMorphUses(
        tokens: [_token('quiero', 5), _token('café', 15)],
        choreo: choreo,
      );
      expect(
        suggestionUses.every((u) => u.useType == ConstructUseTypeEnum.sug),
        isTrue,
      );

      final typedUses = vocabAndMorphUses(
        tokens: [_token('hola', 0)],
        choreo: choreo,
      );
      expect(typedUses, isNotEmpty);
      expect(
        typedUses.every((u) => u.useType == ConstructUseTypeEnum.wa),
        isTrue,
      );
    },
  );

  test('pasted tokens stay excluded (regression pin)', () {
    final choreo = _record()..addPastedString('quiero un café');
    final uses = vocabAndMorphUses(
      tokens: [_token('quiero', 5)],
      choreo: choreo,
    );
    expect(uses, isEmpty);
  });
}
