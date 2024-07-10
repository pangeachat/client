import 'dart:developer';

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/repo/full_text_translation_repo.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:http/http.dart' as http;

import '../../repo/similarity_repo.dart';

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

  // void onSeeAlternativeTranslationsTap() {
  //   if (choreographer.itController.sourceText == null) {
  //     ErrorHandler.logError(
  //       m: "sourceText null in onSeeAlternativeTranslationsTap",
  //       s: StackTrace.current,
  //     );
  //     choreographer.itController.closeIT();
  //     return;
  //   }
  //   showAlternativeTranslations = true;
  //   loadingAlternativeTranslations = true;
  //   translate(choreographer.itController.sourceText!);
  //   choreographer.setState();
  // }

  // Future<void> translate(String text) async {
  //   throw Exception('disabled translaations');
  //   try {
  //     final FullTextTranslationResponseModel results =
  //         await FullTextTranslationRepo.translate(
  //       accessToken: await choreographer.accessToken,
  //       request: FullTextTranslationRequestModel(
  //         text: text,
  //         tgtLang: choreographer.l2LangCode!,
  //         userL2: choreographer.l2LangCode!,
  //         userL1: choreographer.l1LangCode!,
  //       ),
  //     );
  //     // translations = results.translations;
  //   } catch (err, stack) {
  //     showAlternativeTranslations = false;
  //     debugger(when: kDebugMode);
  //     ErrorHandler.logError(e: err, s: stack);
  //   } finally {
  //     loadingAlternativeTranslations = false;
  //     choreographer.setState();
  //   }
  // }

  Future<void> setTranslationFeedback() async {
    try {
      choreographer.startLoading();
      translationFeedbackKey = FeedbackKey.loadingPleaseWait;

      showTranslationFeedback = true;

      userTranslation = choreographer.currentText;

      if (choreographer.itController.allCorrect) {
        translationFeedbackKey = FeedbackKey.allCorrect;
        return;
      }

      final String? goldRouteTranslation =
          choreographer.itController.goldRouteTracker.fullTranslation;

      final accessToken = await choreographer.accessToken;
      if (accessToken == null) {
        ErrorHandler.logError(
          m: "accessToken null in setTranslationFeedback",
          s: StackTrace.current,
        );
        translationFeedbackKey = FeedbackKey.loadingPleaseWait;
        return;
      }

      final FullTextTranslationResponseModel results =
          await FullTextTranslationRepo.translate(
        accessToken: accessToken,
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
      // final List<String> altAndUser = [...results.translations];
      // if (results.deepL != null) {
      //   altAndUser.add(results.deepL!);
      // }
      // altAndUser.add(userTranslation);

      if (userTranslation?.toLowerCase() ==
          results.bestTranslation.toLowerCase()) {
        translationFeedbackKey = FeedbackKey.allCorrect;
        return;
      }

      similarityResponse = await SimilarityRepo.get(
        accessToken: accessToken,
        request: SimilarityRequestModel(
          benchmark: results.bestTranslation,
          toCompare: [userTranslation!],
        ),
      );

      // if (similarityResponse!
      //     .userTranslationIsSameAsBotTranslation(userTranslation!)) {
      //   translationFeedbackKey = FeedbackKey.allCorrect;
      //   return;
      // }

      // if (similarityResponse!
      //     .userTranslationIsDifferentButBetter(userTranslation!)) {
      //   translationFeedbackKey = FeedbackKey.newWayAllGood;
      //   return;
      // }
      showAlternativeTranslations = true;
      translationFeedbackKey = FeedbackKey.othersAreBetter;
    } catch (err, stack) {
      if (err is! http.Response) {
        ErrorHandler.logError(e: err, s: stack);
      }
      choreographer.errorService.setError(
        ChoreoError(type: ChoreoErrorType.unknown, raw: err),
      );
    } finally {
      choreographer.stopLoading();
    }
  }

  String translationFeedback(BuildContext context) {
    if (L10n.of(context) == null) {
      debugger(when: kDebugMode);
    }
    switch (translationFeedbackKey) {
      case FeedbackKey.allCorrect:
        return "Score: 100%\n${L10n.of(context)!.allCorrect}";
      case FeedbackKey.newWayAllGood:
        return "Score: 100%\n${L10n.of(context)!.newWayAllGood}";
      case FeedbackKey.othersAreBetter:
        final num userScore =
            (similarityResponse!.userScore(userTranslation!) * 100).round();
        final String displayScore = userScore.toString();
        if (userScore > 90) {
          return "Score: $displayScore%\n${L10n.of(context)!.almostPerfect}";
        }
        if (userScore > 80) {
          return "Score: $displayScore%\n${L10n.of(context)!.prettyGood}";
        }
        return "Score: $displayScore%\n${L10n.of(context)!.othersAreBetter}";
      // case FeedbackKey.commonalityFeedback:
      //     final int count = controller.completedITSteps
      //   .where((element) => element.isCorrect)
      //   .toList()
      //   .length;
      // final int total = controller.completedITSteps.length;
      //     return L10n.of(context)!.commonalityFeedback(count,total);
      case FeedbackKey.loadingPleaseWait:
        return L10n.of(context)!.letMeThink;
      case FeedbackKey.allDone:
        return L10n.of(context)!.allDone;
      default:
        return L10n.of(context)!.loadingPleaseWait;
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
