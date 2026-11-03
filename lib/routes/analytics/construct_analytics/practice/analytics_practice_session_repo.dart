import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_error_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/grammar_match_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_skills_store.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_target_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_target_generator.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
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
  ///
  /// A vocab session's words are picked here once, whatever [skills] the
  /// learner has on at the start page; [skills] only decides which exercise
  /// each word gets (see [AnalyticsPracticeSessionModel.vocab]).
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
    LanguageModel userL1,
    LanguageModel userL2, {
    String? missionId,
    Set<LearningSkillsEnum> skills = PracticeSkillsStore.vocabSkills,
  }) async {
    if (!MatrixState
        .pangeaController
        .subscriptionController
        .showSubscriptionGatedContent) {
      throw UnsubscribedException();
    }

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
    final userL1Code =
        MatrixState.pangeaController.userController.userL1!.langCode;
    final userL2Code =
        MatrixState.pangeaController.userController.userL2!.langCode;

    if (type == ConstructTypeEnum.vocab) {
      final words = <PracticeWord>[];
      if (offline) {
        await LemmaInfoRepo.instance.cacheReady;
        // Offline a session has meaning exercises only
        // (practice-exercises.instructions.md, "Offline Practice").
        for (final target in await VocabMeaningTargetGenerator.get(
          vocabConstructs,
          offline: true,
        )) {
          words.add(
            PracticeWord(
              token: target.target.tokens.first,
              skills: {LearningSkillsEnum.reading},
            ),
          );
        }
      } else {
        final constructsById = {for (final c in vocabConstructs) c.id: c};
        words.addAll(
          rankVocabWords(
            await VocabMeaningTargetGenerator.get(vocabConstructs),
            await VocabAudioTargetGenerator.get(vocabConstructs),
            total: AnalyticsPracticeConstants.targetsToGenerate,
            // Both rankings hold only words with an example message, so
            // every word can be read aloud; each type's 24-hour pause
            // decides the other two.
            skillsOf: (token) {
              final construct = constructsById[token.vocabConstructID];
              return {
                if (construct?.shouldSkipForRecentPractice(
                      PracticeExerciseTypeEnum.lemmaMeaning,
                    ) !=
                    true)
                  LearningSkillsEnum.reading,
                if (construct?.shouldSkipForRecentPractice(
                      PracticeExerciseTypeEnum.lemmaAudio,
                    ) !=
                    true)
                  LearningSkillsEnum.hearing,
                LearningSkillsEnum.speaking,
              };
            },
          ),
        );
        if (scope != null) _addMissionWords(words, scope);
      }

      if (words.isEmpty) throw InsufficientDataException(offline: offline);

      // Shuffled once, so the ten the session plans to show are a random ten
      // of those picked rather than always the top-ranked, which seldom
      // include the words a learner has given an emoji to. The order is then
      // fixed for the session: the chips re-deal the words' exercises, but
      // never reorder or replace them.
      words.shuffle();
      // startedAt is deliberately left unset here — selection is not the
      // start of practice. The clock is stamped when the first exercise
      // paints.
      return AnalyticsPracticeSessionModel.vocab(
        words: words,
        skills: skills,
        userL1: userL1Code,
        userL2: userL2Code,
        missionId: scope?.objective.id,
        missionLabel: scope?.objective.objective,
        offline: offline,
      );
    }

    final targets = <AnalyticsPracticeTarget>[
      ...await GrammarErrorTargetGenerator.get(
        vocabConstructs,
        offline: offline,
      ),
    ];
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
      targets.addAll(morphs.take(remainingCount));
    }

    if (targets.isEmpty) {
      throw InsufficientDataException(offline: offline);
    }

    targets.shuffle();
    return AnalyticsPracticeSessionModel(
      userL1: userL1Code,
      userL2: userL2Code,
      type: type,
      practiceTargets: targets,
      offline: offline,
    );
  }

  /// A vocab session's words, ranked across its exercise types: the meaning
  /// and listening rankings take turns, each word once, up to [total].
  @visibleForTesting
  static List<PracticeWord> rankVocabWords(
    List<AnalyticsPracticeTarget> meaningTargets,
    List<AnalyticsPracticeTarget> listeningTargets, {
    required Set<LearningSkillsEnum> Function(PangeaToken token) skillsOf,
    required int total,
  }) {
    final seen = <ConstructIdentifier>{};
    final words = <PracticeWord>[];
    final longest = max(meaningTargets.length, listeningTargets.length);
    for (var i = 0; i < longest && words.length < total; i++) {
      for (final ranking in [meaningTargets, listeningTargets]) {
        if (i >= ranking.length || words.length >= total) continue;
        final token = ranking[i].target.tokens.first;
        if (!seen.add(token.vocabConstructID)) continue;
        words.add(PracticeWord(token: token, skills: skillsOf(token)));
      }
    }
    return words;
  }

  /// The Mission's words the learner has never used — no construct, so no
  /// example message — as meaning-only words from the plan's own lemma and
  /// part of speech, after the learner's own. Phrases are skipped: the
  /// meaning generator's distractors are per lemma, not per set phrase.
  static void _addMissionWords(
    List<PracticeWord> words,
    QuestObjectiveGroup scope,
  ) {
    final covered = {
      for (final word in words)
        QuestObjectiveGroup.lemmaKey(word.token.lemma.text),
    };
    final planWords = [
      for (final word in scope.vocab)
        if (word.pos != 'phrase') word,
    ];
    for (final word in planWords) {
      if (words.length >= AnalyticsPracticeConstants.targetsToGenerate) break;
      final lemma = QuestObjectiveGroup.lemmaKey(word.lemma);
      if (!covered.add(lemma)) continue;
      words.add(
        PracticeWord(
          token: word.asToken(),
          skills: {LearningSkillsEnum.reading},
          // The Mission's other words as wrong answers, so a learner with
          // little vocabulary of their own still gets a real multiple choice.
          distractorCandidates: [
            for (final other in planWords)
              if (other.lemma.toLowerCase() != lemma)
                other.asToken().vocabConstructID,
          ],
        ),
      );
    }
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
