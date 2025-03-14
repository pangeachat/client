import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/repo/full_text_translation_repo.dart';
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

  // Calculate the percentage of correct choices
  double get _percentCorrectChoices {
    // Get the core counts from ITController
    final correctChoices = choreographer.itController.correctChoices;
    final incorrectChoices = choreographer.itController.incorrectChoices;
    final wildcardChoices = choreographer.itController.wildcardChoices;
    final customChoices = choreographer.itController.customChoices;

    debugPrint(
        "PERCENT DEBUG: Correct: $correctChoices, Incorrect: $incorrectChoices, Wildcard: $wildcardChoices, Custom: $customChoices");

    // Total number of choices made (both correct and incorrect)
    final totalChoices =
        correctChoices + incorrectChoices + wildcardChoices + customChoices;

    if (totalChoices == 0) {
      return 0;
    }

    // Calculate percentage based on correct choices as a portion of total choices
    final percentage = (correctChoices / totalChoices) * 100;
    debugPrint("PERCENT DEBUG: Final percentage: $percentage%");

    return percentage;
  }

  Future<void> setTranslationFeedback() async {
    try {
      choreographer.startLoading();
      translationFeedbackKey = FeedbackKey.loadingPleaseWait;

      showTranslationFeedback = true;

      userTranslation = choreographer.currentText;

      // Calculate percentage based on correct/total choices ratio
      final double percentCorrect = _percentCorrectChoices;
      debugPrint("FEEDBACK: Calculated percentage correct: $percentCorrect%");

      // Set feedback based on percentage
      if (percentCorrect == 100) {
        translationFeedbackKey = FeedbackKey.allCorrect;
      } else if (percentCorrect > 90) {
        translationFeedbackKey = FeedbackKey.newWayAllGood;
      } else {
        translationFeedbackKey = FeedbackKey.othersAreBetter;
      }

      final String? goldRouteTranslation =
          choreographer.itController.goldRouteTracker.fullTranslation;

      final FullTextTranslationResponseModel results =
          await FullTextTranslationRepo.translate(
        accessToken: choreographer.accessToken,
        request: FullTextTranslationRequestModel(
          text: choreographer.itController.sourceText!,
          tgtLang: choreographer.l2LangCode!,
          userL2: choreographer.l2LangCode!,
          userL1: choreographer.l1LangCode!,
          deepL: goldRouteTranslation == null,
        ),
      );

      translations = results.translations;
      if (results.deepL != null || goldRouteTranslation != null) {
        translations.insert(0, (results.deepL ?? goldRouteTranslation)!);
      }

      if (userTranslation?.toLowerCase() !=
          results.bestTranslation.toLowerCase()) {
        similarityResponse = await SimilarityRepo.get(
          accessToken: choreographer.accessToken,
          request: SimilarityRequestModel(
            benchmark: results.bestTranslation,
            toCompare: [userTranslation!],
          ),
        );

        showAlternativeTranslations = true;
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
    final String displayScore = _percentCorrectChoices.toStringAsFixed(0);

    // Use original feedback messages
    switch (translationFeedbackKey) {
      case FeedbackKey.allCorrect:
        return "Match: $displayScore%\n${L10n.of(context).allCorrect}";
      case FeedbackKey.newWayAllGood:
        return "Match: $displayScore%\n${L10n.of(context).newWayAllGood}";
      case FeedbackKey.othersAreBetter:
        if (_percentCorrectChoices > 90) {
          return "Match: $displayScore%\n${L10n.of(context).almostPerfect}";
        }
        if (_percentCorrectChoices > 80) {
          return "Match: $displayScore%\n${L10n.of(context).prettyGood}";
        }
        return "Match: $displayScore%\n${L10n.of(context).othersAreBetter}";
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
