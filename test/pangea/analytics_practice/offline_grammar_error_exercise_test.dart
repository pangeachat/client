import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_practice_generator.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// "have" corrected to "habe", accepted at step 0.
ChoreoRecordModel _record() {
  final record = ChoreoRecordModel(
    originalText: 'Ich have ein Hund',
    choreoSteps: [],
    openMatches: [],
  );
  record.addRecord(
    'Ich habe ein Hund',
    match: PangeaMatch(
      match: SpanData(
        message: null,
        shortMessage: null,
        choices: [
          SpanChoice(
            value: 'habe',
            type: SpanChoiceTypeEnum.suggestion,
            selected: true,
          ),
          SpanChoice(value: 'hat', type: SpanChoiceTypeEnum.distractor),
        ],
        offset: 4,
        length: 4,
        fullText: 'Ich habe ein Hund',
        type: ReplacementTypeEnum.verbConjugation,
        rule: null,
      ),
      status: PangeaMatchStatusEnum.accepted,
    ),
  );
  return record;
}

GrammarErrorRequestInfo _info({String? translation}) => GrammarErrorRequestInfo(
  choreo: _record(),
  stepIndex: 0,
  eventID: r'$event',
  translation: translation,
  sentText: 'Ich habe ein Hund',
);

MessagePracticeExerciseRequest _request({String? translation}) =>
    MessagePracticeExerciseRequest(
      userL1: 'en',
      userL2: 'de',
      exerciseQualityFeedback: null,
      target: PracticeTarget(
        tokens: [
          PangeaToken(
            text: PangeaTokenText.fromJson({'content': 'habe', 'offset': 4}),
            lemma: Lemma(text: 'haben', saveVocab: true, form: 'habe'),
            pos: 'VERB',
            morph: const {},
          ),
        ],
        exerciseType: PracticeExerciseTypeEnum.grammarError,
      ),
      grammarErrorInfo: _info(translation: translation),
    );

Future<GrammarErrorPracticeExerciseModel> _exercise({
  String? translation,
}) async {
  final response = await GrammarErrorPracticeGenerator.get(
    _request(translation: translation),
  );
  return response.exercise as GrammarErrorPracticeExerciseModel;
}

/// #9541 — an offline grammar-error exercise has no translation, so it has no
/// hint, and the learner's own error is always one of the choices.
void main() {
  test('an offline exercise offers the learner\'s own error', () async {
    final exercise = await _exercise();
    expect(exercise.translation, isNull);
    expect(exercise.multipleChoiceContent.choices, contains('have'));
    expect(exercise.multipleChoiceContent.answers, {'habe'});
  });

  test('online, an error the translation shows is still left out', () async {
    final exercise = await _exercise(translation: 'I have a dog');
    expect(exercise.translation, 'I have a dog');
    expect(exercise.multipleChoiceContent.choices, isNot(contains('have')));
  });

  test('an exercise without a translation survives a round trip', () {
    final restored = GrammarErrorRequestInfo.fromJson(_info().toJson());
    expect(restored.translation, isNull);
    expect(restored.eventID, r'$event');
  });
}
