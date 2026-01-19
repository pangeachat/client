import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GrammarErrorPracticeGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    final igcMatch = target.igcMatch;
    assert(igcMatch.bestChoice != null, 'IGC match must have a best choice');
    assert(igcMatch.choices != null, 'IGC match must have choices');

    final errorSpan = igcMatch.errorSpan;
    final correctChoice = igcMatch.bestChoice!.value;
    final choices = igcMatch.choices!.map((c) => c.value).toList();

    final choiceTokens = target.tokens.where(
      (token) => choices.any(
        (choice) => choice.contains(token.text.content),
      ),
    );

    assert(
      choiceTokens.isNotEmpty,
      'At least one token should match the error choices',
    );

    choices.add(errorSpan);
    choices.shuffle();
    return MessageActivityResponse(
      activity: GrammarErrorPracticeActivityModel(
        tokens: choiceTokens.toList(),
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: choices.toSet(),
          answers: {correctChoice},
        ),
      ),
    );
  }
}
