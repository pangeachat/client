import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/choreographer/widgets/choice_array.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_representation_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/toolbar/controllers/text_to_speech_controller.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_positioner.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:matrix/matrix.dart';

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
  })  : _initialSelectedToken = initialSelectedToken,
        _nextEvent = nextEvent,
        _prevEvent = prevEvent,
        _event = event,
        _timeline = timeline;

  @override
  MessageOverlayController createState() => MessageOverlayController();
}

class MessageOverlayController extends State<MessageSelectionOverlay>
    with SingleTickerProviderStateMixin {
  Event get event => widget._event;
  /////////////////////////////////////
  /// Variables
  /////////////////////////////////////
  MessageMode toolbarMode = MessageMode.wordEmoji;

  Map<String, LemmaInfoResponse>? messageLemmaInfos;
  List<String> messageEmojisForDisplay = [];
  List<String> selectedEmojis = [];

  List<String> messageMeaningsForDisplay = [];
  String? selectedMeanings;

  List<String> messageWordFormsForDisplay = [];
  String? selectedWordAudioSurfaceForm;

  List<ConstructIdentifier> messageMorphTagsForDisplay = [];
  List<ConstructIdentifier> selectedMorphTags = [];

  PangeaTokenText? _selectedSpan;
  List<PangeaTokenText>? _highlightedTokens;
  bool initialized = false;
  bool isPlayingAudio = false;

  /////////////////////////////////////
  /// Lifecycle
  /////////////////////////////////////

  @override
  void initState() {
    super.initState();
    initializeTokensAndMode();
  }

  Future<void> initializeTokensAndMode() async {
    try {
      RepresentationEvent? repEvent =
          pangeaMessageEvent?.messageDisplayRepresentation;
      repEvent ??= await _fetchNewRepEvent();

      if (repEvent?.event != null) {
        await repEvent!.sendTokensEvent(
          repEvent.event!.eventId,
          widget._event.room,
          MatrixState.pangeaController.languageController.userL1!.langCode,
          MatrixState.pangeaController.languageController.userL2!.langCode,
        );
      }
      // If repEvent is originalSent but it's missing tokens, then fetch tokens.
      // An edge case, but has happened with some bot message.
      else if (repEvent != null &&
          repEvent.tokens == null &&
          repEvent.content.originalSent) {
        final tokens = await repEvent.tokensGlobal(
          pangeaMessageEvent!.senderId,
          pangeaMessageEvent!.event.originServerTs,
        );
        await pangeaMessageEvent!.room.pangeaSendTextEvent(
          pangeaMessageEvent!.messageDisplayText,
          editEventId: pangeaMessageEvent!.eventId,
          originalSent: pangeaMessageEvent!.originalSent?.content,
          originalWritten: pangeaMessageEvent!.originalWritten?.content,
          tokensSent: PangeaMessageTokens(tokens: tokens),
          choreo: pangeaMessageEvent!.originalSent?.choreo,
        );
      }

      await _initializeMeaningsAndEmojis();
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

  Future<void> _initializeMeaningsAndEmojis() async {
    try {
      if (pangeaMessageEvent?.messageDisplayRepresentation?.tokens == null ||
          !(pangeaMessageEvent?.messageDisplayLangIsL2 ?? false)) {
        return;
      }

      final tokensToSave = pangeaMessageEvent!
          .messageDisplayRepresentation!.tokens!
          .where((token) => token.lemma.saveVocab)
          .toList();

      final constructsToFetch =
          tokensToSave.map((e) => e.vocabConstructID).toList();

      final List<Future<LemmaInfoResponse>> emojiFutures =
          constructsToFetch.map((token) => token.getLemmaInfo()).toList();

      final List<LemmaInfoResponse> lemmaInfos =
          await Future.wait(emojiFutures);

      messageLemmaInfos = Map.fromIterables(
        constructsToFetch.map((cId) => cId.string),
        lemmaInfos,
      );

      messageEmojisForDisplay = constructsToFetch
          .where((cId) => cId.userSetEmoji.isEmpty)
          .map((cId) => messageLemmaInfos![cId.string]!.emoji)
          .expand((e) => e)
          .toList()
        ..shuffle();

      messageMeaningsForDisplay = constructsToFetch
          .where(
            (cId) => cId.isActivityProbablyLevelAppropriate(
              ActivityTypeEnum.wordMeaning,
              null,
            ),
          )
          .map((cId) => messageLemmaInfos![cId.string]!.meaning)
          .toList()
        ..shuffle();

      messageWordFormsForDisplay =
          tokensToSave.map((token) => token.text.content).toList()..shuffle();

      messageMorphTagsForDisplay = tokensToSave
          .map((token) => token.morphsThatShouldBePracticed)
          .expand((e) => e)
          .toList()
        ..shuffle();

      debugger(when: kDebugMode);

      setState(() {});
    } catch (e, s) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        data: {
          "message": pangeaMessageEvent?.event.toJson(),
        },
        e: e,
        s: s,
      );
    }
  }

  Future<void> _setInitialToolbarMode() async {
    if (pangeaMessageEvent?.isAudioMessage ?? false) {
      updateToolbarMode(MessageMode.messageTextToSpeech);
      return;
    }

    // 1) if we have a hidden word activity, then we should start with that
    if (messageAnalyticsEntry?.nextActivity?.activityType ==
        ActivityTypeEnum.hiddenWordListening) {
      updateToolbarMode(MessageMode.practiceActivity);
      return;
    }

    if (selectedToken != null) {
      updateToolbarMode(selectedToken!.modeForToken);
      return;
    }

    // Note: this setting is now hidden so this will always be false
    // leaving this here in case we want to bring it back
    // if (MatrixState.pangeaController.userController.profile.userSettings
    //     .autoPlayMessages) {
    //   return setState(() => toolbarMode = MessageMode.textToSpeech);
    // }

    // defaults to noneSelected
  }

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

  /////////////////////////////////////
  /// State setting
  /////////////////////////////////////

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

  /// Update to [selectedSpan]
  /// [forceMode] is used to force a specific mode
  void _updateSelectedSpan(PangeaTokenText selectedSpan) {
    // if (forceMode == null && selectedSpan == _selectedSpan) {
    //   _selectedSpan = null;
    //   updateToolbarMode(MessageMode.noneSelected);
    //   setState(() {});
    //   return;
    // }
    // debugger(
    //   when: kDebugMode,
    // );
    _selectedSpan = selectedSpan;

    // @ggurdin - is this for sure gone?
    // final nextModeForToken = forceMode ?? selectedToken!.modeForToken;
    // if (toolbarMode != nextModeForToken) {
    //   debugPrint("_updateSelectedSpan: setting toolbarMode to wordZoom");
    //   updateToolbarMode(nextModeForToken);
    // }

    setState(() {});
  }

  void updateToolbarMode(MessageMode mode) => setState(() {
        toolbarMode = mode;
      });

  void onMessageEmojiChoiceSelect(String emoji) {
    if (selectedEmojis.contains(emoji)) {
      selectedEmojis.remove(emoji);
    } else {
      selectedEmojis.add(emoji);
    }

    setState(() {});
  }

  void clearSelectedEmoji() {
    selectedEmojis.clear();
    setState(() {});
  }

  void onMessageMeaningChoiceSelect(String meaning) {
    if (selectedMeanings == meaning) {
      selectedMeanings = null;
    } else {
      selectedMeanings = meaning;
    }
    setState(() {});
  }

  void clearSelectedMeaning() {
    selectedMeanings = null;
    setState(() {});
  }

  void onWordAudioChoiceSelect(String form) {
    if (selectedWordAudioSurfaceForm == form) {
      selectedWordAudioSurfaceForm = null;
    } else {
      selectedWordAudioSurfaceForm = form;
    }
    setState(() {});
  }

  void clearSelectedWordAudioSurfaceForm() {
    selectedWordAudioSurfaceForm = null;
    setState(() {});
  }

  void onMorphChoiceSelect(ConstructIdentifier morphTag) {
    if (selectedMorphTags.contains(morphTag)) {
      selectedMorphTags.remove(morphTag);
    } else {
      selectedMorphTags.add(morphTag);
    }
    setState(() {});
  }

  void clearMorphTags() {
    selectedMorphTags = [];
    setState(() {});
  }

  Future<void> onTokenSelectionWithSelectedMeaning(
    PangeaToken token,
    String meaning,
  ) async {
    MatrixState.pangeaController.putAnalytics.setState(
      AnalyticsStream(
        eventId: pangeaMessageEvent!.eventId,
        roomId: pangeaMessageEvent!.room.id,
        constructs: [
          OneConstructUse(
            useType: messageLemmaInfos![token.vocabConstructID.string]!
                        .meaning
                        .toLowerCase() ==
                    meaning.toLowerCase()
                ? ConstructUseTypeEnum.corPA
                : ConstructUseTypeEnum.incPA,
            lemma: token.vocabConstructID.lemma,
            constructType: ConstructTypeEnum.vocab,
            metadata: ConstructUseMetaData(
              roomId: pangeaMessageEvent!.room.id,
              timeStamp: DateTime.now(),
              eventId: pangeaMessageEvent!.eventId,
            ),
            category: token.vocabConstructID.category,
            form: token.text.content,
          ),
        ],
        origin: AnalyticsUpdateOrigin.wordZoom,
      ),
    );

    setState(() => {});

    await Future.delayed(
      const Duration(milliseconds: choiceArrayAnimationDuration),
    );

    messageMeaningsForDisplay.removeWhere((m) => m == meaning);

    setState(() => {});
  }

  Future<void> onTokenSelectionWithSelectedEmojis(
    PangeaToken token,
    List<String> emojis,
  ) async {
    final List<String> correctSelections = emojis
        .where(
          (selectedEmoji) => messageLemmaInfos![token.vocabConstructID.string]!
              .emoji
              .contains(selectedEmoji),
        )
        .toList();

    correctSelections.map(
      (emoji) => MatrixState.pangeaController.putAnalytics.setState(
        AnalyticsStream(
          eventId: pangeaMessageEvent!.eventId,
          roomId: pangeaMessageEvent!.room.id,
          constructs: [
            OneConstructUse(
              useType: ConstructUseTypeEnum.em,
              lemma: token.vocabConstructID.lemma,
              constructType: ConstructTypeEnum.vocab,
              metadata: ConstructUseMetaData(
                roomId: pangeaMessageEvent!.room.id,
                timeStamp: DateTime.now(),
                eventId: pangeaMessageEvent!.eventId,
              ),
              category: token.vocabConstructID.category,
              form: token.text.content,
            ),
          ],
          origin: AnalyticsUpdateOrigin.wordZoom,
        ),
      ),
    );

    setState(() => {});

    await Future.delayed(
      const Duration(milliseconds: choiceArrayAnimationDuration),
    );

    messageEmojisForDisplay
        .removeWhere((emoji) => correctSelections.contains(emoji));

    setState(() => {});
  }

  Future<void> onTokenSelectionWithSelectedAudio(
    PangeaToken token,
    String selectedAudioSurfaceForm,
  ) async {
    final bool isCorrect = token.text.content == selectedAudioSurfaceForm;

    MatrixState.pangeaController.putAnalytics.setState(
      AnalyticsStream(
        eventId: pangeaMessageEvent!.eventId,
        roomId: pangeaMessageEvent!.room.id,
        constructs: [
          OneConstructUse(
            useType: isCorrect
                ? ConstructUseTypeEnum.corWL
                : ConstructUseTypeEnum.incWL,
            lemma: token.vocabConstructID.lemma,
            constructType: ConstructTypeEnum.vocab,
            metadata: ConstructUseMetaData(
              roomId: pangeaMessageEvent!.room.id,
              timeStamp: DateTime.now(),
              eventId: pangeaMessageEvent!.eventId,
            ),
            category: token.vocabConstructID.category,
            form: token.text.content,
          ),
        ],
        origin: AnalyticsUpdateOrigin.wordZoom,
      ),
    );

    setState(() => {});

    await Future.delayed(
      const Duration(milliseconds: choiceArrayAnimationDuration),
    );

    if (isCorrect) {
      messageWordFormsForDisplay
          .removeWhere((form) => form == selectedAudioSurfaceForm);
    }

    setState(() => {});
  }

  /////////////////////////////////////
  /// Getters
  ////////////////////////////////////
  PangeaMessageEvent? get pangeaMessageEvent => PangeaMessageEvent(
        event: widget._event,
        timeline: widget._timeline,
        ownMessage: widget._event.room.client.userID == widget._event.senderId,
      );

  bool get showToolbarButtons =>
      pangeaMessageEvent != null &&
      pangeaMessageEvent!.event.messageType == MessageTypes.Text;

  int get activitiesLeftToComplete => messageAnalyticsEntry?.numActivities ?? 0;

  bool get isPracticeComplete =>
      (pangeaMessageEvent?.proportionOfActivitiesCompleted ?? 1) >= 1 ||
      !messageInUserL2;

  MessageAnalyticsEntry? get messageAnalyticsEntry =>
      pangeaMessageEvent?.messageDisplayRepresentation?.tokens != null
          ? MatrixState.pangeaController.getAnalytics.perMessage.get(
              pangeaMessageEvent!.messageDisplayRepresentation!.tokens!,
              pangeaMessageEvent!,
            )
          : null;

  bool get messageInUserL2 =>
      pangeaMessageEvent?.messageDisplayLangCode ==
      MatrixState.pangeaController.languageController.userL2?.langCode;

  PangeaToken? get selectedToken =>
      pangeaMessageEvent?.messageDisplayRepresentation?.tokens
          ?.firstWhereOrNull(isTokenSelected);

  /// Whether the overlay is currently displaying a selection
  bool get isSelection => _selectedSpan != null || _highlightedTokens != null;

  PangeaTokenText? get selectedSpan => _selectedSpan;

  ///////////////////////////////////
  /// User action handlers
  /////////////////////////////////////
  void onRequestForMeaningChallenge() {
    if (messageAnalyticsEntry == null) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        e: "MessageAnalyticsEntry is null in onRequestForMeaningChallenge",
        data: {},
      );
      return;
    }
    messageAnalyticsEntry!.addMessageMeaningActivity();

    if (mounted) {
      setState(() {});
    }
  }

  // void onNextActivityRequest() {
  //   if (pangeaMessageEvent?.messageDisplayRepresentation?.tokens == null) {
  //     debugger(when: kDebugMode);
  //     ErrorHandler.logError(
  //       e: "Tokens are null in onNextActivityRequest",
  //       data: {},
  //     );
  //     return;
  //   }

  //   for (final token in pangeaMessageEvent!
  //       .messageDisplayRepresentation!.tokens!
  //       .where((t) => t.lemma.saveVocab)) {
  //     final MessageMode nextActivityMode = token.modeForToken;
  //     if (nextActivityMode != MessageMode.wordZoom) {
  //       _selectedSpan = token.text;
  //       _updateSelectedSpan(token.text);
  //       return;
  //     }
  //   }
  // }

  ///////////////////////////////////
  /// Functions
  /////////////////////////////////////

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

  Future<RepresentationEvent?> _fetchNewRepEvent() async {
    final RepresentationEvent? repEvent =
        pangeaMessageEvent?.messageDisplayRepresentation;

    if (repEvent != null) return repEvent;
    final eventID =
        await pangeaMessageEvent?.representationByDetectedLanguage();

    if (eventID == null) return null;
    final event = await widget._event.room.getEventById(eventID);
    if (event == null) return null;
    return RepresentationEvent(
      timeline: pangeaMessageEvent!.timeline,
      parentMessageEvent: pangeaMessageEvent!.event,
      event: event,
    );
  }

  /// When an activity is completed, we need to update the state
  /// and check if the toolbar should be unlocked
  void onActivityFinish(ActivityTypeEnum activityType) {
    messageAnalyticsEntry!.onActivityComplete();

    if (selectedToken == null) {
      updateToolbarMode(MessageMode.noneSelected);
    }

    updateToolbarMode(selectedToken!.modeForToken);

    if (!mounted) return;
    setState(() {});
  }

  /// In some cases, we need to exit the practice flow and let the user
  /// interact with the toolbar without completing activities
  void exitPracticeFlow() {
    messageAnalyticsEntry?.exitPracticeFlow();
    setState(() {});
  }

  void onClickOverlayMessageToken(
    PangeaToken token,
  ) {
    if (messageAnalyticsEntry?.hasHiddenWordActivity == true) {
      return;
    }

    widget.chatController.choreographer.tts.tryToSpeak(
      token.text.content,
      context,
      targetID: null,
    );

    switch (toolbarMode) {
      case MessageMode.wordEmoji:
        if (token.lemma.saveVocab && selectedEmojis.isNotEmpty) {
          onTokenSelectionWithSelectedEmojis(token, selectedEmojis);
        }
        break;
      case MessageMode.wordMeaning:
        if (token.lemma.saveVocab && selectedMeanings != null) {
          onTokenSelectionWithSelectedMeaning(token, selectedMeanings!);
        }
        break;
      case MessageMode.messageTextToSpeech:
        if (token.lemma.saveVocab && selectedWordAudioSurfaceForm != null) {
          onTokenSelectionWithSelectedAudio(
            token,
            selectedWordAudioSurfaceForm!,
          );
        }
      case MessageMode.wordZoom:
        if (token.lemma.saveVocab) {}
        break;
      case MessageMode.wordMorph:
        if (token.lemma.saveVocab) {}
        break;
      case MessageMode.practiceActivity:
      case MessageMode.messageMeaning:
      case MessageMode.messageSpeechToText:
      case MessageMode.messageTranslation:
      case MessageMode.noneSelected:
        break;
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

  void setIsPlayingAudio(bool isPlaying) {
    if (mounted) {
      setState(() => isPlayingAudio = isPlaying);
    }
  }

  /////////////////////////////////////
  /// Build
  /////////////////////////////////////
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
