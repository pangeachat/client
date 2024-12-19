import 'dart:developer';

import 'package:dart_levenshtein/dart_levenshtein.dart';
import 'package:fluffychat/pangea/enum/activity_type_enum.dart';
import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/message_activity_request.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';

class LemmaActivityGenerator {
  Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    debugger(when: kDebugMode && req.targetTokens.length != 1);

    final PangeaToken targetTokens = req.targetTokens.first;

    final List<String> lemmas = MatrixState
        .pangeaController.getAnalytics.constructListModel
        .constructList(type: ConstructTypeEnum.vocab)
        .map((c) => c.lemma)
        .toList();

    // sort by the closeness in spelling to the target lemma, measured by levenshtein distance
    // use => await string.levenshteinDistance cuz its a Future for some reason
    // can't use standard sort because of this
    final List<Future<int>> distanceFutures = [];
    for (int i = 0; i < lemmas.length; i++) {
      final String lemma = lemmas[i];
      distanceFutures.add(targetTokens.lemma.text.levenshteinDistance(lemma));
    }

    final List<int> distances = await Future.wait(distanceFutures);

    final Map<String, int> lemmasWithDistances = {};
    for (int i = 0; i < lemmas.length; i++) {
      lemmasWithDistances[lemmas[i]] = distances[i];
    }

    // get the shortest 5
    final List<String> sortedLemmas = lemmasWithDistances.keys.toList()
      ..sort(
        (a, b) => lemmasWithDistances[a]!.compareTo(lemmasWithDistances[b]!),
      );
    final List<String> choices = sortedLemmas.sublist(0, 5);

    // TODO - modify MultipleChoiceActivity flow to allow no correct answer
    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: ActivityTypeEnum.lemmaId,
        targetTokens: [targetTokens],
        tgtConstructs: [targetTokens.vocabConstructID],
        langCode: req.userL2,
        content: ActivityContent(
          question: "",
          choices: choices,
          answer: targetTokens.lemma.text,
          spanDisplayDetails: null,
        ),
      ),
    );
  }
}
