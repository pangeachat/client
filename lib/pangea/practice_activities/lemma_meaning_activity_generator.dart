import 'dart:async';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_match.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class LemmaMeaningActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req, {
    required Map<String, dynamic> messageInfo,
  }) async {
    final List<Future<Result<LemmaInfoResponse>>> lemmaInfoFutures = req
        .target
        .tokens
        .map((token) => token.vocabConstructID.getLemmaInfo(messageInfo))
        .toList();

    final List<Result<LemmaInfoResponse>> lemmaInfos = await Future.wait(
      lemmaInfoFutures,
    );

    if (lemmaInfos.any((result) => result.isError)) {
      throw lemmaInfos.firstWhere((result) => result.isError).error!;
    }

    final Map<ConstructForm, List<String>> matchInfo = Map.fromIterables(
      req.target.tokens.map((token) => token.vocabForm),
      lemmaInfos.map((lemmaInfo) => [lemmaInfo.asValue!.value.meaning]),
    );

    return MessageActivityResponse(
      activity: LemmaMeaningPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        matchContent: PracticeMatchActivity(matchInfo: matchInfo),
      ),
    );
  }
}
