import 'dart:math';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class InsufficientDataException implements Exception {}

class AnalyticsPracticeSessionRepo {
  static Future<AnalyticsPracticeSessionModel> get(
    ConstructTypeEnum type,
  ) async {
    if (MatrixState.pangeaController.subscriptionController.isSubscribed ==
        false) {
      throw UnsubscribedException();
    }

    final r = Random();
    final activityTypes = ActivityTypeEnum.analyticsPracticeTypes(type);

    final types = List.generate(
      AnalyticsPracticeConstants.practiceGroupSize +
          AnalyticsPracticeConstants.errorBufferSize,
      (_) => activityTypes[r.nextInt(activityTypes.length)],
    );

    final List<AnalyticsActivityTarget> targets = [];

    if (type == ConstructTypeEnum.vocab) {
      final constructs = await _fetchVocab();
      final targetCount = min(constructs.length, types.length);
      targets.addAll([
        for (var i = 0; i < targetCount; i++)
          AnalyticsActivityTarget(
            target: PracticeTarget(
              tokens: [constructs[i].asToken],
              activityType: types[i],
            ),
          ),
      ]);
    } else {
      final errorTargets = await _fetchErrors();
      targets.addAll(errorTargets);
      if (targets.length <
          (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)) {
        final morphs = await _fetchMorphs();
        final remainingCount = (AnalyticsPracticeConstants.practiceGroupSize +
                AnalyticsPracticeConstants.errorBufferSize) -
            targets.length;
        final morphEntries = morphs.entries.take(remainingCount);

        for (final entry in morphEntries) {
          targets.add(
            AnalyticsActivityTarget(
              target: PracticeTarget(
                tokens: [entry.key],
                activityType: ActivityTypeEnum.grammarCategory,
                morphFeature: entry.value,
              ),
            ),
          );
        }

        targets.shuffle();
      }
    }

    if (targets.isEmpty) {
      throw InsufficientDataException();
    }

    final session = AnalyticsPracticeSessionModel(
      userL1: MatrixState.pangeaController.userController.userL1!.langCode,
      userL2: MatrixState.pangeaController.userController.userL2!.langCode,
      startedAt: DateTime.now(),
      practiceTargets: targets,
    );
    return session;
  }

  static Future<List<ConstructIdentifier>> _fetchVocab() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.vocab)
        .then((map) => map.values.toList());

    // sort by last used descending, nulls first
    constructs.sort((a, b) {
      final dateA = a.lastUsed;
      final dateB = b.lastUsed;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    final Set<String> seemLemmas = {};
    final targets = <ConstructIdentifier>[];
    for (final construct in constructs) {
      if (seemLemmas.contains(construct.lemma)) continue;
      seemLemmas.add(construct.lemma);
      targets.add(construct.id);
      if (targets.length >=
          (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)) {
        break;
      }
    }
    return targets;
  }

  static Future<Map<PangeaToken, MorphFeaturesEnum>> _fetchMorphs() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.morph)
        .then((map) => map.values.toList());

    // sort by last used descending, nulls first
    constructs.sort((a, b) {
      final dateA = a.lastUsed;
      final dateB = b.lastUsed;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    final targets = <PangeaToken, MorphFeaturesEnum>{};
    final Set<String> seenForms = {};

    for (final entry in constructs) {
      if (targets.length >=
          (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)) {
        break;
      }

      final feature = MorphFeaturesEnumExtension.fromString(entry.id.category);
      if (feature == MorphFeaturesEnum.Unknown) {
        continue;
      }

      for (final use in entry.cappedUses) {
        if (targets.length >=
            (AnalyticsPracticeConstants.practiceGroupSize +
                AnalyticsPracticeConstants.errorBufferSize)) {
          break;
        }

        if (use.lemma.isEmpty) continue;
        final form = use.form;
        if (seenForms.contains(form) || form == null) {
          continue;
        }

        seenForms.add(form);
        final token = PangeaToken(
          lemma: Lemma(
            text: form,
            saveVocab: true,
            form: form,
          ),
          text: PangeaTokenText.fromString(form),
          pos: 'other',
          morph: {feature: use.lemma},
        );
        targets[token] = feature;
        break;
      }
    }

    return targets;
  }

  static Future<List<AnalyticsActivityTarget>> _fetchErrors() async {
    final uses = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getUses(count: 100, type: ConstructUseTypeEnum.ga);

    final client = MatrixState.pangeaController.matrixState.client;
    final Map<String, PangeaMessageEvent?> idsToEvents = {};

    for (final use in uses) {
      final eventID = use.metadata.eventId;
      if (eventID == null || idsToEvents.containsKey(eventID)) continue;

      final roomID = use.metadata.roomId;
      if (roomID == null) {
        idsToEvents[eventID] = null;
        continue;
      }

      final room = client.getRoomById(roomID);
      final event = await room?.getEventById(eventID);
      if (event == null || event.redacted) {
        idsToEvents[eventID] = null;
        continue;
      }

      final timeline = await room!.getTimeline();
      idsToEvents[eventID] = PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: event.senderId == client.userID,
      );
    }

    final l2Code =
        MatrixState.pangeaController.userController.userL2!.langCodeShort;

    final events = idsToEvents.values.whereType<PangeaMessageEvent>().toList();
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

    final targets = <AnalyticsActivityTarget>[];
    for (final event in eventsWithContent) {
      final originalSent = event.originalSent!;
      final choreo = originalSent.choreo!;
      final tokens = originalSent.tokens!;

      for (int i = 0; i < choreo.choreoSteps.length; i++) {
        final step = choreo.choreoSteps[i];
        final igcMatch = step.acceptedOrIgnoredMatch;
        if (igcMatch?.isGrammarMatch != true ||
            igcMatch?.match.bestChoice == null) {
          continue;
        }

        final choices = igcMatch!.match.choices!.map((c) => c.value).toList();
        final choiceTokens = tokens
            .where(
              (token) =>
                  token.lemma.saveVocab &&
                  choices.any(
                    (choice) => choice.contains(token.text.content),
                  ),
            )
            .toList();

        // Skip if no valid tokens found for this grammar error
        if (choiceTokens.isEmpty) continue;

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
              morphFeature: null,
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

    return targets;
  }
}
