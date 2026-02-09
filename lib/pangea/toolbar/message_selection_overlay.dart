import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_representation_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/text_to_speech/text_to_speech_response_model.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/pangea/toolbar/layout/message_selection_positioner.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/practice_controller.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_buttons.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/select_mode_controller.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/tokens_util.dart';
import 'package:fluffychat/pangea/toolbar/token_rendering_mixin.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Controls data at the top level of the toolbar (mainly token / toolbar mode selection)
class MessageSelectionOverlay extends StatefulWidget {
  final ChatController chatController;
  final Event _event;
  final Event? _nextEvent;
  final Event? _prevEvent;
  final PangeaToken? _initialSelectedToken;
  final Timeline _timeline;

  const MessageSelectionOverlay({
    required this.chatController,
    required Event event,
    required PangeaToken? initialSelectedToken,
    required Event? nextEvent,
    required Event? prevEvent,
    required Timeline timeline,
    super.key,
  }) : _initialSelectedToken = initialSelectedToken,
       _nextEvent = nextEvent,
       _prevEvent = prevEvent,
       _event = event,
       _timeline = timeline;

  @override
  MessageOverlayController createState() => MessageOverlayController();
}

class MessageOverlayController extends State<MessageSelectionOverlay>
    with SingleTickerProviderStateMixin, AnalyticsUpdater, TokenRenderingMixin {
  Event get event => widget._event;

  PangeaTokenText? _selectedSpan;
  ValueNotifier<PangeaToken?> selectedTokenNotifier = ValueNotifier(null);

  List<PangeaTokenText>? _highlightedTokens;

  double maxWidth = AppConfig.toolbarMinWidth;

  late SelectModeController selectModeController;
  ValueNotifier<SelectMode?> get selectedMode =>
      selectModeController.selectedMode;

  late PracticeController practiceController;
  double? screenWidth;

  /////////////////////////////////////
  /// Lifecycle
  /////////////////////////////////////

  @override
  void initState() {
    super.initState();
    selectModeController = SelectModeController(pangeaMessageEvent);
    practiceController = PracticeController(pangeaMessageEvent);
    _initializeTokensAndMode();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.chatController.setSelectedEvent(event),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newWidth = MediaQuery.widthOf(context);
    if (screenWidth != null && screenWidth != newWidth) {
      widget.chatController.clearSelectedEvents();
      return;
    }
    screenWidth = newWidth;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.chatController.clearSelectedEvents(),
    );
    selectModeController.dispose();
    practiceController.dispose();
    selectedTokenNotifier.dispose();
    super.dispose();
  }

  Future<void> _initializeTokensAndMode() async {
    try {
      if (pangeaMessageEvent.event.messageType != MessageTypes.Text) {
        return;
      }

      RepresentationEvent? repEvent =
          pangeaMessageEvent.messageDisplayRepresentation;

      if (repEvent == null ||
          (repEvent.event == null && repEvent.tokens == null)) {
        repEvent = await _fetchNewRepEvent();
      }

      if (repEvent?.event != null) {
        await repEvent!.requestTokens();
      }
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"eventID": pangeaMessageEvent.eventId},
      );
    } finally {
      _initializeSelectedToken();
      if (mounted) setState(() {});
    }
  }

  void _initializeSelectedToken() => widget._initialSelectedToken != null
      ? updateSelectedSpan(widget._initialSelectedToken!.text)
      : null;

  /////////////////////////////////////
  /// State setting
  /////////////////////////////////////

  /// We need to check if the setState call is safe to call immediately
  /// Kept getting the error: setState() or markNeedsBuild() called during build.
  /// This is a workaround to prevent that error
  @override
  void setState(VoidCallback fn) {
    // if (pangeaMessageEvent != null) {
    //   debugger(when: kDebugMode);
    //   modeLevel = toolbarMode.currentChoiceMode(this, pangeaMessageEvent!);
    // } else {
    //   debugger(when: kDebugMode);
    // }

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

  /// Update [selectedSpan]
  void updateSelectedSpan(PangeaTokenText? selectedSpan) {
    if (MatrixState.pangeaController.subscriptionController.isSubscribed ==
        false) {
      return;
    }

    if (selectedSpan == _selectedSpan) {
      selectModeController.setPlayingToken(selectedToken?.text);
      return;
    }

    _selectedSpan = selectedSpan;
    selectedTokenNotifier.value = selectedToken;
    selectModeController.setPlayingToken(selectedToken?.text);

    if (selectedToken != null &&
        selectModeController.selectedMode.value != SelectMode.audio) {
      TtsController.tryToSpeak(
        selectedToken!.text.content,
        langCode: pangeaMessageEvent.messageDisplayLangCode,
      );
    }

    if (!mounted) return;
    if (selectedToken != null && isNewToken(selectedToken!)) {
      final token = selectedToken!;
      collectNewToken(
        event.eventId,
        "word-zoom-card-${token.text.uniqueKey}",
        token,
        Matrix.of(context).analyticsDataService,
        roomId: event.room.id,
        eventId: event.eventId,
      ).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    setState(() {});
  }

  PangeaMessageEvent get pangeaMessageEvent => PangeaMessageEvent(
    event: widget._event,
    timeline: widget._timeline,
    ownMessage: widget._event.room.client.userID == widget._event.senderId,
  );

  PangeaToken? get selectedToken {
    if (pangeaMessageEvent.isAudioMessage == true) {
      final stt = pangeaMessageEvent.getSpeechToTextLocal();
      if (stt == null || stt.transcript.sttTokens.isEmpty) return null;
      return stt.transcript.sttTokens
          .firstWhereOrNull((t) => isTokenSelected(t.token))
          ?.token;
    }

    return pangeaMessageEvent.messageDisplayRepresentation?.tokens
        ?.firstWhereOrNull(isTokenSelected);
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
    _highlightedTokens = textToSelect.isEmpty
        ? null
        : textToSelect.map((t) => t.text).toList();
    setState(() {});
  }

  Future<RepresentationEvent?> _fetchNewRepEvent() async {
    final RepresentationEvent? repEvent =
        pangeaMessageEvent.messageDisplayRepresentation;

    if (repEvent != null) return repEvent;
    final eventID = await pangeaMessageEvent
        .requestRepresentationByDetectedLanguage();

    if (eventID == null) return null;
    final event = await widget._event.room.getEventById(eventID);
    if (event == null) return null;
    return RepresentationEvent(
      timeline: pangeaMessageEvent.timeline,
      parentMessageEvent: pangeaMessageEvent.event,
      event: event,
    );
  }

  void onClickOverlayMessageToken(PangeaToken token) =>
      updateSelectedSpan(token.text);

  /// Whether the given token is currently selected or highlighted
  bool isTokenSelected(PangeaToken token) {
    final isSelected =
        _selectedSpan?.offset == token.text.offset &&
        _selectedSpan?.length == token.text.length;
    return isSelected;
  }

  bool isNewToken(PangeaToken token) =>
      TokensUtil.isNewTokenByEvent(token, pangeaMessageEvent);

  bool isTokenHighlighted(PangeaToken token) {
    if (_highlightedTokens == null) return false;
    return _highlightedTokens!.any(
      (t) => t.offset == token.text.offset && t.length == token.text.length,
    );
  }

  String tokenEmojiPopupKey(PangeaToken token) =>
      "${token.uniqueId}_${event.eventId}_emoji_button";

  @override
  Widget build(BuildContext context) {
    return MessageSelectionPositioner(
      overlayController: this,
      chatController: widget.chatController,
      event: widget._event,
      nextEvent: widget._nextEvent,
      prevEvent: widget._prevEvent,
      initialSelectedToken: widget._initialSelectedToken,
    );
  }
}
