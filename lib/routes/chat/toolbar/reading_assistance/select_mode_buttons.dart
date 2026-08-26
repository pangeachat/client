import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:collection/collection.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_shared_player_tracker.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/chat/events/utils/message_language_correction.dart';
import 'package:fluffychat/routes/chat/events/utils/report_message.dart';
import 'package:fluffychat/routes/chat/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/message_language_dialog.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_controller.dart';
import 'package:fluffychat/utils/multi_platform_audio_player.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SelectMode {
  audio(Icons.volume_up),
  translate(Icons.translate),
  practice(Symbols.fitness_center),
  emoji(Icons.add_reaction_outlined),
  speechTranslation(Icons.translate),
  requestRegenerate(Icons.replay);

  final IconData icon;
  const SelectMode(this.icon);

  String tooltip(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case SelectMode.audio:
        return l10n.playAudio;
      case SelectMode.translate:
      case SelectMode.speechTranslation:
        return l10n.translationTooltip;
      case SelectMode.practice:
        return l10n.practice;
      case SelectMode.emoji:
        return l10n.emojiView;
      case SelectMode.requestRegenerate:
        return l10n.requestRegeneration;
    }
  }

  /// The call to action an unsubscribed user gets in place of this mode's
  /// content. Named for the feature, so the gate advertises what the mode does
  /// rather than that it is locked (#7929).
  ///
  /// **Null means the mode is not subscription-gated at all** — this is the one
  /// place that decides, so a gate can't drift from the feature it guards.
  /// [SelectMode.requestRegenerate] is free: anyone may re-ask the bot, so it
  /// must never show a gate.
  String? unlockLabel(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case SelectMode.audio:
        return l10n.unlockPremiumAudio;
      case SelectMode.translate:
      case SelectMode.speechTranslation:
        return l10n.unlockTranslations;
      case SelectMode.practice:
        return l10n.unlockMessagePractice;
      case SelectMode.emoji:
        return l10n.unlockEmojiMode;
      case SelectMode.requestRegenerate:
        return null;
    }
  }

  String get buttonTarget => "select_mode_button_$name";
}

enum MessageActions {
  reply,
  forward,
  edit,
  delete,
  copy,
  download,
  pin,
  unpin,
  report,
  info,
  deleteOnError,
  sendAgain;

  IconData get icon {
    switch (this) {
      case MessageActions.reply:
        return Icons.reply_all;
      case MessageActions.forward:
        return Symbols.forward;
      case MessageActions.edit:
        return Symbols.edit;
      case MessageActions.delete:
        return Symbols.delete;
      case MessageActions.copy:
        return Icons.copy_outlined;
      case MessageActions.download:
        return Symbols.download;
      case MessageActions.pin:
        return Icons.push_pin;
      case MessageActions.unpin:
        return Icons.push_pin_outlined;
      case MessageActions.report:
        return Icons.shield_outlined;
      case MessageActions.info:
        return Icons.info_outlined;
      case MessageActions.deleteOnError:
        return Icons.delete;
      case MessageActions.sendAgain:
        return Icons.send_outlined;
    }
  }

  String tooltip(BuildContext context) {
    final l10n = L10n.of(context);
    switch (this) {
      case MessageActions.reply:
        return l10n.reply;
      case MessageActions.forward:
        return l10n.forward;
      case MessageActions.edit:
        return l10n.edit;
      case MessageActions.delete:
        return l10n.redactMessage;
      case MessageActions.copy:
        return l10n.copy;
      case MessageActions.download:
        return l10n.download;
      case MessageActions.pin:
        return l10n.pinMessage;
      case MessageActions.unpin:
        return l10n.unpin;
      case MessageActions.report:
        return l10n.reportMessage;
      case MessageActions.info:
        return l10n.messageInfo;
      case MessageActions.deleteOnError:
        return l10n.delete;
      case MessageActions.sendAgain:
        return l10n.tryToSendAgain;
    }
  }
}

class SelectModeButtons extends StatefulWidget {
  final VoidCallback launchPractice;
  final MessageOverlayController overlayController;
  final MessageToolbarHost controller;

