import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../repo/similarity_repo.dart';

class AlternativeTranslator {
  final Choreographer choreographer;
  bool showAlternativeTranslations = false;
  bool loadingAlternativeTranslations = false;
  bool showTranslationFeedback = false;
  String? userTranslation;
  FeedbackKey? translationFeedbackKey;
  List<String> translations = [];
  SimilartyResponseModel? similarityResponse;

  // Counts for tracking newly learned items
  int _vocabCountBefore = 0;
  int _grammarCountBefore = 0;

  AlternativeTranslator(this.choreographer);

  void clear() {
    userTranslation = null;
    showAlternativeTranslations = false;
    loadingAlternativeTranslations = false;
    showTranslationFeedback = false;
    translationFeedbackKey = null;
    translations = [];
    similarityResponse = null;
  }

  // Whatever was changed before for stars and counts was inaccurate and did not work,
  // this is a new implemention for the counts. Be careful changing this again, please check the accuracy!

  // Capture counts before translation starts
  void captureCountsBefore() {
    final constructListModel =
        MatrixState.pangeaController.getAnalytics.constructListModel;

    final allVocabConstructs =
        constructListModel.constructList(type: ConstructTypeEnum.vocab);
    final allMorphConstructs =
        constructListModel.constructList(type: ConstructTypeEnum.morph);

    _vocabCountBefore = allVocabConstructs.length;
    _grammarCountBefore = allMorphConstructs.length;
  }

  // Calculate percentage of choices that were correct on first attempt
  double get percentCorrectChoices {
    final totalSteps = choreographer.choreoRecord.itSteps.length;
    if (totalSteps == 0) return 0.0;

    // Count steps where there were no wrong clicks
    final int correctFirstAttempts = choreographer.itController.completedITSteps
        .where(
          (step) => !step.continuances.any(
            (c) =>
                c.level != ChoreoConstants.levelThresholdForGreen &&
                c.wasClicked,
          ),
        )
        .length;

    final double percentage = (correctFirstAttempts / totalSteps) * 100;
    return percentage;
  }

  // More accurate calculation for first-attempt accuracy
  double get actualFirstAttemptPercentage {
    final steps = choreographer.itController.completedITSteps;
    if (steps.isEmpty) return 0.0;

    // For each step, determine if the chosen continuance was the first and only click
    int correctFirstAttempts = 0;

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];

      // Count all clicked continuances in this step
      final clickedContinuances =
          step.continuances.where((c) => c.wasClicked).toList();

      // If there's exactly one clicked continuance and it's the chosen one,
      // and it's correct (green or gold), this is a correct first attempt
      if (step.chosen != null &&
          clickedContinuances.length == 1 &&
          clickedContinuances.first == step.continuances[step.chosen!] &&
          (step.chosenContinuance!.level ==
                  ChoreoConstants.levelThresholdForGreen ||
              step.chosenContinuance!.gold)) {
        correctFirstAttempts++;
      }
    }

    final percentage = (correctFirstAttempts / steps.length) * 100;
    return percentage;
  }

  // Use the accurate calculation for star rating
  int get fixedStarRating {
    final double percent = actualFirstAttemptPercentage;

    if (percent >= 99.9) return 5;
    if (percent >= 80) return 4;
    if (percent >= 60) return 3;
    if (percent >= 40) return 2;
    if (percent > 0) return 1;
    return 0;
  }

  // Count new vocabulary words by comparing before and after
  int countVocabularyWordsFromSteps() {
    final constructListModel =
        MatrixState.pangeaController.getAnalytics.constructListModel;
    final allVocabConstructs =
        constructListModel.constructList(type: ConstructTypeEnum.vocab);
    final vocabCountAfter = allVocabConstructs.length;

    final newVocabCount = max(0, vocabCountAfter - _vocabCountBefore);

    return newVocabCount;
  }

  // Count new grammar constructs by comparing before and after
  int countGrammarConstructsFromSteps() {
    final constructListModel =
        MatrixState.pangeaController.getAnalytics.constructListModel;
    final allMorphConstructs =
        constructListModel.constructList(type: ConstructTypeEnum.morph);
    final grammarCountAfter = allMorphConstructs.length;

    final newGrammarCount = max(0, grammarCountAfter - _grammarCountBefore);

    return newGrammarCount;
  }

  // Set feedback based on performance
  Future<void> setTranslationFeedback() async {
    try {
      choreographer.startLoading();
      translationFeedbackKey = FeedbackKey.loadingPleaseWait;
      showTranslationFeedback = true;
      userTranslation = choreographer.currentText;

      // Use the actual first attempt percentage for feedback
      final double percentCorrect = actualFirstAttemptPercentage;

      // Set feedback based on percentage
      if (percentCorrect >= 99.9) {
        translationFeedbackKey = FeedbackKey.allCorrect;
      } else if (percentCorrect >= 80) {
        translationFeedbackKey = FeedbackKey.newWayAllGood;
      } else {
        translationFeedbackKey = FeedbackKey.othersAreBetter;
      }
    } catch (err, stack) {
      if (err is! http.Response) {
        ErrorHandler.logError(
          e: err,
          s: stack,
          data: {
            "sourceText": choreographer.itController.sourceText,
            "currentText": choreographer.currentText,
            "userL1": choreographer.l1LangCode,
            "userL2": choreographer.l2LangCode,
            "goldRouteTranslation":
                choreographer.itController.goldRouteTracker.fullTranslation,
          },
        );
      }
      choreographer.errorService.setError(
        ChoreoError(type: ChoreoErrorType.unknown, raw: err),
      );
    } finally {
      choreographer.stopLoading();
    }
  }

  // Get the appropriate feedback text
  String getDefaultFeedback(BuildContext context) {
    final l10n = L10n.of(context);
    switch (translationFeedbackKey) {
      case FeedbackKey.allCorrect:
        return l10n.perfectTranslation;
      case FeedbackKey.newWayAllGood:
        return l10n.greatJobTranslation;
      case FeedbackKey.othersAreBetter:
        final percent = actualFirstAttemptPercentage;
        if (percent >= 60) {
          return l10n.goodJobTranslation;
        }
        if (percent >= 40) {
          return l10n.makingProgress;
        }
        return l10n.keepPracticing;
      case FeedbackKey.loadingPleaseWait:
        return l10n.letMeThink;
      case FeedbackKey.allDone:
        return l10n.allDone;
      default:
        return l10n.loadingPleaseWait;
    }
  }
}

enum FeedbackKey {
  allCorrect,
  newWayAllGood,
  othersAreBetter,
  loadingPleaseWait,
  allDone,
}

extension FeedbackKeyExtension on FeedbackKey {}
