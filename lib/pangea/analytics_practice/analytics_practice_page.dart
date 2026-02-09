import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/example_message_util.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_view.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_generation_repo.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_record_controller.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectedMorphChoice {
  final MorphFeaturesEnum feature;
  final String tag;

  const SelectedMorphChoice({
    required this.feature,
    required this.tag,
  });
}

class VocabPracticeChoice {
  final String choiceId;
  final String choiceText;
  final String? choiceEmoji;

  const VocabPracticeChoice({
    required this.choiceId,
    required this.choiceText,
    this.choiceEmoji,
  });
}

class _PracticeQueueEntry {
  final MessageActivityRequest request;
  final Completer<MultipleChoicePracticeActivityModel> completer;

  _PracticeQueueEntry({
    required this.request,
    required this.completer,
  });
}

class SessionLoader extends AsyncLoader<AnalyticsPracticeSessionModel> {
  final ConstructTypeEnum type;
  SessionLoader({required this.type});

  @override
  Future<AnalyticsPracticeSessionModel> fetch() =>
      AnalyticsPracticeSessionRepo.get(type);
}

class AnalyticsPractice extends StatefulWidget {
  static bool bypassExitConfirmation = true;

  final ConstructTypeEnum type;
  const AnalyticsPractice({
    super.key,
    required this.type,
  });

  @override
  AnalyticsPracticeState createState() => AnalyticsPracticeState();
}

