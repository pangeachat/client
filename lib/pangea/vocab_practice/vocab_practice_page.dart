import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
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
  bool isAwaitingNextActivity = false;
  String? activityError;

  bool isLoadingLemmaInfo = false;
  final Map<String, String> _choiceTexts = {};
  final Map<String, String?> _choiceEmojis = {};

  StreamSubscription<void>? _languageStreamSubscription;
  bool _sessionClearedDueToLanguageChange = false;

  @override
  void initState() {
    super.initState();
    _startSession();
    _listenToLanguageChanges();
  }

  @override
  void dispose() {
    _languageStreamSubscription?.cancel();
    if (isComplete) {
      VocabPracticeSessionRepo.clearSession();
    } else if (!_sessionClearedDueToLanguageChange) {
      //don't save if session was cleared due to language change
      _saveCurrentTime();
    }
    sessionLoader.dispose();
    super.dispose();
  }

  void _saveCurrentTime() {
    if (sessionLoader.isLoaded) {
      VocabPracticeSessionRepo.updateSession(sessionLoader.value!);
    }
  }

  /// Resets all session state without disposing the widget
  void _resetState() {
    currentActivity = null;
    isLoadingActivity = true;
    isAwaitingNextActivity = false;
    activityError = null;
    isLoadingLemmaInfo = false;
    _choiceTexts.clear();
    _choiceEmojis.clear();
  }

  bool get isComplete =>
      sessionLoader.isLoaded && sessionLoader.value!.hasCompletedCurrentGroup;

  double get progress =>
      sessionLoader.isLoaded ? sessionLoader.value!.progress : 0.0;

  int get availableActivities => sessionLoader.isLoaded
      ? sessionLoader.value!.currentAvailableActivities
      : 0;

  int get completedActivities =>
      sessionLoader.isLoaded ? sessionLoader.value!.currentIndex : 0;

  int get elapsedSeconds =>
      sessionLoader.isLoaded ? sessionLoader.value!.elapsedSeconds : 0;

  void updateElapsedTime(int seconds) {
    if (sessionLoader.isLoaded) {
      sessionLoader.value!.elapsedSeconds = seconds;
    }
  }

  Future<void> _waitForAnalytics() async {
    if (!MatrixState.pangeaController.matrixState.analyticsDataService
        .initCompleter.isCompleted) {
      MatrixState.pangeaController.initControllers();
      await MatrixState.pangeaController.matrixState.analyticsDataService
          .initCompleter.future;
    }
  }

  void _listenToLanguageChanges() {
    _languageStreamSubscription = MatrixState
        .pangeaController.userController.languageStream.stream
        .listen((_) async {
      // If language changed, clear session and back out of vocab practice
      if (await _shouldReloadSession()) {
        _sessionClearedDueToLanguageChange = true;
        await VocabPracticeSessionRepo.clearSession();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  Future<void> _startSession() async {
    await _waitForAnalytics();
    await sessionLoader.load();

    // If user languages have changed since last session, clear session
    if (await _shouldReloadSession()) {
      await VocabPracticeSessionRepo.clearSession();
      sessionLoader.dispose();
      sessionLoader = SessionLoader();
      await sessionLoader.load();
    }

    loadActivity();
  }

  // check if current l1 and l2 have changed from those of the loaded session
  Future<bool> _shouldReloadSession() async {
    if (!sessionLoader.isLoaded) return false;

    final session = sessionLoader.value!;
    final currentL1 =
        MatrixState.pangeaController.userController.userL1?.langCode;
    final currentL2 =
        MatrixState.pangeaController.userController.userL2?.langCode;

    if (session.userL1 != currentL1 || session.userL2 != currentL2) {
      return true;
    }
    return false;
  }

  Future<void> completeActivitySession() async {
    if (!sessionLoader.isLoaded) return;

    _saveCurrentTime();
    sessionLoader.value!.finishSession();
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    setState(() {});
  }

  Future<void> reloadSession() async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Clear current session storage, dispose old session loader, and clear state variables
        await VocabPracticeSessionRepo.clearSession();
        sessionLoader.dispose();
        sessionLoader = SessionLoader();
        _resetState();
        await _startSession();
      },
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<List<InlineSpan>?> getExampleMessage(
    ConstructIdentifier construct,
  ) async {
    final ConstructUses constructUse = await Matrix.of(context)
        .analyticsDataService
        .getConstructUse(construct);
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

  Future<void> loadActivity() async {
    if (!sessionLoader.isLoaded) {
      try {
        await sessionLoader.completer.future;
      } catch (_) {
        return;
      }
    }

    if (!mounted) return;

    setState(() {
      isAwaitingNextActivity = false;
      currentActivity = null;
      isLoadingActivity = true;
      activityError = null;
      _choiceTexts.clear();
      _choiceEmojis.clear();
    });

    final session = sessionLoader.value!;
    final activityRequest = session.currentActivityRequest;
    if (activityRequest == null) {
      setState(() {
        activityError = L10n.of(context).noActivityRequest;
        isLoadingActivity = false;
      });
      return;
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
      final choices = currentActivity!.multipleChoiceContent!.choices.toList();
      await _prefetchLemmaInfo(choices);
    }

    if (mounted) {
      setState(() => isLoadingActivity = false);
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
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    final transformTargetId =
        'vocab-choice-card-${choiceContent.replaceAll(' ', '_')}';
    if (correct) {
      OverlayUtil.showPointsGained(transformTargetId, 5, context);
    } else {
      OverlayUtil.showPointsGained(transformTargetId, -1, context);
    }
    if (!correct) return;

    // display the fact that the choice was correct before loading the next activity
    setState(() => isAwaitingNextActivity = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    setState(() => isAwaitingNextActivity = false);

    // Only move to next activity when answer is correct
    sessionLoader.value!.completeActivity(activity);
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    if (isComplete) {
      await completeActivitySession();
    }

    await loadActivity();
  }

  Future<Map<String, double>> calculateProgressChange(int xpGained) async {
    final derivedData = await MatrixState
        .pangeaController.matrixState.analyticsDataService.derivedData;
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

  String getChoiceText(String choiceId) {
    if (_choiceTexts.containsKey(choiceId)) return _choiceTexts[choiceId]!;
    final cId = ConstructIdentifier.fromString(choiceId);
    return cId?.lemma ?? choiceId;
  }

  String? getChoiceEmoji(String choiceId) => _choiceEmojis[choiceId];

  //fetches display info for all choices from constructIDs
  Future<void> _prefetchLemmaInfo(List<String> choiceIds) async {
    if (!mounted) return;
    setState(() => isLoadingLemmaInfo = true);

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

        if (mounted) {
          setState(() {
            activityError = L10n.of(context).oopsSomethingWentWrong;
            isLoadingLemmaInfo = false;
          });
        }
        return;
      }
      // Update choice texts/emojis if successful
      if (res != null && !res.isError) {
        final id = choiceIds[i];
        final info = res.result!;
        _choiceTexts[id] = info.meaning;
        _choiceEmojis[id] = _choiceEmojis[id] ?? info.emoji.firstOrNull;
      }
    }

    if (mounted) {
      setState(() => isLoadingLemmaInfo = false);
    }
  }
}
