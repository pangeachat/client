import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class WordAudioPracticeExerciseGenerator {
  static MessagePracticeExerciseResponse get(
    MessagePracticeExerciseRequest req,
  ) {
    if (req.target.tokens.length <= 1) {
      throw Exception(
        "Word audio practice exercise requires at least 2 tokens",
      );
    }

    return MessagePracticeExerciseResponse(
      exercise: WordListeningPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        matchContent: MatchPracticeExercise(
          matchInfo: Map.fromEntries(
            req.target.tokens.map(
              (token) => MapEntry(
                ConstructForm(
                  cId: token.vocabConstructID,
                  form: token.text.content,
                ),
                [token.text.content],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