class AnalyticsPracticeState extends State<AnalyticsPractice>
    with AnalyticsUpdater {
  late final SessionLoader _sessionLoader;

  final ValueNotifier<AsyncState<MultipleChoicePracticeActivityModel>>
      activityState = ValueNotifier(const AsyncState.idle());

  final Queue<_PracticeQueueEntry> _queue = Queue();

  final ValueNotifier<MessageActivityRequest?> activityTarget =
      ValueNotifier<MessageActivityRequest?>(null);

  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> enableChoicesNotifier = ValueNotifier<bool>(true);

  final ValueNotifier<SelectedMorphChoice?> selectedMorphChoice =
      ValueNotifier<SelectedMorphChoice?>(null);

  final ValueNotifier<bool> hintPressedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> hintsUsedNotifier = ValueNotifier<int>(0);
  static const int maxHints = 5;

  final Map<String, Map<String, String>> _choiceTexts = {};
  final Map<String, Map<String, String?>> _choiceEmojis = {};

  StreamSubscription<void>? _languageStreamSubscription;

  @override
  void initState() {
    super.initState();
    _sessionLoader = SessionLoader(type: widget.type);
    _startSession();
    _languageStreamSubscription = MatrixState
        .pangeaController.userController.languageStream.stream
        .listen((_) => _onLanguageUpdate());
  }

  @override
  void dispose() {
    _languageStreamSubscription?.cancel();
    _sessionLoader.dispose();
    activityState.dispose();
    activityTarget.dispose();
    progressNotifier.dispose();
    enableChoicesNotifier.dispose();
    selectedMorphChoice.dispose();
    hintPressedNotifier.dispose();
    hintsUsedNotifier.dispose();
    super.dispose();
  }

  MultipleChoicePracticeActivityModel? get _currentActivity =>
      activityState.value is AsyncLoaded<MultipleChoicePracticeActivityModel>
          ? (activityState.value
                  as AsyncLoaded<MultipleChoicePracticeActivityModel>)
              .value
          : null;

  bool get _isComplete => _sessionLoader.value?.isComplete ?? false;

  ValueNotifier<AsyncState<AnalyticsPracticeSessionModel>> get sessionState =>
      _sessionLoader.state;

  AnalyticsDataService get _analyticsService =>
      Matrix.of(context).analyticsDataService;

  List<VocabPracticeChoice> filteredChoices(
    MultipleChoicePracticeActivityModel activity,
  ) {
    final content = activity.multipleChoiceContent;
    final choices = content.choices.toList();
    final answer = content.answers.first;
    final filtered = <VocabPracticeChoice>[];

    final seenTexts = <String>{};
    for (final id in choices) {
      final text = getChoiceText(activity.storageKey, id);

      if (seenTexts.contains(text)) {
        if (id != answer) {
          continue;
        }

        final index = filtered.indexWhere(
          (choice) => choice.choiceText == text,
        );
        if (index != -1) {
          filtered[index] = VocabPracticeChoice(
            choiceId: id,
            choiceText: text,
            choiceEmoji: getChoiceEmoji(activity.storageKey, id),
          );
        }
        continue;
      }

      seenTexts.add(text);
      filtered.add(
        VocabPracticeChoice(
          choiceId: id,
          choiceText: text,
          choiceEmoji: getChoiceEmoji(activity.storageKey, id),
        ),
      );
    }

    return filtered;
  }

  String getChoiceText(String key, String choiceId) {
    if (widget.type == ConstructTypeEnum.morph) {
      return choiceId;
    }
    if (_choiceTexts.containsKey(key) &&
        _choiceTexts[key]!.containsKey(choiceId)) {
      return _choiceTexts[key]![choiceId]!;
    }
    final cId = ConstructIdentifier.fromString(choiceId);
    return cId?.lemma ?? choiceId;
  }

  String? getChoiceEmoji(String key, String choiceId) {
    if (widget.type == ConstructTypeEnum.morph) return null;
    return _choiceEmojis[key]?[choiceId];
  }

  String choiceTargetId(String choiceId) =>
      '${widget.type.name}-choice-card-${choiceId.replaceAll(' ', '_')}';

  void _clearState() {
    activityState.value = const AsyncState.loading();
    activityTarget.value = null;
    selectedMorphChoice.value = null;
    hintPressedNotifier.value = false;
    hintsUsedNotifier.value = 0;
    enableChoicesNotifier.value = true;
    progressNotifier.value = 0.0;
    _queue.clear();
    _choiceTexts.clear();
    _choiceEmojis.clear();
    activityState.value = const AsyncState.idle();

    AnalyticsPractice.bypassExitConfirmation = true;
  }

  void updateElapsedTime(int seconds) {
    if (_sessionLoader.isLoaded) {
      _sessionLoader.value!.setElapsedSeconds(seconds);
    }
  }

  void _playAudio() {
    if (activityTarget.value == null) return;
    if (widget.type != ConstructTypeEnum.vocab) return;
    TtsController.tryToSpeak(
      activityTarget.value!.target.tokens.first.vocabConstructID.lemma,
      langCode: MatrixState.pangeaController.userController.userL2!.langCode,
    );
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
    await _sessionLoader.load();
    if (_sessionLoader.isError) {
      AnalyticsPractice.bypassExitConfirmation = true;
      return;
    }

    progressNotifier.value = _sessionLoader.value!.progress;
    await _continueSession();
  }

  Future<void> reloadSession() async {
    _clearState();
    _sessionLoader.reset();
    await _startSession();
  }

  Future<void> reloadCurrentActivity() async {
    if (activityTarget.value == null) return;

    try {
      activityState.value = const AsyncState.loading();
      selectedMorphChoice.value = null;
      hintPressedNotifier.value = false;

      final req = activityTarget.value!;
      final res = await _fetchActivity(req);

      if (!mounted) return;
      activityState.value = AsyncState.loaded(res);
      _playAudio();
    } catch (e) {
      if (!mounted) return;
      activityState.value = AsyncState.error(e);
    }
  }

  Future<void> _completeSession() async {
    _sessionLoader.value!.finishSession();
    setState(() {});

    final bonus = _sessionLoader.value!.state.allBonusUses;
    await _analyticsService.updateService.addAnalytics(
      null,
      bonus,
      forceUpdate: true,
    );
    AnalyticsPractice.bypassExitConfirmation = true;
  }

  bool _continuing = false;

  Future<void> _continueSession() async {
    if (_continuing) return;
    _continuing = true;
    enableChoicesNotifier.value = true;

    try {
      if (activityState.value
          is AsyncIdle<MultipleChoicePracticeActivityModel>) {
        await _initActivityData();
      } else {
        // Keep trying to load activities from the queue until one succeeds or queue is empty
        while (_queue.isNotEmpty) {
          activityState.value = const AsyncState.loading();
          selectedMorphChoice.value = null;
          hintPressedNotifier.value = false;
          final nextActivityCompleter = _queue.removeFirst();

          try {
            final activity = await nextActivityCompleter.completer.future;
            activityTarget.value = nextActivityCompleter.request;
            _playAudio();
            activityState.value = AsyncState.loaded(activity);
            AnalyticsPractice.bypassExitConfirmation = false;
            return;
          } catch (e) {
            // Completer failed, skip to next
            continue;
          }
        }
        // Queue is empty, complete the session
        await _completeSession();
      }
    } catch (e) {
      AnalyticsPractice.bypassExitConfirmation = true;
      activityState.value = AsyncState.error(e);
    } finally {
      _continuing = false;
    }
  }

  Future<void> _initActivityData() async {
    final requests = _sessionLoader.value!.activityRequests;
    if (requests.isEmpty) {
      throw L10n.of(context).noActivityRequest;
    }

    for (var i = 0; i < requests.length; i++) {
      try {
        activityState.value = const AsyncState.loading();
        final req = requests[i];
        final res = await _fetchActivity(req);
        if (!mounted) return;
        activityTarget.value = req;
        _playAudio();
        activityState.value = AsyncState.loaded(res);
        AnalyticsPractice.bypassExitConfirmation = false;
        // Fill queue with remaining requests
        _fillActivityQueue(requests.skip(i + 1).toList());
        return;
      } catch (e) {
        await recordSkippedUse(requests[i]);
        // Try next request
        continue;
      }
    }
    AnalyticsPractice.bypassExitConfirmation = true;
    if (!mounted) return;
    activityState.value =
        AsyncState.error(L10n.of(context).oopsSomethingWentWrong);
    return;
  }

  Future<void> _fillActivityQueue(
    List<MessageActivityRequest> requests,
  ) async {
    for (final request in requests) {
      final completer = Completer<MultipleChoicePracticeActivityModel>();
      _queue.add(
        _PracticeQueueEntry(
          request: request,
          completer: completer,
        ),
      );
      try {
        final res = await _fetchActivity(request);
        if (!mounted) return;
        completer.complete(res);
      } catch (e) {
        if (!mounted) return;
        completer.completeError(e);
        await recordSkippedUse(request);
      }
    }
  }

  Future<MultipleChoicePracticeActivityModel> _fetchActivity(
    MessageActivityRequest req,
  ) async {
    final result = await PracticeRepo.getPracticeActivity(
      req,
      messageInfo: {},
    );

    if (result.isError ||
        result.result is! MultipleChoicePracticeActivityModel) {
      throw L10n.of(context).oopsSomethingWentWrong;
    }

    final activityModel = result.result as MultipleChoicePracticeActivityModel;

    // Prefetch lemma info for meaning activities before marking ready
    if (activityModel is VocabMeaningPracticeActivityModel) {
      final choices = activityModel.multipleChoiceContent.choices.toList();
      await _fetchLemmaInfo(activityModel.storageKey, choices);
    }

    return activityModel;
  }

  Future<void> _fetchLemmaInfo(
    String requestKey,
    List<String> choiceIds,
  ) async {
    final texts = <String, String>{};
    final emojis = <String, String?>{};

    for (final id in choiceIds) {
      final cId = ConstructIdentifier.fromString(id);
      if (cId == null) continue;

      final res = await cId.getLemmaInfo({});
      if (res.isError) {
        LemmaInfoRepo.clearCache(cId.lemmaInfoRequest({}));
        throw L10n.of(context).oopsSomethingWentWrong;
      }

      texts[id] = res.result!.meaning;
      emojis[id] = res.result!.emoji.firstOrNull;
    }

    _choiceTexts.putIfAbsent(requestKey, () => {});
    _choiceEmojis.putIfAbsent(requestKey, () => {});

    _choiceTexts[requestKey]!.addAll(texts);
    _choiceEmojis[requestKey]!.addAll(emojis);
  }

  Future<void> recordSkippedUse(MessageActivityRequest request) async {
    // Record a 0 XP use so that activity isn't chosen again soon
    _sessionLoader.value!.incrementSkippedActivities();
    final token = request.target.tokens.first;

    final use = OneConstructUse(
      useType: ConstructUseTypeEnum.ignPA,
      constructType: widget.type,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.now(),
      ),
      category: token.pos,
      lemma: token.lemma.text,
      form: token.lemma.text,
      xp: 0,
    );

    await _analyticsService.updateService.addAnalytics(null, [use]);
  }

  void onHintPressed() {
    if (hintsUsedNotifier.value >= maxHints) return;
    if (!hintPressedNotifier.value) {
      hintsUsedNotifier.value++;
    }
    hintPressedNotifier.value = true;
  }

  Future<void> onSelectChoice(
    String choiceContent,
  ) async {
    if (_currentActivity == null) return;
    final activity = _currentActivity!;

    // Track the selection for display
    if (activity is MorphPracticeActivityModel) {
      selectedMorphChoice.value = SelectedMorphChoice(
        feature: activity.morphFeature,
        tag: choiceContent,
      );
    }
    final isCorrect = activity.multipleChoiceContent.isCorrect(choiceContent);
    if (isCorrect) {
      enableChoicesNotifier.value = false;
    }

    // Update activity record
    PracticeRecordController.onSelectChoice(
      choiceContent,
      activity.tokens.first,
      activity,
    );

    final use = activity.constructUse(choiceContent);
    _sessionLoader.value!.submitAnswer(use);
    await _analyticsService.updateService
        .addAnalytics(choiceTargetId(choiceContent), [use]);

    if (!activity.multipleChoiceContent.isCorrect(choiceContent)) return;

    _playAudio();

    // Display the fact that the choice was correct before loading the next activity
    await Future.delayed(const Duration(milliseconds: 1000));

    // Then mark this activity as completed, and either load the next or complete the session
    _sessionLoader.value!.completeActivity();
    progressNotifier.value = _sessionLoader.value!.progress;

    if (_queue.isEmpty) {
      await _completeSession();
    } else if (_isComplete) {
      await _completeSession();
    } else {
      await _continueSession();
    }
  }

  Future<List<InlineSpan>?> getExampleMessage(
    MessageActivityRequest activityRequest,
  ) async {
    final target = activityRequest.target;
    final token = target.tokens.first;
    final construct = target.targetTokenConstructID(token);

    if (widget.type == ConstructTypeEnum.morph) {
      return activityRequest.morphExampleInfo?.exampleMessage;
    }

    return ExampleMessageUtil.getExampleMessage(
      await _analyticsService.getConstructUse(construct),
      Matrix.of(context).client,
    );
  }

  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData =>
      _analyticsService.derivedData;

  /// Returns congratulations message based on performance
  String getCompletionMessage(BuildContext context) {
    final accuracy = _sessionLoader.value?.state.accuracy ?? 0;
    final hasTimeBonus = (_sessionLoader.value?.state.elapsedSeconds ?? 0) <=
        AnalyticsPracticeConstants.timeForBonus;
    final hintsUsed = hintsUsedNotifier.value;

    final bool perfectAccuracy = accuracy == 100;
    final bool noHintsUsed = hintsUsed == 0;
    final bool hintsAvailable = widget.type == ConstructTypeEnum.morph;

    //check how many conditions for bonuses the user met and return message accordingly
    final conditionsMet = [
      perfectAccuracy,
      !hintsAvailable || noHintsUsed,
      hasTimeBonus,
    ].where((c) => c).length;

    if (conditionsMet == 3) {
      return L10n.of(context).perfectPractice;
    }
    if (conditionsMet >= 2) {
      return L10n.of(context).greatPractice;
    }
    if (hintsAvailable && noHintsUsed) {
      return L10n.of(context).usedNoHints;
    }
    return L10n.of(context).youveCompletedPractice;
  }

  @override
  Widget build(BuildContext context) => AnalyticsPracticeView(this);
}
