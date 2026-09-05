import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/match_rule_id_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';

/// Writing assistance returns grammar corrections and translations from one
/// endpoint (#8822). The edit's [ReplacementTypeEnum] is now the only thing
/// that tells them apart, so a translation edit must mint the `It` family and
/// a grammar edit must keep minting the `IGC` family.
const _text = 'quiero un café';

PangeaToken _token(String content, int offset) => PangeaToken(
  text: PangeaTokenText.fromJson({'content': content, 'offset': offset}),
  lemma: Lemma(text: content, saveVocab: true, form: content),
  pos: 'NOUN',
  morph: const {},
);

/// A match whose single choice carries a timestamp (so the step is attributable
/// to the token) and whose [selected] flag drives the correct/incorrect/ignored
/// branch.
ChoreoRecordModel _record({
  required ReplacementTypeEnum type,
  required SpanChoiceTypeEnum choiceType,
  bool selected = true,
  PangeaMatchStatusEnum status = PangeaMatchStatusEnum.accepted,
  Rule? rule,
}) {
  final match = PangeaMatch(
    match: SpanData(
      message: null,
      shortMessage: null,
      choices: [
        SpanChoice(
          value: 'café',
          type: choiceType,
          selected: selected,
          timestamp: DateTime(2026, 7, 15),
        ),
      ],
      offset: 10,
      length: 4,
      fullText: _text,
      type: type,
      rule: rule,
    ),
    status: status,
  );

  return ChoreoRecordModel(
    choreoSteps: [ChoreoRecordStepModel(acceptedOrIgnoredMatch: match)],
    openMatches: [],
    originalText: _text,
  );
}

void main() {
  final representation = PangeaRepresentation(
    langCode: 'es',
    text: _text,
    originalSent: true,
    originalWritten: true,
  );
  final metadata = ConstructUseMetaData(
    roomId: '!room:test',
    eventId: r'$event',
    timeStamp: DateTime(2026, 7, 15),
  );

  List<OneConstructUse> uses(ChoreoRecordModel choreo) =>
      representation.vocabAndMorphUses(
        tokens: [_token('café', 10)],
        choreo: choreo,
        metadata: metadata,
      );

  void expectAll(
    List<OneConstructUse> result,
    ConstructUseTypeEnum expected,
    int xp,
  ) {
    expect(result, isNotEmpty);
    expect(result.every((u) => u.useType == expected), isTrue);
    expect(result.every((u) => u.xp == xp), isTrue);
  }

  group('translation edits mint the It family', () {
    test('accepted suggestion scores corIt', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.translation,
            choiceType: SpanChoiceTypeEnum.suggestion,
          ),
        ),
        ConstructUseTypeEnum.corIt,
        ConstructUseTypeEnum.corIt.pointValue,
      );
    });

    test('selected distractor scores incIt', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.translation,
            choiceType: SpanChoiceTypeEnum.distractor,
          ),
        ),
        ConstructUseTypeEnum.incIt,
        ConstructUseTypeEnum.incIt.pointValue,
      );
    });

    test('unselected choice scores ignIt at zero xp', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.translation,
            choiceType: SpanChoiceTypeEnum.suggestion,
            selected: false,
          ),
        ),
        ConstructUseTypeEnum.ignIt,
        0,
      );
    });

    test('legacy needs-translation rule id still scores corIt', () {
      expectAll(
        uses(
          _record(
            // Events stored before the writing-assistance cutover carry the
            // rule id rather than a translation replacement type.
            type: ReplacementTypeEnum.other,
            choiceType: SpanChoiceTypeEnum.suggestion,
            rule: const Rule(id: MatchRuleIdModel.tokenNeedsTranslation),
          ),
        ),
        ConstructUseTypeEnum.corIt,
        ConstructUseTypeEnum.corIt.pointValue,
      );
    });
  });

  group('grammar edits keep minting the IGC family (regression pins)', () {
    test('accepted suggestion scores corIGC', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.verbConjugation,
            choiceType: SpanChoiceTypeEnum.suggestion,
          ),
        ),
        ConstructUseTypeEnum.corIGC,
        ConstructUseTypeEnum.corIGC.pointValue,
      );
    });

    test('selected distractor scores incIGC', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.genderAgreement,
            choiceType: SpanChoiceTypeEnum.distractor,
          ),
        ),
        ConstructUseTypeEnum.incIGC,
        ConstructUseTypeEnum.incIGC.pointValue,
      );
    });

    test('unselected choice scores ignIGC at zero xp', () {
      expectAll(
        uses(
          _record(
            type: ReplacementTypeEnum.article,
            choiceType: SpanChoiceTypeEnum.suggestion,
            selected: false,
          ),
        ),
        ConstructUseTypeEnum.ignIGC,
        0,
      );
    });

    test('word choice and style still score as IGC until #479 lands', () {
      for (final type in [
        ReplacementTypeEnum.falseCognate,
        ReplacementTypeEnum.style,
        ReplacementTypeEnum.transcription,
      ]) {
        expectAll(
          uses(_record(type: type, choiceType: SpanChoiceTypeEnum.suggestion)),
          ConstructUseTypeEnum.corIGC,
          ConstructUseTypeEnum.corIGC.pointValue,
        );
      }
    });
  });
}
