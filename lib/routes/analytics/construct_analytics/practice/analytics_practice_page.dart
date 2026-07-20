import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_analytics_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_data_service.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_notifier.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/star_rain_widget.dart';

class AnalyticsPractice extends StatefulWidget {
  final ConstructTypeEnum type;

  /// The panel's leading close control — leaving is silent and keeps the
  /// session alive in the [PracticeSessionHolder]; only the explicit End
  /// control discards it. See routing.instructions.md § Practice is a
  /// persistent background session.
  final IconData closeIcon;
  final String closeTooltip;
  final VoidCallback close;

  const AnalyticsPractice({
    super.key,
    required this.type,
    required this.closeIcon,
    required this.closeTooltip,
    required this.close,
  });

  @override
  AnalyticsPracticeState createState() => AnalyticsPracticeState();
}

class AnalyticsPracticeState extends State<AnalyticsPractice>
    with AnalyticsUpdater {
  /// Session state lives in the holder, not this State, so it survives the
  /// panel closing and re-attaches on reopen.
  late final PracticeSessionState _holderState;

  late final AnalyticsPracticeAnalyticsController _analyticsController;
  StreamSubscription<void>? _languageStreamSubscription;

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

    _holderState = PracticeSessionHolder.instance.claim(widget.type);
    PracticeSessionHolder.instance.attachPanel();

    _addLanguageSubscription();
    _resumeOrStart();
  }

  @override
  void dispose() {
    PracticeSessionHolder.instance.detachPanel();
    _languageStreamSubscription?.cancel();
    audioPlaybackSpeedController.dispose();
    // Session notifiers are holder-owned and intentionally NOT disposed here —
    // the session outlives this panel.
    super.dispose();
  }

  PracticeSessionController get session => _holderState.sessionController;
  AnalyticsPracticeDataService get data => _holderState.dataService;
  ExerciseNotifier get practiceExerciseState =>
      _holderState.practiceExerciseState;
  AnalyticsPracticeNotifier get notifier => _holderState.notifier;
  ValueNotifier<double> get progress => _holderState.progress;

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

  /// Attach to the held session: start it fresh if it hasn't been started, or
  /// pick it up wherever it is — an exercise already on screen renders as-is,
  /// and a load left in flight by a closed panel re-renders through
  /// [practiceExerciseState] when it lands.
  void _resumeOrStart() {
    if (session.session == null &&
        session.sessionError == null &&
        !session.isLoadingSession) {
      startSession();
    }
  }

  void _clearState() {
    MatrixState.pAnyState.closeOverlay(StarRainWidget.practiceCompleteKey);
    data.clear();
    session.clear();
    _clearExerciseState();
    if (mounted) setState(() {});
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
    if (increment) session.updateHintsPressed();
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

    // if starting one round after another, hide the confetti from the previous round
    MatrixState.pAnyState.closeOverlay(StarRainWidget.practiceCompleteKey);

    final analyticsService = Matrix.of(context).analyticsDataService;
    if (analyticsService.hasInitError) {
      // Trigger reinit so this retry attempt uses a fresh init. If reinit also
      // fails, initError is set again and waitForAnalytics() below will throw.
      await analyticsService.reinitialize();
    }
    try {
      await _analyticsController.waitForAnalytics(
        Matrix.of(context).client.userID,
      );
      await session.startSession(widget.type);
      if (mounted) setState(() {});

      if (session.sessionError != null) {
        // Signal through the notifier too, so a panel reopened over this
        // session (and the cluster badge) rebuild without this State's
        // setState.
        practiceExerciseState.value = AsyncState.error(session.sessionError!);
        PracticeSessionHolder.instance.bump();
      } else {
        PracticeSessionHolder.instance.bump();
        progress.value = session.progress;
        await _continueSession();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      session.sessionError = e;
      practiceExerciseState.value = AsyncState.error(e);
      PracticeSessionHolder.instance.bump();
      if (mounted) setState(() {});
    }
  }

  Future<void> _completeSession() async {
    // Freeze elapsed at the authoritative wall-clock value (the per-second
    // ticker may not have fired since the panel was reopened).
    final startedAt = session.session?.startedAt;
    if (startedAt != null) {
      session.updateElapsedTime(DateTime.now().difference(startedAt).inSeconds);
    }
    session.completeSession();
    progress.value = session.progress;
    // Idle stops the timer and, via the notifier, flips the panel to the
    // completion view and clears the cluster badge.
    practiceExerciseState.value = const AsyncState.idle();
    PracticeSessionHolder.instance.bump();
    if (mounted) setState(() {});

    final bonus = session.bonusUses;
    await _analyticsController.addSessionAnalytics(bonus, _l2!.langCodeShort);

    if (mounted) {
      StarRainWidget.show(context, StarRainWidget.practiceCompleteKey);
    }
  }

  /// The header's explicit End control: confirm, discard the session, close
  /// the panel. The X never calls this — leaving is silent.
  Future<void> endSession() async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.areYouSure,
      okLabel: l10n.yes,
      cancelLabel: l10n.cancel,
      message: l10n.exitPractice,
    );
    if (result != OkCancelResult.ok) return;

    PracticeSessionHolder.instance.end();
    if (mounted) widget.close();
  }

  Future<void> _continueSession() async {
    if (practiceExerciseState.value
        is AsyncLoading<MultipleChoicePracticeExerciseModel>) {
      return;
    }

    if (session.session?.isComplete == true) {
      await _completeSession();
      return;
    }

    _clearExerciseState(loadingExercise: true);

    try {
      final resp = await session.getNextExercise(
        skipExercise,
        data.prefetchExerciseInfo,
      );

      if (resp != null) {
        _playExerciseAudio(resp);
        practiceExerciseState.value = AsyncState.loaded(resp);
      } else {
        await _completeSession();
      }
    } catch (e) {
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
    session.submitAnswer(uses);
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
    session.completeExercise();
    progress.value = session.progress;
    await _continueSession();
  }

  Future<void> skipExercise(PracticeTarget target) async {
    // Record a 0 XP use so that exercise isn't chosen again soon
    session.skipExercise();
    progress.value = session.progress;

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
