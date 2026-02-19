import 'dart:math';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/grammar_error_target_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/grammar_match_target_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/pangea/analytics_practice/vocab_meaning_target_generator.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/widgets/matrix.dart';

class InsufficientDataException implements Exception {}

class AnalyticsPracticeSessionRepo {
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
    String language,
  ) async {
    if (MatrixState.pangeaController.subscriptionController.isSubscribed ==
        false) {
      throw UnsubscribedException();
    }

    final List<AnalyticsActivityTarget> targets = [];
    final analytics =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    final vocabConstructs = await analytics
        .getAggregatedConstructs(ConstructTypeEnum.vocab, language)
        .then((map) => map.values.toList());

    if (type == ConstructTypeEnum.vocab) {
      final totalNeeded = AnalyticsPracticeConstants.targetsToGenerate;
      final halfNeeded = (totalNeeded / 2).ceil();

      // Fetch audio constructs (with example messages)
      final audioTargets = await VocabAudioTargetGenerator.get(vocabConstructs);
      final audioCount = min(audioTargets.length, halfNeeded);

      // Fetch vocab constructs to fill the rest
      final vocabNeeded = totalNeeded - audioCount;
      final vocabTargets = await VocabMeaningTargetGenerator.get(
        vocabConstructs,
      );
      final vocabCount = min(vocabTargets.length, vocabNeeded);

      final audioTargetsToAdd = audioTargets.take(audioCount);
      final meaningTargetsToAdd = vocabTargets.take(vocabCount);
      targets.addAll(audioTargetsToAdd);
      targets.addAll(meaningTargetsToAdd);
    } else {
      final errorTargets = await GrammarErrorTargetGenerator.get(
        vocabConstructs,
      );
      targets.addAll(errorTargets);

      if (targets.length < AnalyticsPracticeConstants.targetsToGenerate) {
        final morphConstructs = await analytics
            .getAggregatedConstructs(ConstructTypeEnum.morph, language)
            .then((map) => map.values.toList());
        final morphs = await GrammarMatchTargetGenerator.get(morphConstructs);
        final remainingCount =
            AnalyticsPracticeConstants.targetsToGenerate - targets.length;

        final morphEntries = morphs.take(remainingCount);
        targets.addAll(morphEntries);
      }
    }

    if (targets.isEmpty) {
      throw InsufficientDataException();
    }

    targets.shuffle();
    final session = AnalyticsPracticeSessionModel(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      startedAt: DateTime.now(),
      practiceTargets: targets,
    );
    return session;
  }
}
