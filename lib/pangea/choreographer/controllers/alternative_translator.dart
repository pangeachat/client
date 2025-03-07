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
  
  // Add tracking for first-try correct attempts
  List<bool> firstTryCorrectFlags = [];
  Set<String> attemptedTranslations = {}; // Track which translations have been attempted

  AlternativeTranslator(this.choreographer);

  void clear({bool clearTracking = false}) {
    userTranslation = null;
    showAlternativeTranslations = false;
    loadingAlternativeTranslations = false;
    showTranslationFeedback = false;
    translationFeedbackKey = null;
    translations = [];
    similarityResponse = null;
    
    // Only clear tracking data if explicitly requested
    if (clearTracking) {
      firstTryCorrectFlags = [];
      attemptedTranslations = {};
    }
  }
  
  // Method to record a translation attempt
  void recordTranslationAttempt(String translation) {
    if (translations.isEmpty) return; // Safety check
    
    // Check if this is a correct translation (matches the first one)
    bool isCorrect = translation.toLowerCase() == translations.first.toLowerCase();
    
    // Only record first attempts for each translation
    if (!attemptedTranslations.contains(translation)) {
      attemptedTranslations.add(translation);
      firstTryCorrectFlags.add(isCorrect);
    }
  }
  
  // Get percentage of correct first attempts
  int getFirstTryCorrectPercentage() {
    if (firstTryCorrectFlags.isEmpty) return 100; // Default to 100% if no attempts
    
    int correctCount = firstTryCorrectFlags.where((isCorrect) => isCorrect).length;
    return ((correctCount / firstTryCorrectFlags.length) * 100).round();
  }

  Future<void> setTranslationFeedback() async {
    try {
      choreographer.startLoading();
      translationFeedbackKey = FeedbackKey.loadingPleaseWait;

      showTranslationFeedback = true;

      userTranslation = choreographer.currentText;

      if (choreographer.itController.allCorrect) {
        // Even if all correct by the end, we still use first-try percentage for feedback
        int correctPercentage = getFirstTryCorrectPercentage();
        if (correctPercentage == 100) {
          translationFeedbackKey = FeedbackKey.allCorrect;
        } else if (correctPercentage > 90) {
          translationFeedbackKey = FeedbackKey.newWayAllGood;
        } else {
          translationFeedbackKey = FeedbackKey.othersAreBetter;
        }
        return;
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

      if (userTranslation?.toLowerCase() ==
          results.bestTranslation.toLowerCase()) {
        // This is for the case where the user's final translation is correct
        // We still use first-try percentage for feedback
        int correctPercentage = getFirstTryCorrectPercentage();
        if (correctPercentage == 100) {
          translationFeedbackKey = FeedbackKey.allCorrect;
        } else if (correctPercentage > 90) {
          translationFeedbackKey = FeedbackKey.newWayAllGood;
        } else {
          translationFeedbackKey = FeedbackKey.othersAreBetter;
        }
        return;
      }

      similarityResponse = await SimilarityRepo.get(
        accessToken: choreographer.accessToken,
        request: SimilarityRequestModel(
          benchmark: results.bestTranslation,
          toCompare: [userTranslation!],
        ),
      );

      showAlternativeTranslations = true;
      
      // Set feedback based on first-try percentage
      int correctPercentage = getFirstTryCorrectPercentage();
      if (correctPercentage > 90) {
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
    int correctPercentage = getFirstTryCorrectPercentage();
    String displayScore = correctPercentage.toString();
    
    switch (translationFeedbackKey) {
      case FeedbackKey.allCorrect:
        return "Match: $displayScore%\n${L10n.of(context).allCorrect}";
      case FeedbackKey.newWayAllGood:
        return "Match: $displayScore%\n${L10n.of(context).newWayAllGood}";
      case FeedbackKey.othersAreBetter:
        if (correctPercentage > 90) {
          return "Match: $displayScore%\n${L10n.of(context).almostPerfect}";
        }
        if (correctPercentage > 80) {
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