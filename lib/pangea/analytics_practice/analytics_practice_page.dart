import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/example_message_util.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_constants.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_data_service.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_controller.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_ui_controller.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_view.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/pangea/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SelectedMorphChoice {
  final MorphFeaturesEnum feature;
  final String tag;

  const SelectedMorphChoice({required this.feature, required this.tag});
}

class AnalyticsPracticeNotifier extends ChangeNotifier {
  String? _lastSelectedChoice;
  bool showHint = false;
  final Set<String> _clickedChoices = {};

  int correctAnswersSelected(MultipleChoicePracticeExerciseModel? exercise) {
    if (exercise == null) return 0;
    final allAnswers = exercise.multipleChoiceContent.answers;
    return _clickedChoices.where((c) => allAnswers.contains(c)).length;
  }

  bool enableHintPress(
    MultipleChoicePracticeExerciseModel? exercise,
    int hintsUsed,
  ) {
    if (showHint) return false;
    return switch (exercise) {
      VocabAudioPracticeExerciseModel() => true,
      _ => hintsUsed < AnalyticsPracticeConstants.maxHints,
    };
  }

  SelectedMorphChoice? selectedMorphChoice(
    MultipleChoicePracticeExerciseModel? exercise,
  ) {
    if (exercise is! MorphPracticeExerciseModel) return null;
    if (_lastSelectedChoice == null) return null;
    return SelectedMorphChoice(
      feature: exercise.morphFeature,
      tag: _lastSelectedChoice!,
    );
  }

  bool exerciseComplete(MultipleChoicePracticeExerciseModel? exercise) {
    if (exercise == null) return false;
    final allAnswers = exercise.multipleChoiceContent.answers;
    return allAnswers.every((answer) => _clickedChoices.contains(answer));
  }

  bool hasSelectedChoice(String choice) => _clickedChoices.contains(choice);

  void clearExerciseState() {
    _lastSelectedChoice = null;
    _clickedChoices.clear();
    showHint = false;
  }

  void toggleShowHint() {
    showHint = !showHint;
    notifyListeners();
  }

  void selectChoice(String choice) {
    _clickedChoices.add(choice);
    _lastSelectedChoice = choice;
    notifyListeners();
  }
}

typedef ExerciseNotifier =
    ValueNotifier<AsyncState<MultipleChoicePracticeExerciseModel>>;

class AnalyticsPractice extends StatefulWidget {
  static bool bypassExitConfirmation = true;

  final ConstructTypeEnum type;
  const AnalyticsPractice({super.key, required this.type});

  @override
  AnalyticsPracticeState createState() => AnalyticsPracticeState();
}

