import 'dart:async';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/constructs/construct_form.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/practice_exercises/match_practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class LemmaMeaningPracticeExerciseGenerator {
  static Future<MessagePracticeExerciseResponse> get(
    MessagePracticeExerciseRequest req, {
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

    return MessagePracticeExerciseResponse(
      exercise: LemmaMeaningPracticeExerciseModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        matchContent: MatchPracticeExercise(matchInfo: matchInfo),
      ),
    );
  }
}
