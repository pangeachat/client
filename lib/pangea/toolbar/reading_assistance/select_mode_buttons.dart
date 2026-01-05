import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/audio_player.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/pangea/events/utils/report_message.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/message_audio_card.dart';
import 'package:fluffychat/pangea/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum SelectMode {
  audio(Icons.volume_up),
  translate(Icons.translate),
  practice(Symbols.fitness_center),
  emoji(Icons.add_reaction_outlined),
  speechTranslation(Icons.translate);

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
    }
  }
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
  final ChatController controller;

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

  StreamSubscription? _playerStateSub;
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);
  StreamSubscription? _audioSub;

  MatrixState? matrix;

  @override
  void initState() {
    super.initState();

    matrix = Matrix.of(context);
    if (messageEvent.isAudioMessage == true) {
      controller.fetchTranscription();
    }

    controller.playTokenNotifier.addListener(_playToken);
  }

  @override
  void dispose() {
    matrix?.audioPlayer?.dispose();
    matrix?.audioPlayer = null;
    matrix?.voiceMessageEventId.value = null;
    _audioSub?.cancel();
    _playerStateSub?.cancel();
    _isPlayingNotifier.dispose();
    controller.playTokenNotifier.removeListener(_playToken);
    super.dispose();
  }

  PangeaMessageEvent get messageEvent =>
      widget.overlayController.pangeaMessageEvent;

  SelectModeController get controller =>
      widget.overlayController.selectModeController;

  Future<void> updateMode(SelectMode? mode) async {
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
      playAudio();
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
      await controller.fetchTranslation();
    }

    if (updatedMode == SelectMode.speechTranslation) {
      await controller.fetchSpeechTranslation();
    }
  }

  Future<void> modeDisabled() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.of(context).modeDisabled),
      ),
    );
  }

  Future<void> playAudio() async {
    final playerID = "${messageEvent.eventId}_button";
    final isPlaying = matrix?.audioPlayer != null &&
        matrix?.voiceMessageEventId.value == playerID &&
        matrix!.audioPlayer!.playerState.processingState !=
            ProcessingState.completed;

    if (isPlaying) {
      matrix!.audioPlayer!.playerState.playing
          ? await matrix!.audioPlayer!.pause()
          : await matrix!.audioPlayer!.play();
      return;
    }

    _reloadAudio();
  }

  Future<void> _reloadAudio({Duration? seek}) async {
    matrix?.audioPlayer?.dispose();
    matrix?.audioPlayer = AudioPlayer();
    matrix?.voiceMessageEventId.value = "${messageEvent.eventId}_button";

    _playerStateSub?.cancel();
    _playerStateSub =
        matrix?.audioPlayer?.playerStateStream.listen(_onUpdatePlayerState);

    _audioSub?.cancel();
    _audioSub = matrix?.audioPlayer?.positionStream.listen(_onPlayAudio);

    try {
      if (controller.audioFile == null) {
        await controller.fetchAudio();
      }

      if (controller.audioFile == null) return;

      final (PangeaAudioFile pangeaAudioFile, File? audioFile) =
          controller.audioFile!;

      if (audioFile != null) {
        await matrix?.audioPlayer?.setFilePath(audioFile.path);
      } else {
        await matrix?.audioPlayer?.setAudioSource(
          BytesAudioSource(
            pangeaAudioFile.bytes,
            pangeaAudioFile.mimeType,
          ),
        );
      }

      TtsController.stop();

      if (seek != null) {
        matrix!.audioPlayer!.seek(seek);
      }

      await matrix?.audioPlayer?.play();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: 'something wrong playing message audio',
        data: {
          'event': messageEvent.event.toJson(),
        },
      );
    }
  }

  void _onPlayAudio(Duration duration) {
    if (controller.audioFile?.$1.tokens != null) {
      widget.overlayController.highlightCurrentText(
        duration.inMilliseconds,
        controller.audioFile!.$1.tokens!,
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
  }

  void _playToken() {
    final token = controller.playTokenNotifier.value.$1;

    if (token == null ||
        controller.audioFile?.$1.tokens == null ||
        controller.selectedMode.value != SelectMode.audio) {
      return;
    }

    final ttsToken = controller.audioFile!.$1.tokens!.firstWhereOrNull(
      (t) => t.text == token,
    );

    if (ttsToken == null) return;

    final isPlaying = matrix?.audioPlayer != null &&
        matrix!.audioPlayer!.playerState.processingState !=
            ProcessingState.completed;

    final start = Duration(milliseconds: ttsToken.startMS);
    if (isPlaying) {
      matrix!.audioPlayer!.seek(start);
      matrix!.audioPlayer!.play();
    } else {
      _reloadAudio(seek: start);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = controller.readingAssistanceModes;
    final allModes = controller.allModes;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: AppConfig.toolbarMenuHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(allModes.length + 1, (index) {
            if (index < allModes.length) {
              final mode = allModes[index];
              final enabled = modes.contains(mode);
              return Container(
                width: 45.0,
                alignment: Alignment.center,
                child: Tooltip(
                  message: mode.tooltip(context),
                  child: ListenableBuilder(
                    listenable: Listenable.merge(
                      [
                        controller.selectedMode,
                        controller.modeStateNotifier(mode),
                      ],
                    ),
                    builder: (context, _) {
                      final selectedMode = controller.selectedMode.value;
                      return Opacity(
                        opacity: enabled ? 1.0 : 0.5,
                        child: PressableButton(
                          borderRadius: BorderRadius.circular(20),
                          depressed: mode == selectedMode || !enabled,
                          color: enabled
                              ? theme.colorScheme.primaryContainer
                              : theme.disabledColor,
                          onPressed:
                              enabled ? () => updateMode(mode) : modeDisabled,
                          playSound: enabled && mode != SelectMode.audio,
                          colorFactor:
                              theme.brightness == Brightness.light ? 0.55 : 0.3,
                          builder: (context, depressed, shadowColor) =>
                              AnimatedContainer(
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
                              builder: (context, playing, __) =>
                                  _SelectModeButtonIcon(
                                mode: mode,
                                loading: controller.isLoading &&
                                    mode == selectedMode,
                                playing: mode == SelectMode.audio && playing,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            } else {
              return Container(
                width: 45.0,
                alignment: Alignment.center,
                child: _MoreButton(
                  controller: widget.controller,
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

class _SelectModeButtonIcon extends StatelessWidget {
  final SelectMode mode;
  final bool loading;
  final bool playing;

  const _SelectModeButtonIcon({
    required this.mode,
    this.loading = false,
    this.playing = false,
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
      );
    }

    return Icon(mode.icon, size: 20);
  }
}

class _MoreButton extends StatelessWidget {
  final ChatController controller;
  final PangeaMessageEvent? messageEvent;

  const _MoreButton({
    required this.controller,
    this.messageEvent,
  });

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

    final isPinned = events.length == 1 &&
        controller.room.pinnedEventIds.contains(events.first.eventId);

    switch (action) {
      case MessageActions.reply:
        return events.length == 1 && controller.room.canSendDefaultMessages;
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
      case MessageActions.info:
        return events.length == 1;
      case MessageActions.deleteOnError:
      case MessageActions.sendAgain:
        return false;
    }
  }

  Future<void> _showMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox;

    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        offset,
        offset + button.size.bottomRight(Offset.zero),
      ),
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

  void _onActionPressed(
    MessageActions action,
    BuildContext context,
  ) {
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
        reportEvent(
          event,
          controller,
          controller.context,
        );
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
          child: const Icon(
            Icons.more_horiz,
            size: 20,
          ),
        ),
      ),
    );
  }
}
