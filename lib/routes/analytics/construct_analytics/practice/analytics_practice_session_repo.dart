import 'dart:math';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_match_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_target_generator.dart';
import 'package:fluffychat/widgets/matrix.dart';

class InsufficientDataException implements Exception {
  /// The session was to run offline, so what it lacks is data saved on this
  /// device. See practice-exercises.instructions.md, "Offline Practice".
  final bool offline;

  const InsufficientDataException({this.offline = false});
}

class AnalyticsPracticeSessionRepo {
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
    LanguageModel userL1,
    LanguageModel userL2,
  ) async {
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      throw UnsubscribedException();
    }

    final List<AnalyticsPracticeTarget> targets = [];
    final analytics =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    final vocabConstructs = await analytics
        .getAggregatedConstructs(ConstructTypeEnum.vocab, userL2.langCodeShort)
        .then((map) => map.values.toList());

    // Decided once, at the start: the session keeps this mode if the
    // connection comes or goes while it runs.
    final offline = ConnectionStatusController.instance.cannotReachPangea;

    if (offline && type == ConstructTypeEnum.vocab) {
      await LemmaInfoRepo.instance.cacheReady;
      targets.addAll(
        await VocabMeaningTargetGenerator.get(vocabConstructs, offline: true),
      );
    } else if (type == ConstructTypeEnum.vocab) {
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
        offline: offline,
      );
      targets.addAll(errorTargets);

      if (targets.length < AnalyticsPracticeConstants.targetsToGenerate) {
        final morphConstructs = await analytics
            .getAggregatedConstructs(
              ConstructTypeEnum.morph,
              userL2.langCodeShort,
            )
            .then((map) => map.values.toList());
        final morphs = await GrammarMatchTargetGenerator.get(
          morphConstructs,
          offline: offline,
        );
        final remainingCount =
            AnalyticsPracticeConstants.targetsToGenerate - targets.length;

        final morphEntries = morphs.take(remainingCount);
        targets.addAll(morphEntries);
      }
    }

    if (targets.isEmpty) {
      throw InsufficientDataException(offline: offline);
    }

    targets.shuffle();
    final session = AnalyticsPracticeSessionModel(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      // startedAt is deliberately left unset here — selection is not the start
      // of practice. The clock is stamped when the first exercise paints.
      type: type,
      practiceTargets: targets,
      offline: offline,
    );
    return session;
  }

  /// Whether the connection banner may offer an offline vocab session: the app
  /// does not know the learner to be unsubscribed, and this device has a full
  /// session's worth of different words whose meanings are saved on it. Reads
  /// the learner's whole vocab, so the banner asks once per lost connection,
  /// not on every build. See connection-status.instructions.md, "What the
  /// user sees".
  static Future<bool> canStartOffline() async {
    final pangea = MatrixState.pangeaController;
    if (!pangea.subscriptionController.showSubscriptionGatedContent) {
      return false;
    }
    final l2 = pangea.userController.userL2;
    if (l2 == null) return false;

    try {
      await LemmaInfoRepo.instance.cacheReady;
      final ids = await pangea.matrixState.analyticsDataService
          .getAggregatedConstructIds(ConstructTypeEnum.vocab, l2.langCodeShort);
      final lemmas = <String>{};
      for (final id in ids) {
        if (id.knownMeanings.isEmpty) continue;
        lemmas.add(id.lemma);
        if (lemmas.length >= AnalyticsPracticeConstants.practiceGroupSize) {
          return true;
        }
      }
      return false;
    } catch (e, s) {
      // Asked again on every lost connection, so one report a session.
      ErrorHandler.logErrorOnce(
        key: 'AnalyticsPracticeSessionRepo.canStartOffline',
        e: e,
        s: s,
        data: {'l2': l2.langCodeShort},
      );
      return false;
    }
  }
}
