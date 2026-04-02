import 'package:fluffychat/pangea/practice_exercises/lemma_practice_exercise_generator.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class VocabMeaningPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req,
  ) async {
    final token = req.target.tokens.first;
    final choices =
        await LemmaPracticeExerciseGenerator.lemmaPracticeExerciseDistractors(
          token,
          language: req.userL2.split('-').first,
        );

    if (!choices.contains(token.vocabConstructID)) {
      choices.add(token.vocabConstructID);
    }

    final Set<String> constructIdChoices = choices.map((c) => c.string).toSet();

    return MessagePracticeExerciseResponse(
      exercise: VocabMeaningPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoicePracticeExercise(
          choices: constructIdChoices,
          answers: {token.vocabConstructID.string},
        ),
      ),
    );
  }
}
