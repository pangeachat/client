import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_generation_repo.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_repo.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_view.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SessionLoader extends AsyncLoader<VocabPracticeSessionModel> {
  @override
  Future<VocabPracticeSessionModel> fetch() =>
      VocabPracticeSessionRepo.currentSession;
}

class VocabPractice extends StatefulWidget {
  const VocabPractice({super.key});

  @override
  VocabPracticeState createState() => VocabPracticeState();
}

class VocabPracticeState extends State<VocabPractice> {
  SessionLoader sessionLoader = SessionLoader();
  PracticeActivityModel? currentActivity;
  bool isLoadingActivity = true;
  String? activityError;

  final Map<String, String> _choiceTexts = {};
  final Map<String, String?> _choiceEmojis = {};

  StreamSubscription<void>? _languageStreamSubscription;

  @override
  void initState() {
    super.initState();
    _startSession();
    _languageStreamSubscription = MatrixState
        .pangeaController.userController.languageStream.stream
        .listen((_) => _onLanguageUpdate());
  }

  @override
  void dispose() {
    _languageStreamSubscription?.cancel();
    if (isComplete) {
      VocabPracticeSessionRepo.clearSession();
    } else {
      _saveSession();
    }
    sessionLoader.dispose();
    super.dispose();
  }

  double get progress =>
      sessionLoader.isLoaded ? sessionLoader.value!.progress : 0.0;

  int get availableActivities => sessionLoader.isLoaded
      ? sessionLoader.value!.currentAvailableActivities
      : 0;

  int get completedActivities =>
      sessionLoader.isLoaded ? sessionLoader.value!.currentIndex : 0;

  int get elapsedSeconds =>
      sessionLoader.isLoaded ? sessionLoader.value!.elapsedSeconds : 0;

  bool get isComplete =>
      sessionLoader.isLoaded && sessionLoader.value!.hasCompletedCurrentGroup;

  AnalyticsDataService get _analyticsService =>
      Matrix.of(context).analyticsDataService;

  String getChoiceText(String choiceId) {
    if (_choiceTexts.containsKey(choiceId)) return _choiceTexts[choiceId]!;
    final cId = ConstructIdentifier.fromString(choiceId);
    return cId?.lemma ?? choiceId;
  }

  String? getChoiceEmoji(String choiceId) => _choiceEmojis[choiceId];

  /// Resets all session state without disposing the widget
  void _clearState() {
    setState(() {
      currentActivity = null;
      isLoadingActivity = true;
      activityError = null;
      _choiceTexts.clear();
      _choiceEmojis.clear();
    });
  }

  void updateElapsedTime(int seconds) {
    if (sessionLoader.isLoaded) {
      sessionLoader.value!.elapsedSeconds = seconds;
    }
  }

