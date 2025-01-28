import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics/controllers/message_analytics_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/toolbar/controllers/text_to_speech_controller.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_positioner.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Controls data at the top level of the toolbar (mainly token / toolbar mode selection)
class MessageSelectionOverlay extends StatefulWidget {
  final ChatController chatController;
  final Event _event;
  final Event? _nextEvent;
  final Event? _prevEvent;
  final PangeaMessageEvent? _pangeaMessageEvent;
  final PangeaToken? _initialSelectedToken;

  const MessageSelectionOverlay({
    required this.chatController,
    required Event event,
    required PangeaMessageEvent? pangeaMessageEvent,
    required PangeaToken? initialSelectedToken,
    required Event? nextEvent,
    required Event? prevEvent,
    super.key,
  })  : _initialSelectedToken = initialSelectedToken,
        _pangeaMessageEvent = pangeaMessageEvent,
        _nextEvent = nextEvent,
        _prevEvent = prevEvent,
        _event = event;

  @override
  MessageOverlayController createState() => MessageOverlayController();
}

class MessageOverlayController extends State<MessageSelectionOverlay>
    with SingleTickerProviderStateMixin {
  MessageMode toolbarMode = MessageMode.noneSelected;
  PangeaTokenText? _selectedSpan;
  List<PangeaTokenText>? _highlightedTokens;

  List<PangeaToken>? tokens;
  bool initialized = false;

  PangeaMessageEvent? get pangeaMessageEvent => widget._pangeaMessageEvent;

  bool isPlayingAudio = false;

  bool get showToolbarButtons =>
      pangeaMessageEvent != null &&
      pangeaMessageEvent!.event.messageType == MessageTypes.Text;

  int get activitiesLeftToComplete => messageAnalyticsEntry?.numActivities ?? 0;

  bool get isPracticeComplete =>
      (pangeaMessageEvent?.proportionOfActivitiesCompleted ?? 1) >= 1 ||
      !messageInUserL2;

  /// Decides whether an _initialSelectedToken should be used
  /// for a first practice activity on the word meaning
  void _initializeSelectedToken() {
    // if there is no initial selected token, then we don't need to do anything
    if (widget._initialSelectedToken == null || messageAnalyticsEntry == null) {
      return;
    }

    // should not already be involved in a hidden word activity
    final isInHiddenWordActivity =
        messageAnalyticsEntry!.isTokenInHiddenWordActivity(
      widget._initialSelectedToken!,
    );

    // whether the activity should generally be involved in an activity
    final selected =
        !isInHiddenWordActivity ? widget._initialSelectedToken : null;

    if (selected != null) {
      _updateSelectedSpan(selected.text);
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeTokensAndMode();
  }

  void _updateSelectedSpan(PangeaTokenText selectedSpan) {
    _selectedSpan = selectedSpan;

    if (!(messageAnalyticsEntry?.hasHiddenWordActivity ?? false)) {
      widget.chatController.choreographer.tts.tryToSpeak(
        selectedSpan.content,
        context,
        widget._pangeaMessageEvent?.eventId,
      );
    }

    // if a token is selected, then the toolbar should be in wordZoom mode
    if (toolbarMode != MessageMode.wordZoom) {
      debugPrint("_updateSelectedSpan: setting toolbarMode to wordZoom");
      updateToolbarMode(MessageMode.wordZoom);
    }
    setState(() {});
  }

  /// If sentence TTS is playing a word, highlight that word in message overlay
  void highlightCurrentText(int currentPosition, List<TTSToken> ttsTokens) {
    final List<TTSToken> textToSelect = [];
    // Check if current time is between start and end times of tokens
    for (final TTSToken token in ttsTokens) {
      if (token.endMS > currentPosition) {
        if (token.startMS < currentPosition) {
          textToSelect.add(token);
        } else {
          break;
        }
      }
    }

    if (const ListEquality().equals(textToSelect, _highlightedTokens)) return;
    _highlightedTokens =
        textToSelect.isEmpty ? null : textToSelect.map((t) => t.text).toList();
    setState(() {});
  }

  MessageAnalyticsEntry? get messageAnalyticsEntry =>
      pangeaMessageEvent != null && tokens != null
          ? MatrixState.pangeaController.getAnalytics.perMessage.get(
              tokens!,
              pangeaMessageEvent!,
            )
          : null;

  Future<void> _initializeTokensAndMode() async {
    try {
      final repEvent = pangeaMessageEvent?.messageDisplayRepresentation;
      if (repEvent != null) {
        tokens = await repEvent.tokensGlobal(
          pangeaMessageEvent!.senderId,
          pangeaMessageEvent!.originServerTs,
        );
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "eventID": pangeaMessageEvent?.eventId,
        },
      );
    } finally {
      _initializeSelectedToken();
      _setInitialToolbarMode();
      initialized = true;
      if (mounted) setState(() {});
    }
  }

  bool get messageInUserL2 =>
      pangeaMessageEvent?.messageDisplayLangCode ==
      MatrixState.pangeaController.languageController.userL2?.langCode;

  Future<void> _setInitialToolbarMode() async {
    if (widget._pangeaMessageEvent?.isAudioMessage ?? false) {
      toolbarMode = MessageMode.speechToText;
      return setState(() {});
    }

    // 1) if we have a hidden word activity, then we should start with that
    if (messageAnalyticsEntry?.nextActivity?.activityType ==
        ActivityTypeEnum.hiddenWordListening) {
      return setState(() => toolbarMode = MessageMode.practiceActivity);
    }

    if (selectedToken != null) {
      return setState(() => toolbarMode = MessageMode.wordZoom);
    }

    // Note: this setting is now hidden so this will always be false
    // leaving this here in case we want to bring it back
    // if (MatrixState.pangeaController.userController.profile.userSettings
    //     .autoPlayMessages) {
    //   return setState(() => toolbarMode = MessageMode.textToSpeech);
    // }

    // defaults to noneSelected
  }

  /// We need to check if the setState call is safe to call immediately
  /// Kept getting the error: setState() or markNeedsBuild() called during build.
  /// This is a workaround to prevent that error
  @override
  void setState(VoidCallback fn) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (mounted &&
        (phase == SchedulerPhase.idle ||
            phase == SchedulerPhase.postFrameCallbacks)) {
      // It's safe to call setState immediately
      try {
        super.setState(fn);
      } catch (e, s) {
        ErrorHandler.logError(
          e: "Error calling setState in MessageSelectionOverlay: $e",
          s: s,
          data: {},
        );
      }
    } else {
      // Defer the setState call to after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (mounted) super.setState(fn);
        } catch (e, s) {
          ErrorHandler.logError(
            e: "Error calling setState in MessageSelectionOverlay after postframeCallback: $e",
            s: s,
            data: {},
          );
        }
      });
    }
  }

  /// When an activity is completed, we need to update the state
  /// and check if the toolbar should be unlocked
  void onActivityFinish() {
    messageAnalyticsEntry!.onActivityComplete();
    if (!mounted) return;
    setState(() {});
  }

  /// In some cases, we need to exit the practice flow and let the user
  /// interact with the toolbar without completing activities
  void exitPracticeFlow() {
    messageAnalyticsEntry?.exitPracticeFlow();
    setState(() {});
  }

  void updateToolbarMode(MessageMode mode) {
    setState(() {
      // only practiceActivity and wordZoom make sense with selectedSpan
      if (![MessageMode.practiceActivity, MessageMode.wordZoom]
          .contains(mode)) {
        debugPrint("updateToolbarMode: $mode - clearing selectedSpan");
        _selectedSpan = null;
      }
      if (mode != MessageMode.textToSpeech) {
        _highlightedTokens = null;
      }
      toolbarMode = mode;
    });
  }

  /// The text that the toolbar should target
  /// If there is no selectedSpan, then the whole message is the target
  /// If there is a selectedSpan, then the target is the selected text
  String get targetText {
    if (_selectedSpan == null || pangeaMessageEvent == null) {
      return widget._pangeaMessageEvent?.messageDisplayText ??
          widget._event.body;
    }

    return widget._pangeaMessageEvent!.messageDisplayText.substring(
      _selectedSpan!.offset,
      _selectedSpan!.offset + _selectedSpan!.length,
    );
  }

  void onClickOverlayMessageToken(
    PangeaToken token,
  ) {
    if (toolbarMode == MessageMode.practiceActivity &&
        messageAnalyticsEntry?.nextActivity?.activityType ==
            ActivityTypeEnum.hiddenWordListening) {
      return;
    }

    _updateSelectedSpan(token.text);
    setState(() {});
  }

  /// Whether the given token is currently selected or highlighted
  bool isTokenSelected(PangeaToken token) {
    final isSelected = _selectedSpan?.offset == token.text.offset &&
        _selectedSpan?.length == token.text.length;
    return isSelected;
  }

  bool isTokenHighlighted(PangeaToken token) {
    if (_highlightedTokens == null) return false;
    return _highlightedTokens!.any(
      (t) => t.offset == token.text.offset && t.length == token.text.length,
    );
  }

  PangeaToken? get selectedToken => tokens?.firstWhereOrNull(isTokenSelected);

  /// Whether the overlay is currently displaying a selection
  bool get isSelection => _selectedSpan != null || _highlightedTokens != null;

  PangeaTokenText? get selectedSpan => _selectedSpan;

  void setIsPlayingAudio(bool isPlaying) {
    if (mounted) {
      setState(() => isPlayingAudio = isPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MessageSelectionPositioner(
      overlayController: this,
      chatController: widget.chatController,
      event: widget._event,
      nextEvent: widget._nextEvent,
      prevEvent: widget._prevEvent,
      pangeaMessageEvent: pangeaMessageEvent,
      initialSelectedToken: widget._initialSelectedToken,
    );
  }
}
