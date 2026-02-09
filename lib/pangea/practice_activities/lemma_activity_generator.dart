import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaActivityGenerator {
  static Future<MessageActivityResponse> get(MessageActivityRequest req) async {
    debugger(when: kDebugMode && req.target.tokens.length != 1);

    final token = req.target.tokens.first;
    final choices = await lemmaActivityDistractors(token);

    // TODO - modify MultipleChoiceActivity flow to allow no correct answer
    return MessageActivityResponse(
      activity: LemmaPracticeActivityModel(
        tokens: req.target.tokens,
        langCode: req.userL2,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: choices.map((c) => c.lemma).toSet(),
          answers: {token.lemma.text},
        ),
      ),
    );
  }

  static Future<Set<ConstructIdentifier>> lemmaActivityDistractors(
    PangeaToken token, {
    int? maxChoices = 4,
  }) async {
    final constructs = await MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.vocab);

    final List<ConstructIdentifier> constructIds = constructs.keys.toList();
    // Offload computation to an isolate
    final Map<ConstructIdentifier, int> distances = await compute(
      _computeDistancesInIsolate,
      {'lemmas': constructIds, 'target': token.lemma.text},
    );

    // Sort lemmas by distance
    final sortedLemmas = distances.keys.toList()
      ..sort((a, b) => distances[a]!.compareTo(distances[b]!));

    // Skip the first 7 lemmas (to avoid very similar and conjugated forms of verbs) if we have enough lemmas
    final int startIndex = sortedLemmas.length > 11 ? 7 : 0;

    // Take up to 4 (or maxChoices) lemmas ensuring uniqueness by lemma text
    final List<ConstructIdentifier> uniqueByLemma = [];
    for (int i = startIndex; i < sortedLemmas.length; i++) {
      final cid = sortedLemmas[i];
      if (!uniqueByLemma.any((c) => c.lemma == cid.lemma)) {
        uniqueByLemma.add(cid);
        if (uniqueByLemma.length == maxChoices) break;
      }
    }

    if (uniqueByLemma.isEmpty) {
      return {token.vocabConstructID};
    }

    // Ensure the target lemma (token.vocabConstructID) is included while keeping unique lemma texts
    final int existingIndex = uniqueByLemma.indexWhere(
      (c) => c.lemma == token.vocabConstructID.lemma,
    );
    if (existingIndex >= 0) {
      uniqueByLemma[existingIndex] = token.vocabConstructID;
    } else {
      if (uniqueByLemma.length < 4) {
        uniqueByLemma.add(token.vocabConstructID);
      } else {
        uniqueByLemma[uniqueByLemma.length - 1] = token.vocabConstructID;
      }
    }

    //shuffle so correct answer isn't always first
    uniqueByLemma.shuffle();

    return uniqueByLemma.toSet();
  }

  // isolate helper function
  static Map<ConstructIdentifier, int> _computeDistancesInIsolate(
    Map<String, dynamic> params,
  ) {
    final List<ConstructIdentifier> lemmas = params['lemmas'];
    final String target = params['target'];

    // Calculate Levenshtein distances
    final Map<ConstructIdentifier, int> distances = {};
    for (final lemma in lemmas) {
      distances[lemma] = _levenshteinDistanceSync(target, lemma.lemma);
    }
    return distances;
  }

  static int _levenshteinDistanceSync(String s, String t) {
    final int m = s.length;
    final int n = t.length;
    final List<List<int>> dp = List.generate(
      m + 1,
      (_) => List.generate(n + 1, (_) => 0),
    );

    for (int i = 0; i <= m; i++) {
      for (int j = 0; j <= n; j++) {
        if (i == 0) {
          dp[i][j] = j;
        } else if (j == 0) {
          dp[i][j] = i;
        } else if (s[i - 1] == t[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1];
        } else {
          dp[i][j] =
              1 +
              [
                dp[i - 1][j],
                dp[i][j - 1],
                dp[i - 1][j - 1],
              ].reduce((a, b) => a < b ? a : b);
        }
      }
    }

    return dp[m][n];
  }
}
