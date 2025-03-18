import 'dart:async';
import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_misc/message_analytics_controller.dart';
import 'package:fluffychat/pangea/analytics_misc/put_analytics_controller.dart';
import 'package:fluffychat/pangea/choreographer/widgets/choice_array.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_representation_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';
import 'package:fluffychat/pangea/toolbar/controllers/text_to_speech_controller.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_positioner.dart';
import 'package:fluffychat/pangea/toolbar/widgets/reading_assistance_content.dart';
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
  MessageMode toolbarMode = MessageMode.noneSelected;

  Map<ConstructIdentifier, LemmaInfoResponse>? messageLemmaInfos;

  List<String> messageEmojisForDisplay = [];
  List<String> messageMeaningsForDisplay = [];
  List<String> messageWordFormsForDisplay = [];
  List<ConstructIdentifier> messageMorphTagsForDisplay = [];

  List<int> selectedChoices = [];

  PangeaTokenText? _selectedSpan;
  List<PangeaTokenText>? _highlightedTokens;
  bool initialized = false;
  bool isPlayingAudio = false;

  // either a MorphFeatureEnum or a PartOfSpeechEnum
  // String? modeLevel;

  /////////////////////////////////////
  /// Lifecycle
  /////////////////////////////////////

  @override
  void initState() {
    initializeTokensAndMode();
    super.initState();
  }

  Future<void> initializeTokensAndMode() async {
    debugger();
    print("this heck");
    try {
      print("what");
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
      await updateReadingAssistanceInputBarChoices();
    } catch (e, s) {
      debugger(when: kDebugMode);
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

  Future<void> updateReadingAssistanceInputBarChoices() async {
    try {
      if (pangeaMessageEvent?.messageDisplayRepresentation?.tokens == null ||
          !(pangeaMessageEvent?.messageDisplayLangIsL2 ?? false)) {
        debugger(when: kDebugMode);
        return;
      }

      ////Get all the infos
      final messageVocabConstructIds = pangeaMessageEvent!
          .messageDisplayRepresentation!.tokensToSave
          .map((e) => e.vocabConstructID)
          .toList();

      final List<Future<LemmaInfoResponse>> lemmaInfoFutures =
          messageVocabConstructIds
              .map((token) => token.getLemmaInfo())
              .toList();

      final List<LemmaInfoResponse> lemmaInfos =
          await Future.wait(lemmaInfoFutures);

      messageLemmaInfos = Map.fromIterables(
        messageVocabConstructIds,
        lemmaInfos,
      );

      debugger(when: kDebugMode);

      ////Get all the choices
      final List<ConstructIdentifier> vocabConstructIdsByModeLevel =
          messageVocabConstructIds
              // .where((cId) => modeLevel == null || cId.category == modeLevel)
              .toList();

      /// emojis
      messageEmojisForDisplay = [];
      debugPrint("messageLemmaInfos: ${messageLemmaInfos!.length}");
      for (final entry in messageLemmaInfos!.entries) {
        print("entry: ${entry.key.lemma} ${entry.value.emoji}");
        for (final emoji in entry.value.emoji) {
          if (!entry.key.userSetEmoji.contains(emoji)) {
            messageEmojisForDisplay.add(emoji);
          }
        }
      }
      print("messageEmojisForDisplay: ${messageEmojisForDisplay.length}");
      messageEmojisForDisplay.shuffle();

      // messageEmojisForDisplay = vocabConstructIdsByModeLevel
      //     .map(
      //       (cId) => messageLemmaInfos![cId]!
      //           .emoji
      //           .where((e) => !cId.userSetEmoji.contains(e)),
      //     )
      //     .expand((e) => e)
      //     .toList()
      //   ..shuffle();

      /// meanings
      messageMeaningsForDisplay = vocabConstructIdsByModeLevel
          // .where(
          //   (cId) => cId.category.toLowerCase() == modeLevel?.toLowerCase(),
          // )
          .map((cId) => messageLemmaInfos![cId]!.meaning)
          .toList()
        ..shuffle();

      /// word forms
      messageWordFormsForDisplay = pangeaMessageEvent!
          .messageDisplayRepresentation!.tokensToSave
          // .where((token) => token.pos.toLowerCase() == modeLevel?.toLowerCase())
          .map((token) => token.text.content)
          .toList()
        ..shuffle();

      /// morph tags
      messageMorphTagsForDisplay =
          pangeaMessageEvent!.messageDisplayRepresentation!.tokensToSave
              .map((token) => token.morphsThatShouldBePracticed)
              .expand((e) => e)
              // .where(
              //   (cId) => cId.lemma.toLowerCase() == modeLevel?.toLowerCase(),
              // )
              .toList()
            ..shuffle();

      selectedChoices.clear();

      debugger(when: kDebugMode);

      setState(() {});
    } catch (e, s) {
      debugPrint("error but not stopping: $e");

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

  /// Update to [selectedSpan]
  /// [forceMode] is used to force a specific mode
  void _updateSelectedSpan(PangeaTokenText selectedSpan) {
    if (selectedToken != null) {
      MatrixState.pAnyState.disposeByWidgetKey(
        selectedToken!.text.uniqueKey,
      );
    }

    if (selectedSpan == _selectedSpan) {
      _selectedSpan = null;
    } else {
      _selectedSpan = selectedSpan;
    }

    if (selectedToken != null) {
      final entry = ReadingAssistanceContent(
        pangeaMessageEvent: pangeaMessageEvent!,
        overlayController: this,
      );
      OverlayUtil.showPositionedCard(
        context: context,
        cardToShow: entry,
        transformTargetId: selectedToken!.text.uniqueKey,
        closePrevOverlay: false,
        backDropToDismiss: false,
        addBorder: false,
        overlayKey: selectedToken!.text.uniqueKey,
        maxHeight: AppConfig.toolbarMaxHeight,
        maxWidth: AppConfig.toolbarMinWidth,
      );
    }

    setState(() {});
  }

  void updateToolbarMode(MessageMode mode) => setState(() {
        toolbarMode = mode;
      });

  void onChoiceSelect(int choiceIndex) {
    debugPrint("Selected choice: $choiceIndex");
    if (selectedChoices.contains(choiceIndex)) {
      if (selectedToken == null) {
        selectedChoices.remove(choiceIndex);
      }
    } else {
      selectedChoices.add(choiceIndex);
    }
    if (selectedToken != null) {
      switch (toolbarMode) {
        case MessageMode.wordEmoji:
          debugPrint("Selected emoji: ${messageEmojisForDisplay[choiceIndex]}");
          onTokenSelectionWithSelectedEmojis(
            selectedToken!,
            selectedChoices,
          );
          break;
        case MessageMode.wordMeaning:
          onTokenSelectionWithSelectedMeaning(
            selectedToken!,
            messageMeaningsForDisplay[selectedChoices.first],
          );
          break;
        case MessageMode.messageTextToSpeech:
          onTokenSelectionWithSelectedAudio(
            selectedToken!,
            messageWordFormsForDisplay[selectedChoices.first],
          );
          break;
        case MessageMode.wordMorph:
          onTokenSelectionWithSelectedMorphs(
            selectedToken!,
            selectedChoices
                .map((index) => messageMorphTagsForDisplay[index])
                .toList(),
          );
          break;
        default:
          debugger(when: kDebugMode);
          break;
      }
    }

    setState(() {});
  }

  void clearSelectedEmoji() {
    selectedChoices.clear();
    setState(() {});
  }

  // void onChoiceLevelSelection(String choiceLevel) {
  //   modeLevel = choiceLevel;

  //   _updateReadingAssistanceInputBarChoices();

  //   debugPrint("modeLevel is now: $modeLevel");
  //   setState(() {});
  // }

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
            useType: messageLemmaInfos![token.vocabConstructID]!
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

  Future<void> onTokenSelectionWithSelectedMorphs(
    PangeaToken token,
    List<ConstructIdentifier> morphs,
  ) async {
    for (final morph in morphs) {
      MatrixState.pangeaController.putAnalytics.setState(
        AnalyticsStream(
          eventId: pangeaMessageEvent!.eventId,
          roomId: pangeaMessageEvent!.room.id,
          constructs: [
            OneConstructUse(
              useType: token.hasMorph(morph)
                  ? ConstructUseTypeEnum.corM
                  : ConstructUseTypeEnum.incM,
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
    }

    setState(() => {});

    await Future.delayed(
      const Duration(milliseconds: choiceArrayAnimationDuration),
    );

    messageMorphTagsForDisplay.removeWhere((m) => morphs.contains(m));

    setState(() => {});
  }

  Future<void> onTokenSelectionWithSelectedEmojis(
    PangeaToken token,
    List<int> emojisIndices,
  ) async {
    final List<int> correctPlacements = emojisIndices
        .where(
          (selectedEmoji) => messageLemmaInfos![token.vocabConstructID]!
              .emoji
              .contains(messageEmojisForDisplay[selectedEmoji]),
        )
        .toList();

    correctPlacements.map(
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

    token.vocabConstructID
        .setUserLemmaInfo(
          UserSetLemmaInfo(
            emojis: token.vocabConstructID.userSetEmoji +
                correctPlacements
                    .map((emoji) => messageEmojisForDisplay[emoji])
                    .toList(),
          ),
        )
        .then((_) => setState(() {}));

    // find the correct place for the incorrect selections and place them
    if (messageLemmaInfos != null) {
      for (final emojiIndex in emojisIndices
          .where((index) => !correctPlacements.contains(index))) {
        final emoji = messageEmojisForDisplay[emojiIndex];
        for (final lemma in messageLemmaInfos!.entries) {
          if (lemma.value.emoji.contains(emoji) &&
              !lemma.key.userSetEmoji.contains(emoji)) {
            lemma.key
                .setUserLemmaInfo(
                  UserSetLemmaInfo(
                    emojis: lemma.key.userSetEmoji +
                        [messageEmojisForDisplay[emojiIndex]],
                  ),
                )
                .then((onValue) => setState(() {}));
            break;
          } else {
            debugger(when: kDebugMode);
            continue;
          }
        }
      }
    } else {
      debugger(when: kDebugMode);
    }

    setState(() => {});

    await Future.delayed(
      const Duration(milliseconds: 2000),
    );

    selectedChoices.clear();

    updateReadingAssistanceInputBarChoices();

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
      const Duration(milliseconds: 2000),
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

  /// you have to complete one of the mode mini-games to unlock translation
  bool get isTranslationUnlocked =>
      !messageInUserL2 ||
      (messageEmojisForDisplay.isEmpty ||
          (messageLemmaInfos?.isEmpty ?? false) ||
          messageMeaningsForDisplay.isEmpty ||
          messageWordFormsForDisplay.isEmpty ||
          messageMorphTagsForDisplay.isEmpty);

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

  // // void onNextActivityRequest() {
  // //   if (pangeaMessageEvent?.messageDisplayRepresentation?.tokens == null) {
  // //     debugger(when: kDebugMode);
  // //     ErrorHandler.logError(
  // //       e: "Tokens are null in onNextActivityRequest",
  // //       data: {},
  // //     );
  // //     return;
  // //   }

  // //   for (final token in pangeaMessageEvent!
  // //       .messageDisplayRepresentation!.tokens!
  // //       .where((t) => t.lemma.saveVocab)) {
  // //     final MessageMode nextActivityMode = token.modeForToken;
  // //     if (nextActivityMode != MessageMode.wordZoom) {
  // //       _selectedSpan = token.text;
  // //       _updateSelectedSpan(token.text);
  // //       return;
  // //     }
  // //   }
  // // }

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

    if (selectedChoices.isNotEmpty && token.lemma.saveVocab) {
      switch (toolbarMode) {
        case MessageMode.wordEmoji:
          onTokenSelectionWithSelectedEmojis(token, selectedChoices);
          break;
        case MessageMode.wordMeaning:
          final String selectedMeaning =
              messageMeaningsForDisplay[selectedChoices.first];
          onTokenSelectionWithSelectedMeaning(token, selectedMeaning);
          break;
        case MessageMode.messageTextToSpeech:
          final String selectedWordAudioSurfaceForm =
              messageWordFormsForDisplay[selectedChoices.first];
          onTokenSelectionWithSelectedAudio(
            token,
            selectedWordAudioSurfaceForm,
          );
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
      selectedChoices.clear();
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
