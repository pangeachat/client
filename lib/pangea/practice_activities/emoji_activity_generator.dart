import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';

class EmojiActivityGenerator {
  Future<MessageActivityResponse> get(
    MessageActivityRequest req,
    BuildContext context,
  ) async {
    if (req.targetTokens.length == 1) {
      return _favorite(req, context);
    } else {
      return _matchActivity(req, context);
    }
  }

  Future<MessageActivityResponse> _favorite(
    MessageActivityRequest req,
    BuildContext context,
  ) async {
    final PangeaToken token = req.targetTokens.first;

    // Check if user has already saved emojis for this construct
    final List<String> userSavedEmojis = token.vocabConstructID.userSetEmoji;

    // Use user-saved emojis if available, otherwise get from server
    final List<String> emojis = userSavedEmojis.isNotEmpty
        ? userSavedEmojis
        : await token.getEmojiChoices();

    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: ActivityTypeEnum.emoji,
        targetTokens: [token],
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          question: L10n.of(context).pickAnEmojiFor(token.lemma.text),
          choices: emojis,
          answers: emojis,
          spanDisplayDetails: null,
        ),
      ),
    );
  }

  Future<MessageActivityResponse> _matchActivity(
    MessageActivityRequest req,
    BuildContext context,
  ) async {
    final Map<ConstructForm, List<String>> matchInfo = {};
    final List<MapEntry<PangeaToken, List<String>>> tokensWithUserEmojis = [];
    final List<PangeaToken> tokensNeedingServerEmojis = [];
    //if user saved emojis, use those, otherwise generate.
    for (final token in req.targetTokens) {
      final List<String> userSavedEmojis = token.vocabConstructID.userSetEmoji;

      if (userSavedEmojis.isNotEmpty) {
        tokensWithUserEmojis.add(MapEntry(token, userSavedEmojis));
      } else {
        tokensNeedingServerEmojis.add(token);
      }
    }

    for (final entry in tokensWithUserEmojis) {
      matchInfo[entry.key.vocabForm] = entry.value;
    }

    if (tokensNeedingServerEmojis.isNotEmpty) {
      final List<Future<LemmaInfoResponse>> lemmaInfoFutures =
          tokensNeedingServerEmojis
              .map((token) => token.vocabConstructID.getLemmaInfo())
              .toList();

      final List<LemmaInfoResponse> lemmaInfos =
          await Future.wait(lemmaInfoFutures);

      for (int i = 0; i < tokensNeedingServerEmojis.length; i++) {
        matchInfo[tokensNeedingServerEmojis[i].vocabForm] = lemmaInfos[i].emoji;
      }
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
