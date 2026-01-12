import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
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

class VocabPracticeState extends State<VocabPractice> with AnalyticsUpdater {
  SessionLoader sessionLoader = SessionLoader();
  final ValueNotifier<AsyncState<PracticeActivityModel>> activityState =
      ValueNotifier(const AsyncState.idle());

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

  PracticeActivityModel? get _currentActivity =>
      activityState.value is AsyncLoaded<PracticeActivityModel>
          ? (activityState.value as AsyncLoaded<PracticeActivityModel>).value
          : null;

  double get progress =>
      sessionLoader.isLoaded ? sessionLoader.value!.progress : 0.0;

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

  String choiceTargetId(String choiceId) =>
      'vocab-choice-card-${choiceId.replaceAll(' ', '_')}';

  /// Resets all session state without disposing the widget
  void _clearState() {
    activityState.value = const AsyncState.idle();
    setState(() {
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
        activityState.value = AsyncState.error(
          L10n.of(context).oopsSomethingWentWrong,
        );
      }
    }
  }

  Future<void> _startSession() async {
    await _waitForAnalytics();
    await sessionLoader.load();
    await _loadNextActivity();
  }

  Future<void> reloadSession() async {
    _clearState();
    await VocabPracticeSessionRepo.clearSession();
    sessionLoader.dispose();
    sessionLoader = SessionLoader();
    await _startSession();
  }

  Future<void> _completeSession() async {
    if (!sessionLoader.isLoaded) return;
    final bonus = sessionLoader.value!.finishSession();
    await _analyticsService.updateService.addAnalytics(null, bonus);
    await _saveSession();
    setState(() {});
  }

  Future<void> _loadNextActivity() async {
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
        throw L10n.of(context).oopsSomethingWentWrong;
      }

      // Prefetch lemma info for meaning activities before marking ready
      if (result.result != null &&
          result.result!.activityType == ActivityTypeEnum.lemmaMeaning) {
        final choices = result.result!.multipleChoiceContent!.choices.toList();
        await _prefetchLemmaInfo(choices);
      }

      activityState.value = AsyncState.loaded(result.result!);
    } catch (e) {
      activityState.value = AsyncState.error(
        L10n.of(context).oopsSomethingWentWrong,
      );
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
    if (_currentActivity?.multipleChoiceContent == null) return;

    final activity = _currentActivity!.multipleChoiceContent!;
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
    if (_currentActivity == null) return;
    final activity = _currentActivity!;

    activity.onMultipleChoiceSelect(choiceConstruct, choiceContent);
    final correct = activity.multipleChoiceContent!.isCorrect(choiceContent);

    // Submit answer immediately (records use and gives XP)
    final use = sessionLoader.value!.submitAnswer(activity, correct);
    await _analyticsService.updateService
        .addAnalytics(choiceTargetId(choiceContent), [use]);
    await _saveSession();
    if (!correct) return;

    // display the fact that the choice was correct before loading the next activity
    await Future.delayed(const Duration(milliseconds: 1000));

    // Only move to next activity when answer is correct
    sessionLoader.value!.completeActivity(activity);
    await _saveSession();

    isComplete ? await _completeSession() : await _loadNextActivity();
  }

  Future<List<InlineSpan>?> getExampleMessage(
    ConstructIdentifier construct,
  ) async {
    final ConstructUses constructUse =
        await _analyticsService.getConstructUse(construct);

    for (final use in constructUse.cappedUses) {
      final event = await Matrix.of(context).client.getEventByConstructUse(use);
      if (event == null) continue;

      final spans = _buildExampleMessage(use.form, event);
      if (spans != null) return spans;
    }

    return null;
  }

  List<InlineSpan>? _buildExampleMessage(
    String? form,
    PangeaMessageEvent messageEvent,
  ) {
    final tokens = messageEvent.messageDisplayRepresentation?.tokens;
    if (tokens == null || tokens.isEmpty) return null;
    final token = tokens.firstWhereOrNull(
      (token) => token.text.content == form,
    );
    if (token == null) return null;

    final text = messageEvent.messageDisplayText;
    final tokenText = token.text.content;
    int tokenIndex = text.indexOf(tokenText);
    if (tokenIndex == -1) return null;

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

  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData =>
      _analyticsService.derivedData;

  @override
  Widget build(BuildContext context) => VocabPracticeView(this);
}
