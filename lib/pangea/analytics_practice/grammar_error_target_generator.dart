import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_practice_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GrammarErrorTargetGenerator {
  static ActivityTypeEnum activityType = ActivityTypeEnum.grammarError;

  static Future<List<AnalyticsActivityTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    // Score and sort by priority (highest first). Uses shared scorer for
    // consistent prioritization with message practice.
    final sortedConstructs = constructs.practiceSort(activityType);

    final client = MatrixState.pangeaController.matrixState.client;
    final Set<String> seenEventIDs = {};
    final cutoffTime = DateTime.now().subtract(const Duration(hours: 24));

    final targets = <AnalyticsActivityTarget>[];
    for (final construct in sortedConstructs) {
      final lastPracticeUse = construct.lastUseByTypes(
        activityType.associatedUseTypes,
      );

      if (lastPracticeUse != null && lastPracticeUse.isAfter(cutoffTime)) {
        continue;
      }

      final errorUses = construct.cappedUses.where(
        (u) => u.useType == ConstructUseTypeEnum.ga,
      );
      if (errorUses.isEmpty) continue;

      for (final use in errorUses) {
        final eventID = use.metadata.eventId;
        if (eventID == null || seenEventIDs.contains(eventID)) continue;

        final event = await client.getEventByConstructUse(use);
        seenEventIDs.add(eventID);

        if (event == null) continue;
        final eventTargets = await _getTargetsFromEvent(event, construct.id);
        if (eventTargets != null) {
          targets.add(eventTargets);
          if (targets.length >= AnalyticsPracticeConstants.targetsToGenerate) {
            return targets;
          }
        }
      }
    }

    return targets;
  }

  static Future<AnalyticsActivityTarget?> _getTargetsFromEvent(
    PangeaMessageEvent event,
    ConstructIdentifier constructId,
  ) async {
    final l2Code =
        MatrixState.pangeaController.userController.userL2!.langCodeShort;
    final originalSent = event.originalSent;
    if (originalSent?.langCode.split("-").first != l2Code) {
      return null;
    }

    final choreo = originalSent?.choreo;
    if (choreo == null ||
        !choreo.choreoSteps.any(
          (step) =>
              step.acceptedOrIgnoredMatch?.isGrammarMatch == true &&
              step.acceptedOrIgnoredMatch?.match.bestChoice != null,
        )) {
      return null;
    }

    final tokens = originalSent?.tokens;
    if (tokens == null || tokens.isEmpty) {
      return null;
    }

    String? translation;
    for (int i = 0; i < choreo.choreoSteps.length; i++) {
      final step = choreo.choreoSteps[i];
      final igcMatch = step.acceptedOrIgnoredMatch;
      if (igcMatch?.isGrammarMatch != true ||
          igcMatch?.match.bestChoice == null) {
        continue;
      }

      final stepText = choreo.stepText(stepIndex: i - 1);
      final errorSpan = stepText.characters
          .skip(igcMatch!.match.offset)
          .take(igcMatch.match.length)
          .toString();

      if (igcMatch.match.isNormalizationError(errorSpanOverride: errorSpan)) {
        continue;
      }

      if (igcMatch.match.offset == 0 &&
          igcMatch.match.length >= stepText.trim().characters.length) {
        continue;
      }

      final choices = igcMatch.match.choices!.map((c) => c.value).toList();
      final choiceTokens = tokens
          .where(
            (token) =>
                token.lemma.saveVocab &&
                choices.any((choice) => choice.contains(token.text.content)),
          )
          .toList();

      if (!choiceTokens.any((t) => t.lemma.text == constructId.lemma)) {
        continue;
      }

      // Skip if no valid tokens found for this grammar error, or only one answer
      if (choiceTokens.length <= 1) continue;

      try {
        translation ??= await event.requestRespresentationByL1();
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {
            'context': 'AnalyticsPracticeSessionRepo._fetchErrors',
            'message': 'Failed to fetch translation for analytics practice',
            'event_id': event.eventId,
          },
        );
      }

      if (translation == null) continue;
      return AnalyticsActivityTarget(
        target: PracticeTarget(
          tokens: choiceTokens,
          activityType: activityType,
        ),
        grammarErrorInfo: GrammarErrorRequestInfo(
          choreo: choreo,
          stepIndex: i,
          eventID: event.eventId,
          translation: translation,
        ),
      );
    }

    return null;
  }
}
