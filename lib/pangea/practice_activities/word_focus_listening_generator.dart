import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';

class WordFocusListeningGenerator {
  static MessageActivityResponse get(
    MessageActivityRequest req,
  ) {
    if (req.target.tokens.length <= 1) {
      throw Exception(
        "Word focus listening activity requires at least 2 tokens",
      );
    }

    return MessageActivityResponse(
      activity: WordListeningPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        matchContent: PracticeMatchActivity(
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