  Future<void> _saveSession() async {
    if (sessionLoader.isLoaded) {
      await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);
    }
  }

  Future<void> _waitForAnalytics() async {
    if (!_analyticsService.initCompleter.isCompleted) {
      MatrixState.pangeaController.initControllers();
      await _analyticsService.initCompleter.future;
    }
  }

  Future<void> _onLanguageUpdate() async {
    try {
      _clearState();
      await _analyticsService
          .updateDispatcher.constructUpdateStream.stream.first
          .timeout(const Duration(seconds: 10));
      await reloadSession();
    } catch (e) {
      if (mounted) {
        setState(
          () => activityError = L10n.of(context).oopsSomethingWentWrong,
        );
      }
    }
  }

  Future<void> _startSession() async {
    await _waitForAnalytics();
    await sessionLoader.load();
    await loadNextActivity();
  }

  Future<void> reloadSession() async {
    _clearState();
    await VocabPracticeSessionRepo.clearSession();
    sessionLoader.dispose();
    sessionLoader = SessionLoader();
    await _startSession();
  }

  Future<void> completeSession() async {
    if (!sessionLoader.isLoaded) return;
    sessionLoader.value!.finishSession();
    await _saveSession();
    setState(() {});
  }

  Future<void> loadNextActivity() async {
    if (!sessionLoader.isLoaded) {
      try {
        await sessionLoader.completer.future;
      } catch (_) {
        return;
      }
    }

    if (!mounted) return;

    try {
      _clearState();

      final session = sessionLoader.value!;
      final activityRequest = session.currentActivityRequest;
      if (activityRequest == null) {
        throw L10n.of(context).noActivityRequest;
      }

      final result = await PracticeRepo.getPracticeActivity(
        activityRequest,
        messageInfo: {},
      );
      if (result.isError) {
        activityError = L10n.of(context).oopsSomethingWentWrong;
      } else {
        currentActivity = result.result!;
      }

      // Prefetch lemma info for meaning activities before marking ready
      if (currentActivity != null &&
          currentActivity!.activityType == ActivityTypeEnum.lemmaMeaning) {
        final choices =
            currentActivity!.multipleChoiceContent!.choices.toList();
        await _prefetchLemmaInfo(choices);
      }
    } catch (e) {
      activityError = L10n.of(context).oopsSomethingWentWrong;
    } finally {
      if (mounted) {
        setState(() => isLoadingActivity = false);
      }
    }
  }

  //fetches display info for all choices from constructIDs
  Future<void> _prefetchLemmaInfo(List<String> choiceIds) async {
    final results = await Future.wait(
      choiceIds.map((id) async {
        final cId = ConstructIdentifier.fromString(id);
        if (cId == null) {
          return null;
        }
        try {
          final result = await cId.getLemmaInfo({});
          return result;
        } catch (e) {
          return null;
        }
      }),
    );

    // Check if any result is an error
    for (int i = 0; i < results.length; i++) {
      final res = results[i];
      if (res != null && res.isError) {
        // Clear cache for failed items so retry will fetch fresh
        final failedId = choiceIds[i];
        final cId = ConstructIdentifier.fromString(failedId);
        if (cId != null) {
          LemmaInfoRepo.clearCache(cId.lemmaInfoRequest({}));
        }

        throw L10n.of(context).oopsSomethingWentWrong;
      }
      // Update choice texts/emojis if successful
      if (res != null && !res.isError) {
        final id = choiceIds[i];
        final info = res.result!;
        _choiceTexts[id] = info.meaning;
        _choiceEmojis[id] = _choiceEmojis[id] ?? info.emoji.firstOrNull;
      }
    }

    // Check for duplicate choice texts and remove duplicates
    _removeDuplicateChoices();
  }

  /// Removes duplicate choice texts, keeping the correct answer if it's a duplicate, or the first otherwise
  void _removeDuplicateChoices() {
    if (currentActivity?.multipleChoiceContent == null) return;

    final activity = currentActivity!.multipleChoiceContent!;
    final correctAnswers = activity.answers;

    final Map<String, List<String>> textToIds = {};

    for (final id in _choiceTexts.keys) {
      final text = _choiceTexts[id]!;
      textToIds.putIfAbsent(text, () => []).add(id);
    }

    // Find duplicates and remove them
    final Set<String> idsToRemove = {};
    for (final entry in textToIds.entries) {
      final duplicateIds = entry.value;
      if (duplicateIds.length > 1) {
        // Find if any of the duplicates is the correct answer
        final correctId = duplicateIds.firstWhereOrNull(
          (id) => correctAnswers.contains(id),
        );

        // Remove all duplicates except one
        if (correctId != null) {
          idsToRemove.addAll(duplicateIds.where((id) => id != correctId));
        } else {
          idsToRemove.addAll(duplicateIds.skip(1));
        }
      }
    }

    if (idsToRemove.isNotEmpty) {
      activity.choices.removeAll(idsToRemove);
      for (final id in idsToRemove) {
        _choiceTexts.remove(id);
        _choiceEmojis.remove(id);
      }
    }
  }

  Future<void> onSelectChoice(
    ConstructIdentifier choiceConstruct,
    String choiceContent,
  ) async {
    if (currentActivity == null) return;
    final activity = currentActivity!;

    activity.onMultipleChoiceSelect(choiceConstruct, choiceContent);
    final correct = activity.multipleChoiceContent!.isCorrect(choiceContent);

    // Submit answer immediately (records use and gives XP)
    sessionLoader.value!.submitAnswer(activity, correct);
    await _saveSession();

    final transformTargetId =
        'vocab-choice-card-${choiceContent.replaceAll(' ', '_')}';
    if (correct) {
      OverlayUtil.showPointsGained(transformTargetId, 5, context);
    } else {
      OverlayUtil.showPointsGained(transformTargetId, -1, context);
    }
    if (!correct) return;

    // display the fact that the choice was correct before loading the next activity
    await Future.delayed(const Duration(milliseconds: 1000));

    // Only move to next activity when answer is correct
    sessionLoader.value!.completeActivity(activity);
    await _saveSession();

    if (isComplete) {
      await completeSession();
    }

    await loadNextActivity();
  }

  Future<List<InlineSpan>?> getExampleMessage(
    ConstructIdentifier construct,
  ) async {
    final ConstructUses constructUse =
        await _analyticsService.getConstructUse(construct);
    for (final use in constructUse.cappedUses) {
      if (use.metadata.eventId == null || use.metadata.roomId == null) {
        continue;
      }

      final room = MatrixState.pangeaController.matrixState.client
          .getRoomById(use.metadata.roomId!);
      if (room == null) continue;

      final event = await room.getEventById(use.metadata.eventId!);
      if (event == null) continue;

      final timeline = await room.getTimeline();
      final pangeaMessageEvent = PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: event.senderId ==
            MatrixState.pangeaController.matrixState.client.userID,
      );

      final tokens = pangeaMessageEvent.messageDisplayRepresentation?.tokens;
      if (tokens == null || tokens.isEmpty) continue;
      final token = tokens.firstWhereOrNull(
        (token) => token.text.content == use.form,
      );
      if (token == null) continue;

      final text = pangeaMessageEvent.messageDisplayText;
      final tokenText = token.text.content;
      int tokenIndex = text.indexOf(tokenText);
      if (tokenIndex == -1) continue;

      final beforeSubstring = text.substring(0, tokenIndex);
      if (beforeSubstring.length != beforeSubstring.characters.length) {
        tokenIndex = beforeSubstring.characters.length;
      }

      final int tokenLength = tokenText.characters.length;
      final before = text.characters.take(tokenIndex).toString();
      final after = text.characters.skip(tokenIndex + tokenLength).toString();
      return [
        TextSpan(text: before),
        TextSpan(
          text: tokenText,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        TextSpan(text: after),
      ];
    }

    return null;
  }

  Future<Map<String, double>> calculateProgressChange(int xpGained) async {
    final derivedData = await _analyticsService.derivedData;
    final currentLevel = derivedData.level;
    final currentXP = derivedData.totalXP;

    final minXPForCurrentLevel =
        DerivedAnalyticsDataModel.calculateXpWithLevel(currentLevel);
    final minXPForNextLevel = derivedData.minXPForNextLevel;

    final xpRange = minXPForNextLevel - minXPForCurrentLevel;

    final progressBefore =
        ((currentXP - minXPForCurrentLevel) / xpRange).clamp(0.0, 1.0);

    final newTotalXP = currentXP + xpGained;
    final progressAfter =
        ((newTotalXP - minXPForCurrentLevel) / xpRange).clamp(0.0, 1.0);

    return {
      'before': progressBefore,
      'after': progressAfter,
    };
  }

  @override
  Widget build(BuildContext context) => VocabPracticeView(this);
}