class AnalyticsPracticeState extends State<AnalyticsPractice>
    with AnalyticsUpdater {
  final PracticeSessionController _sessionController =
      PracticeSessionController();

  final AnalyticsPracticeDataService _dataService =
      AnalyticsPracticeDataService();

  late final AnalyticsPracticeAnalyticsController _analyticsController;
  StreamSubscription<void>? _languageStreamSubscription;

  final ExerciseNotifier practiceExerciseState = ExerciseNotifier(
    const AsyncState.idle(),
  );
  final AnalyticsPracticeNotifier notifier = AnalyticsPracticeNotifier();
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  PracticeTarget? _cachedTarget;
  List<InlineSpan>? _cachedExampleMessage;

  final AudioPlaybackSpeedController audioPlaybackSpeedController =
      AudioPlaybackSpeedController();

  @override
  void initState() {
    super.initState();

    _analyticsController = AnalyticsPracticeAnalyticsController(
      Matrix.of(context).analyticsDataService,
    );

    _addLanguageSubscription();
    startSession();
  }

  @override
  void dispose() {
    _languageStreamSubscription?.cancel();
    notifier.dispose();
    practiceExerciseState.dispose();
    progress.dispose();
    audioPlaybackSpeedController.dispose();
    super.dispose();
  }

  PracticeSessionController get session => _sessionController;
  AnalyticsPracticeDataService get data => _dataService;

  LanguageModel? get _l2 => MatrixState.pangeaController.userController.userL2;

  MultipleChoicePracticeExerciseModel? get practiceExercise {
    final state = practiceExerciseState.value;
    if (state is! AsyncLoaded<MultipleChoicePracticeExerciseModel>) {
      return null;
    }

    return state.value;
  }

  Future<double> get levelProgress =>
      _analyticsController.levelProgress(_l2!.langCodeShort);

  Future<List<InlineSpan>?> get exampleMessage async {
    final exercise = practiceExercise;
    if (exercise == null) return null;

    if (exercise.practiceTarget == _cachedTarget &&
        _cachedExampleMessage != null) {
      return _cachedExampleMessage;
    }

    final List<InlineSpan>? message = switch (exercise) {
      VocabAudioPracticeExerciseModel() =>
        exercise.exampleMessage.exampleMessage,
      MorphCategoryPracticeExerciseModel() =>
        exercise.exampleMessageInfo.exampleMessage,
      _ => await ExampleMessageUtil.getExampleMessage(
        await _analyticsController.getTargetTokenConstruct(
          exercise.practiceTarget,
          _l2!.langCodeShort,
        ),
      ),
    };

    _cachedTarget = exercise.practiceTarget;
    _cachedExampleMessage = message;
    return message;
  }

  bool _autoLaunchNextExercise(MultipleChoicePracticeExerciseModel exercise) =>
      exercise is! VocabAudioPracticeExerciseModel;

  void _clearState() {
    _dataService.clear();
    _sessionController.clear();
    AnalyticsPractice.bypassExitConfirmation = true;
    _clearExerciseState();
  }

  void _clearExerciseState({bool loadingExercise = false}) {
    notifier.clearExerciseState();
    practiceExerciseState.value = loadingExercise
        ? AsyncState.loading()
        : AsyncState.idle();
  }

  void _addLanguageSubscription() {
    _languageStreamSubscription ??= MatrixState
        .pangeaController
        .userController
        .languageStream
        .stream
        .listen((_) => _onLanguageUpdate());
  }

  Future<void> _onLanguageUpdate() async {
    try {
      _clearState();
      await _analyticsController.waitForUpdate();
      await startSession();
    } catch (e) {
      if (mounted) {
        practiceExerciseState.value = AsyncState.error(e);
      }
    }
  }

  void onHintPressed({bool increment = true}) {
    if (increment) _sessionController.updateHintsPressed();
    final currentSpeed = audioPlaybackSpeedController.playbackSpeed.value;
    if (currentSpeed > 0.75 &&
        practiceExercise is VocabAudioPracticeExerciseModel) {
      audioPlaybackSpeedController.setSpeed(0.75);
    }
    notifier.toggleShowHint();
  }

  void _playExerciseAudio(MultipleChoicePracticeExerciseModel exercise) =>
      AnalyticsPracticeUiController.playTargetAudio(
        exercise,
        widget.type,
        _l2!.langCodeShort,
      );

  Future<void> startSession() async {
    _clearState();
    final analyticsService = Matrix.of(context).analyticsDataService;
    if (analyticsService.hasInitError) {
      // Trigger reinit so this retry attempt uses a fresh init. If reinit also
      // fails, initError is set again and waitForAnalytics() below will throw.
      await analyticsService.reinitialize();
    }
    try {
      await _analyticsController.waitForAnalytics();
      await _sessionController.startSession(widget.type);
      if (mounted) setState(() {});

      if (_sessionController.sessionError != null) {
        AnalyticsPractice.bypassExitConfirmation = true;
      } else {
        progress.value = _sessionController.progress;
        await _continueSession();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      _sessionController.sessionError = e;
      AnalyticsPractice.bypassExitConfirmation = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _completeSession() async {
    _sessionController.completeSession();
    progress.value = _sessionController.progress;
    setState(() {});

    final bonus = _sessionController.bonusUses;
    await _analyticsController.addSessionAnalytics(bonus, _l2!.langCodeShort);
    AnalyticsPractice.bypassExitConfirmation = true;
  }

  Future<void> _continueSession() async {
    if (practiceExerciseState.value
        is AsyncLoading<MultipleChoicePracticeExerciseModel>) {
      return;
    }

    if (_sessionController.session?.isComplete == true) {
      await _completeSession();
      return;
    }

    _clearExerciseState(loadingExercise: true);

    try {
      final resp = await _sessionController.getNextExercise(
        skipExercise,
        _dataService.prefetchExerciseInfo,
      );

      if (resp != null) {
        _playExerciseAudio(resp);
        AnalyticsPractice.bypassExitConfirmation = false;
        practiceExerciseState.value = AsyncState.loaded(resp);
      } else {
        await _completeSession();
      }
    } catch (e) {
      AnalyticsPractice.bypassExitConfirmation = true;
      practiceExerciseState.value = AsyncState.error(e);
    }
  }

  Future<void> onSelectChoice(String choiceContent) async {
    final exercise = practiceExercise;
    if (exercise == null) return;

    // Mark this choice as clicked so it can't be clicked again
    if (notifier.hasSelectedChoice(choiceContent)) return;
    notifier.selectChoice(choiceContent);

    final uses = exercise.constructUses(choiceContent);
    _sessionController.submitAnswer(uses);
    await _analyticsController.addCompletedExerciseAnalytics(
      uses,
      AnalyticsPracticeUiController.getChoiceTargetId(
        choiceContent,
        widget.type,
      ),
      _l2!.langCodeShort,
    );

    if (!notifier.exerciseComplete(exercise)) return;

    _playExerciseAudio(exercise);

    if (_autoLaunchNextExercise(exercise)) {
      await Future.delayed(
        const Duration(milliseconds: 1000),
        startNextExercise,
      );
    }
  }

  Future<void> startNextExercise() async {
    _sessionController.completeExercise();
    progress.value = _sessionController.progress;
    await _continueSession();
  }

  Future<void> skipExercise(PracticeTarget target) async {
    // Record a 0 XP use so that exercise isn't chosen again soon
    _sessionController.skipExercise();
    progress.value = _sessionController.progress;

    await _analyticsController.addSkippedExerciseAnalytics(
      target,
      _l2!.langCodeShort,
    );
  }

  Future<void> flagExercise(
    MultipleChoicePracticeExerciseModel exercise,
  ) async {
    final feedback = await showDialog<String?>(
      context: context,
      builder: (context) {
        return FeedbackDialog(
          title: L10n.of(context).feedbackTitle,
          onSubmit: Navigator.of(context).pop,
        );
      },
    );

    if (feedback == null || feedback.isEmpty) return;
    ErrorHandler.logError(
      e: 'Analytics practice exercise flagged',
      data: {'exercise': exercise.toJson(), 'feedback': feedback},
    );

    await skipExercise(exercise.practiceTarget);
    await _continueSession();
  }

  @override
  Widget build(BuildContext context) => AnalyticsPracticeView(this);
}
