import 'package:async/async.dart';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';

class EmojiPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    if (req.target.tokens.length <= 1) {
      throw Exception("Emoji exercise requires at least 2 tokens");
    }

    return _matchPracticeExercise(req, messageInfo: messageInfo);
  }

  static Future<MessagePracticeExerciseResponse> _matchPracticeExercise(
    MessagePracticeExerciseRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    final Map<ConstructForm, List<String>> matchInfo = {};
    final List<PangeaToken> missingEmojis = [];

    final List<String> usedEmojis = [];
    for (final token in req.target.tokens) {
      final userSavedEmoji = token.vocabConstructID.userSetEmoji;
      if (userSavedEmoji != null && !usedEmojis.contains(userSavedEmoji)) {
        matchInfo[token.vocabForm] = [userSavedEmoji];
        usedEmojis.add(userSavedEmoji);
      } else {
        missingEmojis.add(token);
      }
    }

    final List<Future<Result<LemmaInfoResponse>>> lemmaInfoFutures =
        missingEmojis
            .map((token) => token.vocabConstructID.getLemmaInfo(messageInfo))
            .toList();

    final List<Result<LemmaInfoResponse>> lemmaInfos = await Future.wait(
      lemmaInfoFutures,
    );

    for (int i = 0; i < missingEmojis.length; i++) {
      if (lemmaInfos[i].isError) {
        throw lemmaInfos[i].asError!.error;
      }

      final e = lemmaInfos[i].asValue!.value.emoji.firstWhere(
        (e) => !usedEmojis.contains(e),
        orElse: () =>
            throw Exception("Not enough unique emojis for tokens in message"),
      );

      final token = missingEmojis[i];
      matchInfo[token.vocabForm] ??= [];
      matchInfo[token.vocabForm]!.add(e);
      usedEmojis.add(e);
    }

    return MessagePracticeExerciseResponse(
      exercise: EmojiPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        matchContent: MatchPracticeExercise(matchInfo: matchInfo),
      ),
    );
  }
}
