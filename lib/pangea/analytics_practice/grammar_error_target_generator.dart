import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GrammarErrorTargetGenerator {
  static Future<List<AnalyticsActivityTarget>> get(
    List<ConstructUses> constructs,
  ) async {
    final useTypes = [ConstructUseTypeEnum.corGE, ConstructUseTypeEnum.incGE];
    final cutoffTime = DateTime.now().subtract(const Duration(hours: 24));

    final client = MatrixState.pangeaController.matrixState.client;
    final Map<String, PangeaMessageEvent?> idsToEvents = {};

    final targets = <AnalyticsActivityTarget>[];
    for (final construct in constructs) {
      final errorUses = construct.cappedUses
          .where((u) => u.useType == ConstructUseTypeEnum.ga)
          .toList();
      if (errorUses.isEmpty) continue;

      final lastPracticeUse = construct.lastUseByTypes(useTypes);
      debugPrint(
        "Construct ${construct.id.toJson()} - last practice use: $lastPracticeUse, error uses: ${errorUses.length}",
      );
      if (lastPracticeUse != null && lastPracticeUse.isAfter(cutoffTime)) {
        continue;
      }

      for (final use in errorUses) {
        final eventID = use.metadata.eventId;
        if (eventID == null || idsToEvents.containsKey(eventID)) continue;
        idsToEvents[eventID] = await client.getEventByConstructUse(use);
      }

      final l2Code =
          MatrixState.pangeaController.userController.userL2!.langCodeShort;

      final events = idsToEvents.values
          .whereType<PangeaMessageEvent>()
          .toList();

      final eventsWithContent = events.where((e) {
        final originalSent = e.originalSent;
        final choreo = originalSent?.choreo;
        final tokens = originalSent?.tokens;
        return originalSent?.langCode.split("-").first == l2Code &&
            choreo != null &&
            tokens != null &&
            tokens.isNotEmpty &&
            choreo.choreoSteps.any(
              (step) =>
                  step.acceptedOrIgnoredMatch?.isGrammarMatch == true &&
                  step.acceptedOrIgnoredMatch?.match.bestChoice != null,
            );
      });

      for (final event in eventsWithContent) {
        final originalSent = event.originalSent!;
        final choreo = originalSent.choreo!;
        final tokens = originalSent.tokens!;

        for (int i = 0; i < choreo.choreoSteps.length; i++) {
          final step = choreo.choreoSteps[i];
          final igcMatch = step.acceptedOrIgnoredMatch;
          final stepText = choreo.stepText(stepIndex: i - 1);
          if (igcMatch?.isGrammarMatch != true ||
              igcMatch?.match.bestChoice == null) {
            continue;
          }

          if (igcMatch!.match.offset == 0 &&
              igcMatch.match.length >= stepText.trim().characters.length) {
            continue;
          }

          if (igcMatch.match.isNormalizationError()) {
            // Skip normalization errors
            continue;
          }

          final choices = igcMatch.match.choices!.map((c) => c.value).toList();
          final choiceTokens = tokens
              .where(
                (token) =>
                    token.lemma.saveVocab &&
                    choices.any(
                      (choice) => choice.contains(token.text.content),
                    ),
              )
              .toList();

          // Skip if no valid tokens found for this grammar error, or only one answer
          if (choiceTokens.length <= 1) continue;

          String? translation;
          try {
            translation = await event.requestRespresentationByL1();
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

          targets.add(
            AnalyticsActivityTarget(
              target: PracticeTarget(
                tokens: choiceTokens,
                activityType: ActivityTypeEnum.grammarError,
              ),
              grammarErrorInfo: GrammarErrorRequestInfo(
                choreo: choreo,
                stepIndex: i,
                eventID: event.eventId,
                translation: translation,
              ),
            ),
          );
        }
      }
    }

    return targets;
  }
}
