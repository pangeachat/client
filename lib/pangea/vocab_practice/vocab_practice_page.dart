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
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_generation_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_repo.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_view.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SessionLoader extends AsyncLoader<VocabPracticeSessionModel> {
  @override
  Future<VocabPracticeSessionModel> fetch() => VocabPracticeSessionRepo.get();
}

class VocabPractice extends StatefulWidget {
  const VocabPractice({super.key});

  @override
  VocabPracticeState createState() => VocabPracticeState();
}

class VocabPracticeState extends State<VocabPractice> with AnalyticsUpdater {
  final SessionLoader _sessionLoader = SessionLoader();

  final ValueNotifier<AsyncState<PracticeActivityModel>> activityState =
      ValueNotifier(const AsyncState.idle());

  final Queue<MapEntry<ConstructIdentifier, Completer<PracticeActivityModel>>>
      _queue = Queue();

  final ValueNotifier<ConstructIdentifier?> activityConstructId =
      ValueNotifier<ConstructIdentifier?>(null);

  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);

  final Map<PracticeTarget, Map<String, String>> _choiceTexts = {};
  final Map<PracticeTarget, Map<String, String?>> _choiceEmojis = {};

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
    if (_isComplete) {
      VocabPracticeSessionRepo.clear();
    } else {
      _saveSession();
    }
    _sessionLoader.dispose();
    activityState.dispose();
    activityConstructId.dispose();
    progressNotifier.dispose();
    super.dispose();
  }

  PracticeActivityModel? get _currentActivity =>
      activityState.value is AsyncLoaded<PracticeActivityModel>
          ? (activityState.value as AsyncLoaded<PracticeActivityModel>).value
          : null;

  bool get _isComplete => _sessionLoader.value?.isComplete ?? false;

  ValueNotifier<AsyncState<VocabPracticeSessionModel>> get sessionState =>
      _sessionLoader.state;

  AnalyticsDataService get _analyticsService =>
      Matrix.of(context).analyticsDataService;

  String getChoiceText(PracticeTarget target, String choiceId) {
    if (_choiceTexts.containsKey(target) &&
        _choiceTexts[target]!.containsKey(choiceId)) {
      return _choiceTexts[target]![choiceId]!;
    }
    final cId = ConstructIdentifier.fromString(choiceId);
    return cId?.lemma ?? choiceId;
  }

  String? getChoiceEmoji(PracticeTarget target, String choiceId) =>
      _choiceEmojis[target]?[choiceId];

  String choiceTargetId(String choiceId) =>
      'vocab-choice-card-${choiceId.replaceAll(' ', '_')}';

  void _resetActivityState() {
    activityState.value = const AsyncState.loading();
    activityConstructId.value = null;
  }

  void _resetSessionState() {
    progressNotifier.value = 0.0;
    _queue.clear();
    _choiceTexts.clear();
    _choiceEmojis.clear();
    activityState.value = const AsyncState.idle();
  }

  void updateElapsedTime(int seconds) {
    if (_sessionLoader.isLoaded) {
      _sessionLoader.value!.setElapsedSeconds(seconds);
    }
  }

  Future<void> _saveSession() async {
    if (_sessionLoader.isLoaded) {
      await VocabPracticeSessionRepo.update(_sessionLoader.value!);
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
      _resetActivityState();
      _resetSessionState();
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
    progressNotifier.value = _sessionLoader.value!.progress;
    await _continueSession();
  }

  Future<void> reloadSession() async {
    _resetActivityState();
    _resetSessionState();
    await VocabPracticeSessionRepo.clear();
    _sessionLoader.reset();
    await _startSession();
  }

  Future<void> _completeSession() async {
    _sessionLoader.value!.finishSession();
    setState(() {});

    final bonus = _sessionLoader.value!.state.allBonusUses;
    await _analyticsService.updateService.addAnalytics(null, bonus);
    await _saveSession();
  }

  bool _continuing = false;

  Future<void> _continueSession() async {
    if (_continuing) return;
    _continuing = true;

    try {
      if (activityState.value is AsyncIdle<PracticeActivityModel>) {
        await _initActivityData();
      } else if (_queue.isEmpty) {
        await _completeSession();
      } else {
        activityState.value = const AsyncState.loading();
        final nextActivityCompleter = _queue.removeFirst();
        activityConstructId.value = nextActivityCompleter.key;
        final activity = await nextActivityCompleter.value.future;
        // activity = _removeDuplicateChoices(activity);
        activityState.value = AsyncState.loaded(activity);
      }
    } catch (e) {
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

    try {
      activityState.value = const AsyncState.loading();

      final req = requests.first;
      final res = await _fetchActivity(req);
      if (!mounted) return;

      activityConstructId.value = req.targetTokens.first.vocabConstructID;
      activityState.value = AsyncState.loaded(res);
    } catch (e) {
      if (!mounted) return;
      activityState.value = AsyncState.error(e);
      return;
    }

    _fillActivityQueue(requests.skip(1).toList());
  }

  Future<void> _fillActivityQueue(List<MessageActivityRequest> requests) async {
    for (final request in requests) {
      final completer = Completer<PracticeActivityModel>();
      _queue.add(
        MapEntry(
          request.targetTokens.first.vocabConstructID,
          completer,
        ),
      );
      try {
        final res = await _fetchActivity(request);
        if (!mounted) return;
        completer.complete(res);
      } catch (e) {
        if (!mounted) return;
        completer.completeError(e);
        break;
      }
    }
  }

  Future<PracticeActivityModel> _fetchActivity(
    MessageActivityRequest req,
  ) async {
    final result = await PracticeRepo.getPracticeActivity(
      req,
      messageInfo: {},
    );
    if (result.isError) {
      throw L10n.of(context).oopsSomethingWentWrong;
    }

    // Prefetch lemma info for meaning activities before marking ready
    if (result.result!.activityType == ActivityTypeEnum.lemmaMeaning) {
      final choices = result.result!.multipleChoiceContent!.choices.toList();
      await _fetchLemmaInfo(result.result!.practiceTarget, choices);
    }

    return result.result!;
  }

  Future<void> _fetchLemmaInfo(
    PracticeTarget target,
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

    _choiceTexts.putIfAbsent(target, () => {});
    _choiceEmojis.putIfAbsent(target, () => {});

    _choiceTexts[target]!.addAll(texts);
    _choiceEmojis[target]!.addAll(emojis);
    // _removeDuplicateChoices();
  }

  // /// Removes duplicate choice texts, keeping the correct answer if it's a duplicate, or the first otherwise
  // PracticeActivityModel _removeDuplicateChoices(
  //   PracticeActivityModel activity,
  // ) {
  //   if (activity.multipleChoiceContent == null) return activity;
  //   final choices = activity.multipleChoiceContent!.choices;
  //   final choiceTexts = _choiceTexts[activity.practiceTarget];
  //   if (choiceTexts == null) return activity;

  //   final Map<String, String> definitionToChoice = {};
  //   for (final id in choices) {
  //     final text = choiceTexts[id];
  //     if (text == null) continue;
  //     definitionToChoice[text] = id;
  //   }

  //   final uniqueDefinitions = definitionToChoice.keys.toSet();
  //   final uniqueChoices = uniqueDefinitions
  //       .map((def) => definitionToChoice[def]!)
  //       .toSet()
  //       .toList();

  //   if (uniqueChoices.length == choices.length) {
  //     return activity;
  //   }

  //   activity.multipleChoiceContent!.choices.clear();
  //   activity.multipleChoiceContent!.choices.addAll(uniqueChoices);
  //   return activity;
  // }

  Future<void> onSelectChoice(
    ConstructIdentifier choiceConstruct,
    String choiceContent,
  ) async {
    if (_currentActivity == null) return;
    final activity = _currentActivity!;

    // Update activity record
    activity.onMultipleChoiceSelect(choiceConstruct, choiceContent);
    final correct = activity.multipleChoiceContent!.isCorrect(choiceContent);

    // Update session model and analytics
    final useType = correct
        ? activity.activityType.correctUse
        : activity.activityType.incorrectUse;

    final use = OneConstructUse(
      useType: useType,
      constructType: ConstructTypeEnum.vocab,
      metadata: ConstructUseMetaData(
        roomId: null,
        timeStamp: DateTime.now(),
      ),
      category: activity.targetTokens.first.pos,
      lemma: activity.targetTokens.first.lemma.text,
      form: activity.targetTokens.first.lemma.text,
      xp: useType.pointValue,
    );

    _sessionLoader.value!.submitAnswer(use);
    await _analyticsService.updateService
        .addAnalytics(choiceTargetId(choiceContent), [use]);

    await _saveSession();
    if (!correct) return;

    // Display the fact that the choice was correct before loading the next activity
    await Future.delayed(const Duration(milliseconds: 1000));

    // Then mark this activity as completed, and either load the next or complete the session
    _sessionLoader.value!.completeActivity();
    progressNotifier.value = _sessionLoader.value!.progress;
    await _saveSession();

    _isComplete ? await _completeSession() : await _continueSession();
  }

  Future<List<InlineSpan>?> getExampleMessage(
    ConstructIdentifier construct,
  ) async {
    return ExampleMessageUtil.getExampleMessage(
      await _analyticsService.getConstructUse(construct),
      Matrix.of(context).client,
    );
  }

  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData =>
      _analyticsService.derivedData;

  @override
  Widget build(BuildContext context) => VocabPracticeView(this);
}
