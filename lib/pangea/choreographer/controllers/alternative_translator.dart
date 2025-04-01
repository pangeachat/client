import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
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

  double get _percentCorrectChoices {
    final totalSteps = choreographer.choreoRecord.itSteps.length;
    if (totalSteps == 0) return 0.0;
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

  int get starRating {
    final double percent = _percentCorrectChoices;
    if (percent == 100) return 5;
    if (percent >= 80) return 4;
    if (percent >= 60) return 3;
    if (percent >= 40) return 2;
    if (percent > 0) return 1;
    return 0;
  }

  Future<void> setTranslationFeedback() async {
    try {
      choreographer.startLoading();
      translationFeedbackKey = FeedbackKey.loadingPleaseWait;
      showTranslationFeedback = true;
      userTranslation = choreographer.currentText;

      final double percentCorrect = _percentCorrectChoices;

      // Set feedback based on percentage
      if (percentCorrect == 100) {
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

  String translationFeedback(BuildContext context) {
    try {
      // Count vocabulary words and grammar constructs
      final int vocabCount = countVocabularyWordsFromSteps();
      final int grammarCount = countGrammarConstructsFromSteps();

      // Build the feedback message with icons
      if (vocabCount > 0 || grammarCount > 0) {
        String message = "";

        if (vocabCount > 0) {
          message = "Vocab +$vocabCount";
        }

        if (grammarCount > 0) {
          // If there was already vocabulary, add spacing
          if (message.isNotEmpty) {
            message += "   Grammar +$grammarCount";
          } else {
            message = "Grammar +$grammarCount";
          }
        }

        return message;
      }

      // Fall back to performance-based feedback
      return getDefaultFeedback(context);
    } catch (e, stack) {
      debugPrint("Error in feedback: $e");
      ErrorHandler.logError(
        e: e,
        s: stack,
        data: {"currentText": choreographer.currentText},
      );

      return getDefaultFeedback(context);
    }
  }

  int countVocabularyWordsFromSteps() {
    // Get completed steps from the IT controller
    final completedSteps = choreographer.itController.completedITSteps;
    if (completedSteps.isEmpty) return 0;

    final Set<String> uniqueLemmas = {};

    // Go through each completed step
    for (final step in completedSteps) {
      if (step.chosen != null && step.continuances.isNotEmpty) {
        final continuance = step.continuances[step.chosen!];

        // If it's a correct choice (level 1)
        if (continuance.level == 1 || continuance.gold) {
          for (final token in continuance.tokens) {
            // Only count tokens that are marked as save_vocab
            if (token.lemma.saveVocab) {
              uniqueLemmas.add(token.lemma.text);
            }
          }
        }
      }
    }

    return uniqueLemmas.length;
  }

  int countGrammarConstructsFromSteps() {
    // Get completed steps from the IT controller
    final completedSteps = choreographer.itController.completedITSteps;
    if (completedSteps.isEmpty) return 0;

    final Set<String> uniqueGrammarFeatures = {};
    final Set<String> uniquePOSCategories = {};

    // Go through each completed step
    for (final step in completedSteps) {
      if (step.chosen != null && step.continuances.isNotEmpty) {
        final continuance = step.continuances[step.chosen!];

        // If it's a correct choice (level 1 or gold)
        if (continuance.level == 1 || continuance.gold) {
          for (final token in continuance.tokens) {
            if (!['DET', 'PUNCT', 'SYM', 'X', 'PART', 'ADP']
                .contains(token.pos)) {
              uniquePOSCategories.add(token.pos);
            }

            token.morph.forEach((feature, value) {
              if (feature.name.toUpperCase() != 'POS' &&
                  value.toString().isNotEmpty) {
                uniqueGrammarFeatures.add("$feature:$value");
              }
            });
          }
        }
      }
    }

    return uniquePOSCategories.length + uniqueGrammarFeatures.length;
  }

  String getDefaultFeedback(BuildContext context) {
    switch (translationFeedbackKey) {
      case FeedbackKey.allCorrect:
        return "Perfect translation!";
      case FeedbackKey.newWayAllGood:
        return "Great job with this translation!";
      case FeedbackKey.othersAreBetter:
        if (_percentCorrectChoices >= 60) {
          return "Good work on this translation.";
        }
        if (_percentCorrectChoices >= 40) {
          return "You're making progress!";
        }
        return "Keep practicing!";
      case FeedbackKey.loadingPleaseWait:
        return L10n.of(context).letMeThink;
      case FeedbackKey.allDone:
        return L10n.of(context).allDone;
      default:
        return L10n.of(context).loadingPleaseWait;
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