  const SelectModeButtons({
    required this.launchPractice,
    required this.overlayController,
    required this.controller,
    super.key,
  });

  @override
  State<SelectModeButtons> createState() => SelectModeButtonsState();
}

class SelectModeButtonsState extends State<SelectModeButtons> {
  static const double iconWidth = 36.0;
  static const double buttonSize = 40.0;

  /// The mode buttons the host's [config] leaves visible.
  @visibleForTesting
  static List<SelectMode> visibleModes(
    List<SelectMode> allModes,
    MessageToolbarConfig config,
  ) => config.showPracticeButton
      ? allModes
      : allModes.where((mode) => mode != SelectMode.practice).toList();

  /// Long enough to read as "until dismissed": the mode-disabled snackbar is
  /// closed on the message closing, not on a timer.
  static const Duration _modeDisabledSnackBarDuration = Duration(days: 1);

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _modeDisabledSnackBar;

  StreamSubscription? _playerStateSub;
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);

  /// Elapsed-playback accounting for listening category 3 (#104). Driven from
  /// [_onUpdatePlayerState], which this widget already subscribes to for the
  /// play/pause button state, so the measurement adds no new subscription and no
  /// new work on the playback path.
  DosageSharedPlayerTracker? _listeningTracker;

  /// This widget's key in the shared player's owner notifier. The same string
  /// [playAudio] and [_reloadAndPlayAudio] set, and the reason a timeline
  /// bubble's peer measurement cannot claim this playback: the ids differ.
  String get _playerOwnerId => "${messageEvent.eventId}_button";

  StreamSubscription? _audioSub;

  MatrixState? matrix;

  final ValueNotifier<bool> _shimmerTranslateButton = ValueNotifier(false);

  @override
  void initState() {
    super.initState();

    matrix = Matrix.of(context);
    if (messageEvent.isAudioMessage == true) {
      controller.fetchTranscription();
    }

    controller.playTokenNotifier.addListener(_playToken);
    // #Pangea
    matrix?.voiceMessageEventId.addListener(_onListeningOwnershipChange);
    // Pangea#

    // This widget owns the select-mode targets and only exists while the
    // toolbar is open, so it registers as their owner; registering while the
    // tutorial is already waiting is itself the launch trigger.
    final tutorials = MatrixState.tutorialOverlayController;
    tutorials.registerLauncher(
      TutorialEnum.selectModeButtons,
      _startSelectModeTutorial,
    );
    // The shimmer nudges toward the translate button; the tutorial does that
    // job itself while it runs, and turns the shimmer back on when it moves on.
    _shimmerTranslateButton.value = !tutorials.isTutorialQueued(
      TutorialEnum.selectModeButtons,
    );
  }

  @override
  void dispose() {
    final tutorial = MatrixState.tutorialOverlayController;
    tutorial.unregisterLauncher(
      TutorialEnum.selectModeButtons,
      _startSelectModeTutorial,
    );
    if (tutorial.state.isTutorialActive(TutorialEnum.selectModeButtons) &&
        !tutorial.state.model.isStepTransitioning) {
      tutorial.resetTutorial();
    }

    _closeModeDisabledSnackBar();
    // #Pangea
    // BEFORE the player is torn down and the owner id cleared: a playback the
    // learner closed the toolbar on is still listening that happened, and its
    // measurement would be lost once ownership is gone. The listener comes off
    // first so clearing the notifier below cannot re-enter this.
    matrix?.voiceMessageEventId.removeListener(_onListeningOwnershipChange);
    _listeningTracker?.close();
    // Pangea#
    matrix?.audioPlayer?.dispose();
    matrix?.audioPlayer = null;
    matrix?.voiceMessageEventId.value = null;
    _audioSub?.cancel();
    _playerStateSub?.cancel();
    _isPlayingNotifier.dispose();
    controller.playTokenNotifier.removeListener(_playToken);
    _shimmerTranslateButton.dispose();
    super.dispose();
  }

  PangeaMessageEvent get messageEvent =>
      widget.overlayController.pangeaMessageEvent;

  SelectModeController get controller =>
      widget.overlayController.selectModeController;

  bool get _canRefresh =>
      messageEvent.eventId == widget.controller.chatController?.refreshEventID;

  Future<void> _startSelectModeTutorial() async {
    final chat = widget.controller.chatController;
    if (chat == null) return;
    if (!mounted || controller.selectedMode.value != null) return;

    _shimmerTranslateButton.value = false;

    final translateTarget = SelectMode.translate.buttonTarget;
    final audioTarget = SelectMode.audio.buttonTarget;
    final msgTarget = widget.overlayController.overlayMessageKey;
    final tokenTarget = chat.tutorialTokenTargetKey;
    if (tokenTarget == null) {
      _shimmerTranslateButton.value = true;
      return;
    }

    chat.tutorialOverlayController.launchTutorial(
      context: context,
      tutorial: TutorialModel(
        tutorialType: TutorialEnum.selectModeButtons,
        stepsData: [
          TutorialStepData.single(
            targetKey: tokenTarget,
            onTap: () async {
              widget.overlayController.updateSelectedSpan(
                chat.tutorialToken!.text,
              );
              await Future.delayed(Duration(milliseconds: 4000));
              widget.overlayController.updateSelectedSpan(null);
              _shimmerTranslateButton.value = true;
            },
            canShowNextStep: () =>
                mounted && controller.selectedMode.value == null,
          ),
          TutorialStepData.single(
            targetKey: translateTarget,
            onTap: () async {
              await updateMode(SelectMode.translate);
              await Future.delayed(Duration(milliseconds: 4000));
            },
            canShowNextStep: () =>
                mounted &&
                controller.selectedMode.value == SelectMode.translate,
          ),
          TutorialStepData.single(
            targetKey: audioTarget,
            onTap: () async {
              await updateMode(SelectMode.audio);
              await Future.delayed(Duration(milliseconds: 1000));
            },
            canShowNextStep: () =>
                mounted && controller.selectedMode.value == SelectMode.audio,
          ),
          TutorialStepData.single(
            targetKey: msgTarget,
            onTap: () async => widget.controller.clearSelectedEvents(),
            canShowNextStep: () => true,
          ),
        ],
      ),
      isFocused: chat.isFocused,
    );
  }

  Future<void> updateMode(SelectMode? mode) async {
    widget.overlayController.updateSelectedSpan(null);
    if (mode == null) {
      matrix?.audioPlayer?.stop();
      matrix?.audioPlayer?.seek(null);
      controller.setSelectMode(mode);
      return;
    }

    final updatedMode =
        controller.selectedMode.value == mode && mode != SelectMode.audio
        ? null
        : mode;
    controller.setSelectMode(updatedMode);

    if (updatedMode == SelectMode.audio) {
      await playAudio();
      return;
    } else {
      matrix?.audioPlayer?.stop();
      matrix?.audioPlayer?.seek(null);
    }

    if (updatedMode == SelectMode.practice) {
      widget.launchPractice();
      return;
    }

    if (updatedMode == SelectMode.translate) {
      if (!InstructionsEnum.shimmerTranslation.isToggledOff) {
        InstructionsEnum.shimmerTranslation.setToggledOff(true);
      }
      await controller.fetchTranslation();
    }

    if (updatedMode == SelectMode.speechTranslation) {
      await controller.fetchSpeechTranslation();
    }

    if (updatedMode == SelectMode.requestRegenerate) {
      await widget.controller.chatController?.requestRegeneration(
        messageEvent.eventId,
      );

      if (mounted) {
        controller.setSelectMode(null);
      }
    }

    if (updatedMode == SelectMode.emoji) {
      if (!InstructionsEnum.emojiToolbarMode.isToggledOff) {
        InstructionsEnum.emojiToolbarMode.setToggledOff(true);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(
            content: Text(L10n.of(context).emojiToolbarInstruction),
            showCloseIcon: true,
          ),
        );
      }
    }
  }

  /// Dismisses the mode-disabled snackbar. With accessible navigation on, a
  /// close removes the snackbar SYNCHRONOUSLY, so closing from [dispose] lands
  /// mid-unmount — the messenger's rebuild throws there and the snackbar is
  /// stranded on screen. Defer whenever we're inside a frame.
  void _closeModeDisabledSnackBar() {
    final snackBar = _modeDisabledSnackBar;
    if (snackBar == null) return;
    _modeDisabledSnackBar = null;

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      snackBar.close();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => snackBar.close());
  }

  /// Explains why a mode is greyed out, names the language the message is
  /// assigned, and offers the two ways out: correct that assignment, or move
  /// your target language onto it. Stays up while the message is open (closed
  /// in [dispose]) — the user needs it under the language picker it opens.
  Future<void> modeDisabled() async {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final chat = widget.controller.chatController;

    final assignedLanguage = MessageLanguageCorrection.assignedLanguage(
      messageEvent,
    );
    final l1 = MatrixState.pangeaController.userController.userL1;

    // Only a text message's language is correctable: an audio message takes its
    // language from the speech-to-text transcription, which a representation
    // correction does not feed.
    final canSetMessageLanguage =
        messageEvent.event.messageType == MessageTypes.Text;
    final canSetTargetLanguage =
        chat != null &&
        assignedLanguage != null &&
        assignedLanguage.langCodeShort != l1?.langCodeShort;

    final explanation = assignedLanguage == null
        ? l10n.modeDisabled
        : '${l10n.modeDisabled} '
              '${l10n.messageLanguageIs(assignedLanguage.getDisplayName(l10n))}';

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    _modeDisabledSnackBar = messenger.showSnackBarAnnounced(
      SnackBar(
        duration: _modeDisabledSnackBarDuration,
        showCloseIcon: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4.0,
          children: [
            Text(
              explanation,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.surface),
            ),
            if (canSetMessageLanguage)
              _SnackBarLink(
                label: l10n.updateMessageLanguage,
                onTap: _showMessageLanguageDialog,
              ),
            if (canSetTargetLanguage)
              _SnackBarLink(
                label: l10n.clickToUpdateTargetLanguage,
                onTap: () {
                  _closeModeDisabledSnackBar();
                  chat.updateLanguageOnMismatch(assignedLanguage);
                },
              ),
          ],
        ),
      ),
      announcement: [
        explanation,
        if (canSetMessageLanguage) l10n.updateMessageLanguage,
        if (canSetTargetLanguage) l10n.clickToUpdateTargetLanguage,
      ].join(' '),
    );
  }

  /// The corrected language re-tokenizes the message, so every token-derived
  /// surface the overlay is showing is stale: close it and confirm, the same
  /// way token-info feedback does, rather than half-refresh it in place.
  Future<void> _showMessageLanguageDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final updatedMessage = L10n.of(context).messageLanguageUpdated;

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => MessageLanguageDialog(messageEvent: messageEvent),
    );
    if (updated != true) return;

    _closeModeDisabledSnackBar();
    widget.controller.clearSelectedEvents();
    messenger.showSnackBarAnnounced(
      SnackBar(content: Text(updatedMessage, textAlign: TextAlign.center)),
    );
  }

  Future<void> playAudio() async {
    final playerID = _playerOwnerId;
    final isPlaying =
        matrix?.audioPlayer != null &&
        matrix?.voiceMessageEventId.value == playerID &&
        matrix!.audioPlayer!.playerState.processingState !=
            ProcessingState.completed;

    if (isPlaying) {
      matrix!.audioPlayer!.playerState.playing
          ? await matrix!.audioPlayer!.pause()
          : await matrix!.audioPlayer!.play();
      return;
    }

    await _reloadAndPlayAudio();
  }

  Future<void> _reloadAndPlayAudio({Duration? seek}) async {
    matrix?.audioPlayer?.dispose();
    matrix?.audioPlayer = AudioPlayer();
    matrix?.voiceMessageEventId.value = _playerOwnerId;

    _playerStateSub?.cancel();
    _playerStateSub = matrix?.audioPlayer?.playerStateStream.listen(
      _onUpdatePlayerState,
    );

    _audioSub?.cancel();
    _audioSub = matrix?.audioPlayer?.positionStream.listen(_onPlayAudio);

    try {
      if (controller.audioFile == null) {
        await controller.fetchAudio();
      }

      if (controller.audioFile == null) return;

      final audioFile = controller.audioFile!;

      TtsController.forceStop();

      if (seek != null) {
        matrix!.audioPlayer!.seek(seek);
      }

      final matrixFilePlayer = MultiPlatformAudioPlayer(
        audioPlayer: matrix!.audioPlayer!,
        bytes: audioFile.bytes,
        name: audioFile.name,
        mimeType: audioFile.mimeType,
      );
      await matrixFilePlayer.setAudioSourceAndPlay();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'something wrong playing message audio',
        data: {'event': messageEvent.event.toJson()},
      );
    }
  }

  void _onPlayAudio(Duration duration) {
    if (controller.audioFile?.tokens != null) {
      widget.overlayController.highlightCurrentText(
        duration.inMilliseconds,
        controller.audioFile!.tokens!,
      );
    }
  }

  void _onUpdatePlayerState(PlayerState state) {
    final current = _isPlayingNotifier.value;
    if (!current &&
        state.processingState == ProcessingState.ready &&
        state.playing) {
      _isPlayingNotifier.value = true;
    } else if (current &&
        (!state.playing ||
            state.processingState == ProcessingState.completed)) {
      _isPlayingNotifier.value = false;
    }
    // #Pangea
    _trackListening(state);
    // Pangea#
  }

  // #Pangea
  /// Accumulates listening category 3 off the same player state the button
  /// already reads: the learner TAPPED the speaker button on a message in
  /// conversation.
  ///
  /// This is the paid backend TTS path, but that is not what defines the
  /// category — a learner-initiated playback is category 3 whoever paid, and an
  /// automatic read-aloud is category 2 even when it uses the same paid voice
  /// (D-V2-3). Deliberately NOT emitted for the message practice card, which
  /// also fetches paid TTS for a specific message and so also has a room: it is
  /// a practice surface, and blending drill behaviour into a conversation metric
  /// would produce a precise number about an undefined scope.
  ///
  /// Synchronous: an in-memory append, no await, nothing the learner can
  /// perceive.
  void _trackListening(PlayerState state) {
    _listeningTracker ??= DosageSharedPlayerTracker(
      category: DosageListeningCategory.tapRead,
      roomId: messageEvent.event.room.id,
      ownerId: _playerOwnerId,
      userId: () => matrix?.client.userID,
      accessToken: () => matrix?.client.accessToken,
    );
    _listeningTracker!.update(
      playing: state.playing,
      completed: state.processingState == ProcessingState.completed,
      currentOwnerId: matrix?.voiceMessageEventId.value,
    );
  }

  /// Closes the measurement the moment another surface takes the shared player.
  ///
  /// The player-state subscription above is NOT sufficient on its own, and this
  /// is why: a surface that takes the player stops and DISPOSES the one this
  /// widget is subscribed to, and a disposed player closes its state stream —
  /// so the transition that would have closed the measurement may never be
  /// delivered. The meter would then keep running and, at toolbar dispose, book
  /// however long the learner spent listening to somebody else's voice message
  /// as a speaker-button read-aloud.
  ///
  /// Ownership changes through the notifier whether or not a state event
  /// follows, so the notifier is the reliable signal. The timeline player guards
  /// itself the same way, and an invariant test pins that both do.
  void _onListeningOwnershipChange() {
    if (matrix?.voiceMessageEventId.value == _playerOwnerId) return;
    _listeningTracker?.close();
  }
  // Pangea#

  void _playToken() {
    final token = controller.playTokenNotifier.value.$1;

    if (token == null ||
        controller.audioFile?.tokens == null ||
        controller.selectedMode.value != SelectMode.audio) {
      return;
    }

    final ttsToken = controller.audioFile!.tokens!.firstWhereOrNull(
      (t) => t.text == token,
    );

    if (ttsToken == null) return;

    final isPlaying =
        matrix?.audioPlayer != null &&
        matrix!.audioPlayer!.playerState.processingState !=
            ProcessingState.completed;

    final start = Duration(milliseconds: ttsToken.startMS);
    if (isPlaying) {
      matrix!.audioPlayer!.seek(start);
      matrix!.audioPlayer!.play();
    } else {
      _reloadAndPlayAudio(seek: start);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.overlayController.config;
    final chat = widget.controller.chatController;
    final modes = controller.readingAssistanceModes;
    final allModes = visibleModes(
      controller.allModes(enableRefresh: _canRefresh),
      config,
    );
    final showMoreButton = config.showMoreButton && chat != null;

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: AppConfig.toolbarMenuHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(allModes.length + (showMoreButton ? 1 : 0), (
            index,
          ) {
            if (index < allModes.length) {
              final mode = allModes[index];
              final enabled = modes(enableRefresh: _canRefresh).contains(mode);
              return Container(
                width: 45.0,
                alignment: Alignment.center,
                child: Tooltip(
                  message: mode.tooltip(context),
                  child: Semantics(
                    enabled: enabled,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        controller.selectedMode,
                        controller.modeStateNotifier(mode),
                      ]),
                      builder: (context, _) {
                        final selectedMode = controller.selectedMode.value;
                        final target = MatrixState.pAnyState.layerLinkAndKey(
                          mode.buttonTarget,
                        );
                        return Opacity(
                          opacity: enabled ? 1.0 : 0.75,
                          child: CompositedTransformTarget(
                            link: target.link,
                            child: PressableButton(
                              key: target.key,
                              borderRadius: BorderRadius.circular(20),
                              depressed: mode == selectedMode || !enabled,
                              color: theme.colorScheme.primaryContainer,
                              onPressed: enabled
                                  ? () => updateMode(mode)
                                  : modeDisabled,
                              playSound: enabled && mode != SelectMode.audio,
                              colorFactor: theme.brightness == Brightness.light
                                  ? 0.55
                                  : 0.3,
                              builder: (context, depressed, shadowColor) {
                                final canShimmer =
                                    !InstructionsEnum
                                        .shimmerTranslation
                                        .isToggledOff &&
                                    mode == SelectMode.translate &&
                                    enabled;

                                final content = AnimatedContainer(
                                  duration: FluffyThemes.animationDuration,
                                  height: buttonSize,
                                  width: buttonSize,
                                  decoration: BoxDecoration(
                                    color: depressed
                                        ? shadowColor
                                        : theme.colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: ValueListenableBuilder(
                                    valueListenable: _isPlayingNotifier,
                                    builder: (context, playing, _) =>
                                        _SelectModeButtonIcon(
                                          mode: mode,
                                          loading:
                                              controller.isLoading &&
                                              mode == selectedMode,
                                          playing:
                                              mode == SelectMode.audio &&
                                              playing,
                                          color: theme
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                );

                                return canShimmer
                                    ? ValueListenableBuilder(
                                        valueListenable:
                                            _shimmerTranslateButton,
                                        builder: (context, shimmer, child) =>
                                            ShimmerBackground(
                                              enabled: shimmer,
                                              borderRadius:
                                                  BorderRadius.circular(100),
                                              maxOpacity: 0.6,
                                              child: child!,
                                            ),
                                        child: content,
                                      )
                                    : content;
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            } else {
              return Container(
                width: 45.0,
                alignment: Alignment.center,
                child: _MoreButton(
                  controller: chat!,
                  messageEvent: messageEvent,
                ),
              );
            }
          }),
        ),
      ),
    );
  }
}

/// A tappable line inside the mode-disabled snackbar, styled to read as a link
/// against the snackbar's inverted surface.
class _SnackBarLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SnackBarLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primaryContainer;
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    );
  }
}

class _SelectModeButtonIcon extends StatelessWidget {
  final SelectMode mode;
  final bool loading;
  final bool playing;
  final Color color;

  const _SelectModeButtonIcon({
    required this.mode,
    this.loading = false,
    this.playing = false,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          height: 20.0,
          width: 20.0,
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    if (mode == SelectMode.audio) {
      return Icon(
        playing ? Icons.pause_outlined : Icons.volume_up,
        size: 20,
        color: color,
      );
    }

    return Icon(mode.icon, size: 20, color: color);
  }
}

class _MoreButton extends StatelessWidget {
  final ChatController controller;
  final PangeaMessageEvent? messageEvent;

  const _MoreButton({required this.controller, this.messageEvent});

  bool _messageActionEnabled(MessageActions action) {
    if (messageEvent == null) return false;
    if (controller.selectedEvents.isEmpty) return false;
    final events = controller.selectedEvents;

    if (events.any((e) => !e.status.isSent)) {
      if (action == MessageActions.sendAgain) {
        return true;
      }

      if (events.every((e) => e.status.isError) &&
          action == MessageActions.deleteOnError) {
        return true;
      }

      return false;
    }

    final isPinned =
        events.length == 1 &&
        controller.room.pinnedEventIds.contains(events.first.eventId);

    switch (action) {
      case MessageActions.reply:
        return events.length == 1 &&
            controller.room.canSendDefaultMessages &&
            !controller.room.isActivityFinished;
      case MessageActions.edit:
        return controller.canEditSelectedEvents &&
            !events.first.isActivityMessage &&
            events.single.messageType == MessageTypes.Text;
      case MessageActions.delete:
        return controller.canRedactSelectedEvents;
      case MessageActions.copy:
        return events.length == 1 &&
            events.single.messageType == MessageTypes.Text;
      case MessageActions.download:
        return controller.canSaveSelectedEvent;
      case MessageActions.pin:
        return controller.canPinSelectedEvents && !isPinned;
      case MessageActions.unpin:
        return controller.canPinSelectedEvents && isPinned;
      case MessageActions.forward:
      case MessageActions.report:
        return events.length == 1;
      case MessageActions.info:
        return events.length == 1 &&
            MatrixState.pangeaController.userController.showDeveloperOptions;
      case MessageActions.deleteOnError:
      case MessageActions.sendAgain:
        return false;
    }
  }

  Future<void> _showMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox;

    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(offset, offset + button.size.bottomRight(Offset.zero)),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<MessageActions>(
      useRootNavigator: true,
      context: context,
      position: position,
      items: MessageActions.values
          .where(_messageActionEnabled)
          .map(
            (action) => PopupMenuItem<MessageActions>(
              value: action,
              child: Row(
                children: [
                  Icon(action.icon),
                  const SizedBox(width: 8.0),
                  Text(action.tooltip(context)),
                ],
              ),
            ),
          )
          .toList(),
    );

    if (action == null) return;
    _onActionPressed(action, context);
  }

  void _onActionPressed(MessageActions action, BuildContext context) {
    switch (action) {
      case MessageActions.reply:
        controller.replyAction();
        break;
      case MessageActions.forward:
        controller.forwardEventsAction();
        break;
      case MessageActions.edit:
        controller.editSelectedEventAction();
        break;
      case MessageActions.delete:
        controller.redactEventsAction();
        break;
      case MessageActions.copy:
        controller.copyEventsAction();
        break;
      case MessageActions.download:
        controller.saveSelectedEvent(context);
        break;
      case MessageActions.pin:
      case MessageActions.unpin:
        controller.pinEvent();
        break;
      case MessageActions.report:
        final event = controller.selectedEvents.first;
        controller.clearSelectedEvents();
        reportEvent(event, controller, controller.context);
        break;
      case MessageActions.info:
        controller.showEventInfo();
        break;
      case MessageActions.deleteOnError:
        controller.deleteErrorEventsAction();
        break;
      case MessageActions.sendAgain:
        controller.sendAgainAction();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: L10n.of(context).more,
      child: PressableButton(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.primaryContainer,
        onPressed: () => _showMenu(context),
        playSound: true,
        colorFactor: theme.brightness == Brightness.light ? 0.55 : 0.3,
        builder: (context, depressed, shadowColor) => AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          height: 40.0,
          width: 40.0,
          decoration: BoxDecoration(
            color: depressed ? shadowColor : theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.more_horiz, size: 20),
        ),
      ),
    );
  }
}
