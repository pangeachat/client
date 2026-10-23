import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:record/record.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/features/journey_checklist/journey_moments.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_analytics_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_constants.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_data_service.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_notifier.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_ui_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_view.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/end_practice_session_dialog.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/example_message_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_skills_store.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_match.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/read_aloud_recorder.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_audio_practice_exercise_generator.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/vocab_meaning_practice_exercise_generator.dart';
import 'package:fluffychat/routes/chat/events/audio_playback_speed_controller.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/streaming_stt_session.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_audio_capture.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/star_rain_widget.dart';

class AnalyticsPractice extends StatefulWidget {
  final ConstructTypeEnum type;

  /// Scope the session to this Mission's target vocabulary (#9438); null is
  /// the learner's usual weak-word session.
  final String? missionId;

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
    this.missionId,
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

  /// When the read-aloud item on screen appeared; its time is banked off the
  /// speed bonus when the session moves on.
  DateTime? _readAloudShownAt;

  /// The start page chips the learner just set, shown while the session's
  /// words are picked again for them; null otherwise.
  final ValueNotifier<Set<LearningSkillsEnum>?> pendingSkills = ValueNotifier(
    null,
  );

  @override
  void initState() {
    super.initState();

    _analyticsController = AnalyticsPracticeAnalyticsController(
      Matrix.of(context).analyticsDataService,
    );

    _holderState = PracticeSessionHolder.instance.claim(
      widget.type,
      missionId: widget.missionId,
    );
    PracticeSessionHolder.instance.attachPanel();
    PracticeSessionHolder.instance.addListener(_onHolderChanged);

    // The learner is back — if a previous session timed out while they were
    // away, this reopen is where they find out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showTimeoutNotice());

    _addLanguageSubscription();
    _resumeOrStart();
  }

  @override
  void dispose() {
    PracticeSessionHolder.instance.removeListener(_onHolderChanged);
    PracticeSessionHolder.instance.detachPanel();
    _languageStreamSubscription?.cancel();
    audioPlaybackSpeedController.dispose();
    pendingSkills.dispose();
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
  bool get isLive => _holderState.isLive;
  bool get awaitingStart => _holderState.awaitingStart;

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
      ReadAloudPracticeExerciseModel() =>
        exercise.exampleMessage.exampleMessage,
      _ => await ExampleMessageUtil.getExampleMessage(
        await _analyticsController.getTargetTokenConstruct(
          exercise.practiceTarget,
          _l2!.langCodeShort,
        ),
        savedOnly: session.session?.offline ?? false,
      ),
    };

