import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/example_message_util.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_repo.dart';
import 'package:fluffychat/pangea/morphs/morph_meaning/morph_info_request.dart';
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

    final List<AnalyticsActivityTarget> targets = [];

    if (type == ConstructTypeEnum.vocab) {
      const totalNeeded = AnalyticsPracticeConstants.practiceGroupSize +
          AnalyticsPracticeConstants.errorBufferSize;
      final halfNeeded = (totalNeeded / 2).ceil();

      // Fetch audio constructs (with example messages)
      final audioMap = await _fetchAudio();
      final audioCount = min(audioMap.length, halfNeeded);

      // Fetch vocab constructs to fill the rest
      final vocabNeeded = totalNeeded - audioCount;
      final vocabConstructs = await _fetchVocab();
      final vocabCount = min(vocabConstructs.length, vocabNeeded);

      // Add audio targets - these MUST have example messages
      for (final entry in audioMap.entries.take(audioCount)) {
        targets.add(
          AnalyticsActivityTarget(
            target: PracticeTarget(
              tokens: [entry.key.asToken],
              activityType: ActivityTypeEnum.lemmaAudio,
            ),
            audioExampleMessage: entry.value,
          ),
        );
      }

      // Add vocab meaning targets (no example messages needed)
      for (var i = 0; i < vocabCount; i++) {
        targets.add(
          AnalyticsActivityTarget(
            target: PracticeTarget(
              tokens: [vocabConstructs[i].asToken],
              activityType: ActivityTypeEnum.lemmaMeaning,
            ),
          ),
        );
      }

      // Shuffle to mix audio and vocab
      targets.shuffle();
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
        final morphEntries = morphs.take(remainingCount);

        for (final entry in morphEntries) {
          targets.add(
            AnalyticsActivityTarget(
              target: PracticeTarget(
                tokens: [entry.token],
                activityType: ActivityTypeEnum.grammarCategory,
                morphFeature: entry.feature,
              ),
              exampleMessage: ExampleMessageInfo(
                exampleMessage: entry.exampleMessage,
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

  static Future<Map<ConstructIdentifier, AudioExampleMessage>>
      _fetchAudio() async {
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

    final Set<String> seenLemmas = {};
    final targets = <ConstructIdentifier, AudioExampleMessage>{};

    for (final construct in constructs) {
      if (targets.length >=
          (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)) {
        break;
      }

      if (seenLemmas.contains(construct.lemma)) continue;

      // Try to get an audio example message with token data for this lemma
      final audioExampleMessage =
          await ExampleMessageUtil.getAudioExampleMessage(
        await MatrixState.pangeaController.matrixState.analyticsDataService
            .getConstructUse(construct.id),
        MatrixState.pangeaController.matrixState.client,
      );

      // Only add to targets if we found an example message
      if (audioExampleMessage != null) {
        seenLemmas.add(construct.lemma);
        targets[construct.id] = audioExampleMessage;
      }
    }
    return targets;
  }

  static Future<List<MorphPracticeTarget>> _fetchMorphs() async {
    final constructs = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getAggregatedConstructs(ConstructTypeEnum.morph)
        .then((map) => map.values.toList());

    final morphInfoRequest = MorphInfoRequest(
      userL1: MatrixState.pangeaController.userController.userL1?.langCode ??
          LanguageKeys.defaultLanguage,
      userL2: MatrixState.pangeaController.userController.userL2?.langCode ??
          LanguageKeys.defaultLanguage,
    );

    final morphInfoResult = await MorphInfoRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      morphInfoRequest,
    );

    // Build list of features with multiple tags (valid for practice)
    final List<String> validFeatures = [];
    if (!morphInfoResult.isError) {
      final response = morphInfoResult.asValue?.value;
      if (response != null) {
        for (final feature in response.features) {
          if (feature.tags.length > 1) {
            validFeatures.add(feature.code);
          }
        }
      }
    }

    // sort by last used descending, nulls first
    constructs.sort((a, b) {
      final dateA = a.lastUsed;
      final dateB = b.lastUsed;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1;
      if (dateB == null) return 1;
      return dateA.compareTo(dateB);
    });

    final targets = <MorphPracticeTarget>[];
    final Set<String> seenForms = {};

    for (final entry in constructs) {
      if (targets.length >=
          (AnalyticsPracticeConstants.practiceGroupSize +
              AnalyticsPracticeConstants.errorBufferSize)) {
        break;
      }

      final feature = MorphFeaturesEnumExtension.fromString(entry.id.category);

      // Only include features that are in the valid list (have multiple tags)
      if (feature == MorphFeaturesEnum.Unknown ||
          (validFeatures.isNotEmpty && !validFeatures.contains(feature.name))) {
        continue;
      }

      List<InlineSpan>? exampleMessage;
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

        exampleMessage = await ExampleMessageUtil.getExampleMessage(
          await MatrixState.pangeaController.matrixState.analyticsDataService
              .getConstructUse(entry.id),
          MatrixState.pangeaController.matrixState.client,
          form: form,
        );

        if (exampleMessage == null) {
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
        targets.add(
          MorphPracticeTarget(
            feature: feature,
            token: token,
            exampleMessage: exampleMessage,
          ),
        );
        break;
      }
    }

    return targets;
  }

  static Future<List<AnalyticsActivityTarget>> _fetchErrors() async {
    // Fetch all recent uses in one call (not filtering blocked constructs)
    final allRecentUses = await MatrixState
        .pangeaController.matrixState.analyticsDataService
        .getUses(count: 200, filterCapped: false);

    // Filter for grammar error uses
    final grammarErrorUses = allRecentUses
        .where((use) => use.useType == ConstructUseTypeEnum.ga)
        .toList();

    // Create list of recently used constructs
    final cutoffTime = DateTime.now().subtract(const Duration(hours: 24));
    final recentlyPracticedConstructs = allRecentUses
        .where(
          (use) =>
              use.metadata.timeStamp.isAfter(cutoffTime) &&
              (use.useType == ConstructUseTypeEnum.corGE ||
                  use.useType == ConstructUseTypeEnum.incGE),
        )
        .map((use) => use.identifier)
        .toSet();

    final client = MatrixState.pangeaController.matrixState.client;
    final Map<String, PangeaMessageEvent?> idsToEvents = {};

    for (final use in grammarErrorUses) {
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
        if (choiceTokens.length <= 1) {
          continue;
        }

        final firstToken = choiceTokens.first;
        final tokenIdentifier = ConstructIdentifier(
          lemma: firstToken.lemma.text,
          type: ConstructTypeEnum.vocab,
          category: firstToken.pos,
        );

        final hasRecentPractice =
            recentlyPracticedConstructs.contains(tokenIdentifier);

        if (hasRecentPractice) continue;

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

class MorphPracticeTarget {
  final PangeaToken token;
  final MorphFeaturesEnum feature;
  final List<InlineSpan> exampleMessage;

  MorphPracticeTarget({
    required this.token,
    required this.feature,
    required this.exampleMessage,
  });
}
