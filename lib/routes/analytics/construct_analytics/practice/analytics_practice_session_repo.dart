import 'dart:math';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/mission_vocab.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_match_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_target_generator.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class InsufficientDataException implements Exception {}

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

    MissionVocab? scope;
    if (missionId != null && type == ConstructTypeEnum.vocab) {
      scope = await MissionVocab.resolve(
        MatrixState.pangeaController.matrixState.client,
        missionId,
      );
      // silent-ok: a Mission no joined course carries (a stale link, a course
      // since left) falls back to the learner's usual session rather than an
      // empty panel; nothing is lost but the scope.
      if (scope != null) {
        final lemmas = scope.lemmas;
        vocabConstructs = vocabConstructs
            .where((c) => lemmas.contains(c.lemma.toLowerCase()))
            .toList();
      }
    }

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

      if (scope != null) {
        // The Mission's words the learner has never used — no construct, so
        // no example message — as meaning exercises from the plan's own
        // lemma and part of speech. Phrases are skipped: the meaning
        // generator's distractors are per lemma, not per set phrase.
        final covered = {
          for (final target in targets)
            target.target.tokens.first.lemma.text.toLowerCase(),
        };
        final words = [
          for (final word in scope.vocab)
            if (word.pos != 'phrase') word,
        ];
        for (final word in words) {
          if (targets.length >= totalNeeded) break;
          final lemma = word.lemma.toLowerCase();
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
      );
      targets.addAll(errorTargets);

      if (targets.length < AnalyticsPracticeConstants.targetsToGenerate) {
        final morphConstructs = await analytics
            .getAggregatedConstructs(
              ConstructTypeEnum.morph,
              userL2.langCodeShort,
            )
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
      // startedAt is deliberately left unset here — selection is not the start
      // of practice. The clock is stamped when the first exercise paints.
      type: type,
      practiceTargets: targets,
      missionId: scope?.objective.id,
      missionLabel: scope?.objective.objective,
    );
    return session;
  }
}
