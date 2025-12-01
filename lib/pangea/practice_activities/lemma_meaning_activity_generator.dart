import 'dart:async';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';

class LemmaMeaningActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    final List<Future<LemmaInfoResponse>> lemmaInfoFutures = req.targetTokens
        .map((token) => token.vocabConstructID.getLemmaInfo())
        .toList();

    final List<LemmaInfoResponse> lemmaInfos =
        await Future.wait(lemmaInfoFutures);

    final Map<ConstructForm, List<String>> matchInfo = Map.fromIterables(
      req.targetTokens.map((token) => token.vocabForm),
      lemmaInfos.map((lemmaInfo) => [lemmaInfo.meaning]),
    );

    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: ActivityTypeEnum.wordMeaning,
        targetTokens: req.targetTokens,
        langCode: req.userL2,
        matchContent: PracticeMatchActivity(
          matchInfo: matchInfo,
        ),
      ),
    );
  }
}