    _cachedTarget = exercise.practiceTarget;
    _cachedExampleMessage = message;
    return message;
  }

  bool _autoLaunchNextExercise(MultipleChoicePracticeExerciseModel exercise) =>
      exercise is! VocabAudioPracticeExerciseModel &&
      exercise is! ReadAloudPracticeExerciseModel;

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

  /// The idle timeout dropped the session out from under this panel. Other
  /// paths that drop it — the End control, a confirmed replace — are the
  /// learner's own doing and close the panel themselves, so they never set the
  /// notice and are deliberately ignored here.
  void _onHolderChanged() {
    if (!mounted) return;
    if (identical(PracticeSessionHolder.instance.current, _holderState)) {
      // A pick that a closed panel left in flight lands here, with nothing
      // else to rebuild this one onto the start page.
      setState(() {});
      return;
    }
    if (!PracticeSessionHolder.instance.hasTimeoutNotice) return;
    _showTimeoutNotice();
    widget.close();
  }

  void _showTimeoutNotice() {
    if (!mounted) return;
    if (!PracticeSessionHolder.instance.consumeTimeoutNotice()) return;
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(
        content: Text(
          L10n.of(context).practiceSessionTimedOut(
            AnalyticsPracticeConstants.idleTimeout.inMinutes,
          ),
        ),
      ),
    );
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
    PracticeSessionHolder.instance.markInteraction();
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

  /// Pick the session's words and open the start page, generating the first
  /// exercise behind it. [begin] goes straight to that exercise instead, for
  /// Another round, where the learner has just chosen to go again; with
  /// [keepCurrent] the start page stays up while its chips re-pick the words.
  /// See practice-exercises.instructions.md, "Start page".
  Future<void> startSession({
    bool begin = false,
    bool keepCurrent = false,
  }) async {
    // A session starting over a state whose watchdog was already stood down —
    // the Retry after a failed load, a language-change restart — needs the idle
    // clock re-armed from now, or the new session would go unwatched until its
    // first answer.
    PracticeSessionHolder.instance.markInteraction();
    _clearState();
    _holderState.firstExercise = null;

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
      final current = await session.startSession(
        widget.type,
        missionId: widget.missionId,
        skills: widget.type == ConstructTypeEnum.vocab
            ? await PracticeSkillsStore.load()
            : PracticeSkillsStore.vocabSkills,
        keepCurrent: keepCurrent,
      );
      if (!current) return;
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
        begin ? await _continueSession() : _prefetchFirstExercise();
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      session.sessionError = e;
      practiceExerciseState.value = AsyncState.error(e);
      PracticeSessionHolder.instance.bump();
      if (mounted) setState(() {});
    }
  }

  void _prefetchFirstExercise() {
    final offline = session.session?.offline ?? false;
    final first = session.getNextExercise(
      skipExercise,
      (exercise) => data.prefetchExerciseInfo(exercise, offline: offline),
    );
    // Awaited on Start, which shows any error; until then it must not
    // surface as unhandled.
    first.ignore();
    _holderState.firstExercise = first;
  }

  /// The start page's Start: the clock starts when the first exercise shows.
  Future<void> beginSession() async {
    PracticeSessionHolder.instance.markInteraction();
    await _continueSession();
  }

  /// The start page's chips: keep the choice on this device and pick the
  /// session's words again for it.
  Future<void> setSkills(Set<LearningSkillsEnum> skills) async {
    pendingSkills.value = skills;
    await PracticeSkillsStore.save(skills);
    await startSession(keepCurrent: true);
    // A later tap may already be picking for its own choice.
    if (identical(pendingSkills.value, skills)) pendingSkills.value = null;
  }

  Future<void> _completeSession() async {
    _bankReadAloudTime();
    // Freeze elapsed at the authoritative wall-clock value (the per-second
    // ticker may not have fired since the panel was reopened).
    final startedAt = session.session?.startedAt;
    if (startedAt != null) {
      session.updateElapsedTime(DateTime.now().difference(startedAt).inSeconds);
    }
    session.completeSession();
    JourneyMoments.practiceCompleted(Matrix.of(context).client, widget.type);
    progress.value = session.progress;
    // Idle stops the timer and, via the notifier, flips the panel to the
    // completion view and clears the cluster badge.
    practiceExerciseState.value = const AsyncState.idle();
    PracticeSessionHolder.instance.bump();
    if (mounted) setState(() {});

    final bonus = session.bonusUses;
    final language = _l2!.langCodeShort;
    try {
      await _analyticsController.addSessionAnalytics(bonus, language);
    } finally {
      // Measured even when the bonus write fails: the view then shows what
      // did count rather than waiting on a number that never comes.
      session.measureEarnedXp(_analyticsController.analyticsService, language);
      if (mounted) setState(() {});
    }

    if (mounted) {
      StarRainWidget.show(context, StarRainWidget.practiceCompleteKey);
    }
  }

  /// The header's explicit End control: confirm, discard the session, close
  /// the panel. The X never calls this — leaving is silent.
  Future<void> endSession() async {
    final ended = await EndPracticeSessionDialog.confirmAndEnd(
      context,
      type: widget.type,
      useRootNavigator: false,
    );
    if (ended && mounted) widget.close();
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
      final offline = session.session?.offline ?? false;
      final prefetched = _holderState.firstExercise;
      _holderState.firstExercise = null;
      final resp =
          await (prefetched ??
              session.getNextExercise(
                skipExercise,
                (exercise) =>
                    data.prefetchExerciseInfo(exercise, offline: offline),
              ));

      if (resp != null) {
        var next = resp;
        // Once the microphone is known to be unavailable, every remaining
        // read-aloud item is a meaning exercise for the same word.
        if (next is ReadAloudPracticeExerciseModel &&
            _holderState.micUnavailable) {
          final meaning = await _meaningInsteadOf(next);
          if (meaning == null) {
            await skipExercise(next.practiceTarget);
            _clearExerciseState();
            return _continueSession();
          }
          next = meaning;
        }
        // First exercise on screen = the clock's zero (#8966). Idempotent, so
        // every later exercise passing through here leaves it alone. The bump
        // is what puts the cluster badge up, since it now has a clock to show.
        session.session?.markStarted();
        PracticeSessionHolder.instance.bump();

        _playExerciseAudio(next);
        if (next is ReadAloudPracticeExerciseModel) {
          _readAloudShownAt = DateTime.now();
        }
        practiceExerciseState.value = AsyncState.loaded(next);
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

    PracticeSessionHolder.instance.markInteraction();

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

    final isComplete = notifier.exerciseComplete(exercise);

    // Every tap speaks the word it landed on. The audio exercise takes one tap
    // per word it heard, and the tap that finishes it is a word tap like the
    // rest (#8310); the meaning exercise instead replays its target there, so
    // it would say the same lemma twice.
    if (!isComplete || exercise is VocabAudioPracticeExerciseModel) {
      AnalyticsPracticeUiController.playChoiceAudio(
        exercise,
        choiceContent,
        _l2!.langCodeShort,
      );
    }

    if (!isComplete) return;

    _playExerciseAudio(exercise);

    if (_autoLaunchNextExercise(exercise)) {
      await Future.delayed(
        AnalyticsPracticeConstants.correctAnswerHold,
        startNextExercise,
      );
    }
  }

  Future<void> startNextExercise() async {
    // Also the audio exercise's explicit Continue tap, which is the only
    // learner action on that screen once the answer is in.
    PracticeSessionHolder.instance.markInteraction();
    _bankReadAloudTime();
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
    PracticeSessionHolder.instance.markInteraction();
    ErrorHandler.logError(
      e: 'Analytics practice exercise flagged',
      data: {'exercise': exercise.toJson(), 'feedback': feedback},
    );

    _bankReadAloudTime();
    await skipExercise(exercise.practiceTarget);
    await _continueSession();
  }

  /// Time a read-aloud item was on screen stays on the displayed clock but
  /// comes off the speed bonus (practice-exercises.instructions.md, "Scoring").
  void _bankReadAloudTime() {
    final shownAt = _readAloudShownAt;
    if (shownAt == null) return;
    _readAloudShownAt = null;
    session.session?.addReadAloudSeconds(
      DateTime.now().difference(shownAt).inSeconds,
    );
  }

  /// Record a read-aloud item's one answer: `corRA` when the target was heard,
  /// `incRA` when the tries ran out. Marks the item answered either way — the
  /// miss is the item's final state, not a wrong pick to try past.
  /// [targetHeard] decides the item; [heard], per reference word of the
  /// recorded take, says which other words earn a spoken-word use.
  Future<void> submitReadAloud(
    ReadAloudPracticeExerciseModel exercise, {
    required bool targetHeard,
    required List<bool> heard,
  }) async {
    PracticeSessionHolder.instance.markInteraction();
    if (notifier.exerciseComplete(exercise)) return;
    final uses = exercise.takeUses(targetHeard: targetHeard, heard: heard);
    session.submitAnswer(uses);
    notifier.selectChoice(exercise.heardAnswer);
    await _analyticsController.addCompletedExerciseAnalytics(
      uses,
      AnalyticsPracticeUiController.getChoiceTargetId(
        exercise.heardAnswer,
        widget.type,
      ),
      _l2!.langCodeShort,
    );
  }

  /// The microphone was refused or is absent: this item and the session's
  /// remaining read-aloud items become meaning exercises for the same words.
  Future<void> onMicUnavailable(ReadAloudPracticeExerciseModel exercise) async {
    _holderState.micUnavailable = true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).readAloudMicUnavailable)),
      );
    }
    final meaning = await _meaningInsteadOf(exercise);
    if (!identical(practiceExercise, exercise)) return;
    if (meaning == null) {
      await skipReadAloud(exercise);
      return;
    }
    _bankReadAloudTime();
    notifier.clearExerciseState();
    _playExerciseAudio(meaning);
    practiceExerciseState.value = AsyncState.loaded(meaning);
  }

  /// Leave a read-aloud item no route could transcribe, without recording it.
  Future<void> skipReadAloud(ReadAloudPracticeExerciseModel exercise) async {
    PracticeSessionHolder.instance.markInteraction();
    _bankReadAloudTime();
    await skipExercise(exercise.practiceTarget);
    await _continueSession();
  }

  /// A meaning exercise standing in for [exercise], or null when one cannot
  /// be built; the caller then skips the item.
  Future<MultipleChoicePracticeExerciseModel?> _meaningInsteadOf(
    ReadAloudPracticeExerciseModel exercise,
  ) async {
    final model = session.session;
    if (model == null) return null;
    try {
      final response = await VocabMeaningPracticeExerciseGenerator.get(
        VocabAudioPracticeExerciseGenerator.asMeaningRequest(
          MessagePracticeExerciseRequest(
            userL1: model.userL1,
            userL2: model.userL2,
            exerciseQualityFeedback: null,
            target: exercise.practiceTarget,
          ),
        ),
      );
      final meaning = response.exercise;
      if (meaning is! MultipleChoicePracticeExerciseModel) return null;
      await data.prefetchExerciseInfo(meaning, offline: model.offline);
      return meaning;
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'exercise': exercise.toJson()});
      return null;
    }
  }

  /// The microphone for one read-aloud item: live through the streaming relay
  /// where the target language is routed for it, else the batch route. On
  /// both, [sentence] goes along as the expected-text hint, so recognition is
  /// biased toward what the learner was asked to read.
  ReadAloudRecorder buildReadAloudRecorder(
    List<String> reference, {
    required String sentence,
  }) {
    final userController = MatrixState.pangeaController.userController;
    final hint = _expectedTextHint(sentence);
    return ReadAloudRecorder(
      reference: reference,
      hasMicPermission: () => AudioRecorder().hasPermission(),
      streamingSessionFactory: buildStreamingSessionFactory(
        flagEnabled: Environment.liveStreamingSttEnabled,
        messageLangCodeShort: _l2?.langCodeShort,
        accessToken: userController.accessToken,
        wsUrl: readAloudRelayUrl(
          PApiUrls.speechToTextStream,
          expectedText: hint,
        ),
      ),
      captureFactory: SttAudioCapture.new,
      transcribe: (wav) => _transcribeTake(wav, expectedText: hint),
    );
  }

  /// The sentence as the hint, or none when it is over the choreographer's
  /// cap, which would refuse the whole request. An item is at most a
  /// sentence of eight words, so a hint that long is a generator fault worth
  /// hearing about once.
  String? _expectedTextHint(String sentence) {
    final text = sentence.trim();
    if (text.isEmpty) return null;
    if (text.length <= SpeechToTextRequestModel.maxExpectedTextChars) {
      return text;
    }
    ErrorHandler.logErrorOnce(
      key: 'read_aloud_expected_text_over_cap',
      e: 'read-aloud sentence over the expected_text cap',
      s: StackTrace.current,
      data: {'length': text.length},
      level: SentryLevel.warning,
    );
    return null;
  }

  /// The words heard in a take through the batch route: empty when the audio
  /// held none, null when every provider failed and there is nothing to judge.
  Future<List<String>?> _transcribeTake(
    Uint8List wav, {
    required String? expectedText,
  }) async {
    final userController = MatrixState.pangeaController.userController;
    final result = await SpeechToTextRepo.instance.get(
      buildVoiceSttRequest(
        audioContent: wav,
        mimeType: 'audio/wav',
        userL1:
            userController.userL1?.langCodeShort ??
            LanguageKeys.unknownLanguage,
        userL2: _l2?.langCodeShort ?? LanguageKeys.unknownLanguage,
        expectedText: expectedText,
      ),
    );
    if (result.isError) return null;
    final response = result.result!;
    if (response.results.isEmpty) return null;
    if (!response.hasUsableTranscript) return const [];
    if (response.hasUsableTokens) {
      return [
        for (final stt in response.transcript.sttTokens)
          if (isSpokenWord(stt.token.text.content)) stt.token.text.content,
      ];
    }
    return spokenWords(response.transcript.text);
  }

  @override
  Widget build(BuildContext context) => AnalyticsPracticeView(this);
}
