import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/parts_of_speech_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/multiple_choice_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

class MorphCategoryPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req,
  ) async {
    if (req.target.morphFeature == null) {
      throw ArgumentError(
        "MorphCategoryPracticeExerciseGenerator requires a targetMorphFeature",
      );
    }

    final feature = req.target.morphFeature!;
    final morphTag = req.target.tokens.first.getMorphTag(feature);
    if (morphTag == null) {
      throw ArgumentError("Token does not have the specified morph feature");
    }

    final tags = await GrammarConstructsProvider.fetchTags(
      feature: feature.name,
    );
    final allTags = tags.map((t) => t.value);
    final List<String> possibleDistractors = allTags
        .where(
          (tag) =>
              tag.toLowerCase() != morphTag.toLowerCase() &&
              PartOfSpeechEnum.isEligibleLemmaTag(tag),
        )
        .toList();

    if (possibleDistractors.isEmpty) {
      throw InsufficientDataException();
    }

    possibleDistractors.shuffle();
    final choices = possibleDistractors.take(3).toList();
    choices.add(morphTag);
    choices.shuffle();

    return MessagePracticeExerciseResponse(
      exercise: MorphCategoryPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        morphFeature: feature,
        multipleChoiceContent: MultipleChoicePracticeExercise(
          choices: choices.toSet(),
          answers: {morphTag},
        ),
        exampleMessageInfo:
            req.exampleMessage ?? const ExampleMessageInfo(exampleMessage: []),
      ),
    );
  }
}
