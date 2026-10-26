import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_match_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_target_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class InsufficientDataException implements Exception {
  /// The session was to run offline, so what it lacks is data saved on this
  /// device. See practice-exercises.instructions.md, "Offline Practice".
  final bool offline;

  const InsufficientDataException({this.offline = false});
}

class AnalyticsPracticeSessionRepo {
  /// Select a session's targets. With [missionId], a vocab session is scoped
  /// to that Mission's target vocabulary (#9438): the learner's own
  /// constructs for those words first, then a meaning exercise built straight
  /// from the plan for each word they have never used, so a Mission's words
  /// can be practised before they have come up in a conversation. Grammar
  /// practice has no vocabulary to scope by and ignores the Mission.
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
    LanguageModel userL1,
    LanguageModel userL2, {
    String? missionId,
  }) async {
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      throw UnsubscribedException();
    }

    final List<AnalyticsPracticeTarget> targets = [];
    final analytics =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    var vocabConstructs = await analytics
        .getAggregatedConstructs(ConstructTypeEnum.vocab, userL2.langCodeShort)
        .then((map) => map.values.toList());

    QuestObjectiveGroup? scope;
    if (missionId != null && type == ConstructTypeEnum.vocab) {
      scope = await MatrixState.pangeaController.matrixState.client
          .joinedMissionGroup(missionId);
      // silent-ok: a Mission no joined course carries (a stale link, a course
      // since left) falls back to the learner's usual session rather than an
      // empty panel; nothing is lost but the scope.
      if (scope != null) {
        final lemmas = scope.lemmas;
        vocabConstructs = vocabConstructs
            .where(
              (c) => lemmas.contains(QuestObjectiveGroup.lemmaKey(c.lemma)),
            )
            .toList();
      }
    }

    // Decided once, at the start: the session keeps this mode if the
    // connection comes or goes while it runs.
    final offline = ConnectionStatusController.instance.cannotReachPangea;

    if (offline && type == ConstructTypeEnum.vocab) {
      await LemmaInfoRepo.instance.cacheReady;
      targets.addAll(
        await VocabMeaningTargetGenerator.get(vocabConstructs, offline: true),
      );
    } else if (type == ConstructTypeEnum.vocab) {
      // About a third each of listening, read-aloud and meaning, by count:
      // speaking is in every session without an item that needs a microphone
      // and the network dominating it (practice-exercises.instructions.md,
      // "Speaking practice"). Listening and read-aloud share the one pool of
      // example-bearing words; meaning fills whatever is left.
      final totalNeeded = AnalyticsPracticeConstants.targetsToGenerate;
      final thirdNeeded = (totalNeeded / 3).ceil();

      final exampleTargets = await VocabAudioTargetGenerator.get(
        vocabConstructs,
      );
      final spokenTargets = alternateListeningAndReadAloud(
        exampleTargets,
        each: thirdNeeded,
      );

      final vocabNeeded = totalNeeded - spokenTargets.length;
      final vocabTargets = await VocabMeaningTargetGenerator.get(
        vocabConstructs,
      );
      final vocabCount = min(vocabTargets.length, vocabNeeded);

      targets.addAll(spokenTargets);
      targets.addAll(vocabTargets.take(vocabCount));

      if (scope != null) {
        // The Mission's words the learner has never used — no construct, so
        // no example message — as meaning exercises from the plan's own
        // lemma and part of speech. Phrases are skipped: the meaning
        // generator's distractors are per lemma, not per set phrase.
        final covered = {
          for (final target in targets)
            QuestObjectiveGroup.lemmaKey(target.target.tokens.first.lemma.text),
        };
        final words = [
          for (final word in scope.vocab)
            if (word.pos != 'phrase') word,
        ];
        for (final word in words) {
          if (targets.length >= totalNeeded) break;
          final lemma = QuestObjectiveGroup.lemmaKey(word.lemma);
          if (covered.contains(lemma)) continue;
          covered.add(lemma);
          targets.add(
            AnalyticsPracticeTarget(
              target: PracticeTarget(
                tokens: [word.asToken()],
                exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
                // The Mission's other words as wrong answers, so a learner
                // with little vocabulary of their own still gets a real
                // multiple choice.
                distractorCandidates: [
                  for (final other in words)
                    if (other.lemma.toLowerCase() != lemma)
                      other.asToken().vocabConstructID,
                ],
              ),
            ),
          );
        }
      }
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
      missionId: scope?.objective.id,
      missionLabel: scope?.objective.objective,
      offline: offline,
    );
    return session;
  }

  /// Listening and read-aloud both need an example-bearing word and the pool
  /// can be small, so the two take turns down the one priority order,
  /// listening first, up to [each] apiece. Giving listening its whole share
  /// first starved read-aloud whenever the pool held [each] words or fewer.
  @visibleForTesting
  static List<AnalyticsPracticeTarget> alternateListeningAndReadAloud(
    List<AnalyticsPracticeTarget> exampleTargets, {
    required int each,
  }) {
    final listening = <AnalyticsPracticeTarget>[];
    final readAloud = <AnalyticsPracticeTarget>[];
    for (final target in exampleTargets) {
      final listeningFull = listening.length >= each;
      final readAloudFull = readAloud.length >= each;
      if (listeningFull && readAloudFull) break;
      if (readAloudFull ||
          (!listeningFull && listening.length <= readAloud.length)) {
        listening.add(target);
      } else {
        readAloud.add(
          AnalyticsPracticeTarget(
            target: PracticeTarget(
              tokens: target.target.tokens,
              exerciseType: PracticeExerciseTypeEnum.readAloud,
            ),
          ),
        );
      }
    }
    return [...listening, ...readAloud];
  }

  /// Whether the connection banner may offer an offline vocab session: the app
  /// does not know the learner to be unsubscribed, and this device has a full
  /// session's worth of different words whose meanings are saved on it. Reads
  /// the learner's whole vocab, so the banner asks once per lost connection,
  /// not on every build. See connection-status.instructions.md, "What the
  /// user sees".
  static Future<bool> canStartOffline() async {
    final pangea = MatrixState.pangeaController;
    // The banner shows on the sign-in page too, where nobody has words saved.
    if (!pangea.matrixState.client.isLogged()) return false;
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
