import 'package:async/async.dart';

import 'package:fluffychat/features/analytics/construct_form.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';

/// Pick the emoji to display for one token: the first candidate that is
/// neither already used by another token nor the content the user flagged
/// as wrong via practice feedback. Falls back to the flagged content when
/// it is the only unused candidate — a regenerated row that kept it as the
/// sole option is served as-is rather than failing the exercise. Kept pure
/// so it can be unit-tested without Matrix state.
///
/// Throws [StateError] when every candidate is already used.
String pickEmojiChoice({
  required List<String> candidates,
  required List<String> used,
  String? avoid,
}) {
  return candidates.firstWhere(
    (e) => !used.contains(e) && e != avoid,
    orElse: () => candidates.firstWhere((e) => !used.contains(e)),
  );
}

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

      final String e;
      try {
        e = pickEmojiChoice(
          candidates: lemmaInfos[i].asValue!.value.emoji,
          used: usedEmojis,
          avoid: req.avoidContent[missingEmojis[i].vocabConstructID],
        );
      } on StateError {
        throw Exception("Not enough unique emojis for tokens in message");
      }

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
