import 'package:async/async.dart';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';

class EmojiActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    if (req.targetTokens.length <= 1) {
      throw Exception("Emoji activity requires at least 2 tokens");
    }

    return _matchActivity(req, messageInfo: messageInfo);
  }

  static Future<MessageActivityResponse> _matchActivity(
    MessageActivityRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    final Map<ConstructForm, List<String>> matchInfo = {};
    final List<PangeaToken> missingEmojis = [];

    final List<String> usedEmojis = [];
    for (final token in req.targetTokens) {
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

    final List<Result<LemmaInfoResponse>> lemmaInfos =
        await Future.wait(lemmaInfoFutures);

    for (int i = 0; i < missingEmojis.length; i++) {
      if (lemmaInfos[i].isError) {
        throw lemmaInfos[i].asError!.error;
      }

      final e = lemmaInfos[i].asValue!.value.emoji.firstWhere(
            (e) => !usedEmojis.contains(e),
            orElse: () => throw Exception(
              "Not enough unique emojis for tokens in message",
            ),
          );

      final token = missingEmojis[i];
      matchInfo[token.vocabForm] ??= [];
      matchInfo[token.vocabForm]!.add(e);
      usedEmojis.add(e);
    }

    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: ActivityTypeEnum.emoji,
        targetTokens: req.targetTokens,
        langCode: req.userL2,
        matchContent: PracticeMatchActivity(
          matchInfo: matchInfo,
        ),
      ),
    );
  }
}
