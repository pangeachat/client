import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:async/async.dart' as async;
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/analytics_updater_mixin.dart';
import 'package:fluffychat/features/bot/bot_event_extension.dart';
import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/join_codes/join_rule_extension.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/navigation/panel_focus.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/room_close_location.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/overlay/layer_link_and_key.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/features/overlay/overlay_position.dart';
import 'package:fluffychat/features/overlay/transparent_backdrop.dart';
import 'package:fluffychat/features/subscription/widgets/paywall_card.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_model.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_sequences.dart';
import 'package:fluffychat/features/tutorials/tutorial_step_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/pangea/morphs/morph_icon.dart';
import 'package:fluffychat/pangea/spaces/load_participants_builder.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/chat/chat_view.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/goal_star_animation.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/suggestion_card.dart';
import 'package:fluffychat/routes/chat/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/routes/chat/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/span_card.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/writing_asssitance_popup_manager.dart';
import 'package:fluffychat/routes/chat/choreographer/text_editing/edit_type_enum.dart';
import 'package:fluffychat/routes/chat/choreographer/text_editing/pangea_text_controller.dart';
import 'package:fluffychat/routes/chat/choreographer/writing_assistance_room_extension.dart';
import 'package:fluffychat/routes/chat/event_info_dialog.dart';
import 'package:fluffychat/routes/chat/event_too_large_dialog.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/representation_content_model.dart';
import 'package:fluffychat/routes/chat/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_repo.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_request_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/stt_token_enrichment.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/show_token_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/routes/chat/growth_animation.dart';
import 'package:fluffychat/routes/chat/message_analytics_feedback.dart';
import 'package:fluffychat/routes/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/routes/chat/toolbar/message_practice/message_practice_mode_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/routes/chat/voice_analytics_feedback.dart';
import 'package:fluffychat/routes/settings/settings_learning/disable_language_tools_popup.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_repo.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/multi_platform_audio_player.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:fluffychat/widgets/star_rain_widget.dart';
import '../../utils/localized_exception_extension.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

// #Pangea
// Pangea#

// #Pangea
class _TimelineUpdateNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

/// Serializes [ChatController._getTimeline] across every chat controller. A
/// focus swap can suspend the outgoing room and load the incoming room in the
/// same frame; running two `room.getTimeline` calls at once is unsafe because
/// `getTimeline` overwrites the shared `room.timeline`. Each controller awaits
/// any in-flight load before starting its own. See `routing.instructions.md`.
Completer<void>? _getTimelineGate;
// Pangea#

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;

  // #Pangea
  final Widget? backButton;
  // Pangea#

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
    // #Pangea
    this.backButton,
    // Pangea#
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    // #Pangea
    if (room?.isSpace == true &&
        GoRouterState.of(context).fullPath?.endsWith(":roomid") == true) {
      ErrorHandler.logError(
        e: "Space chat opened",
        s: StackTrace.current,
        data: {"roomId": roomId},
      );
      NavigationUtil.goToSpaceRoute(null, [], context);
    }

    if (room == null) {
      // if (room == null) {
      // Pangea#
      return Scaffold(
        appBar: AppBar(leading: backButton),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              L10n.of(context).youAreNoLongerParticipatingInThisChat,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
      // #Pangea
      backButton: backButton,
      // Pangea#
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final List<ShareItem>? shareItems;
  final String? eventId;

  // #Pangea
  final Widget? backButton;
  // Pangea#

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareItems,
    this.eventId,
    // #Pangea
    this.backButton,
    // Pangea#
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver, AnalyticsUpdater {
  // #Pangea
  final PangeaController pangeaController = MatrixState.pangeaController;
  late Choreographer choreographer;
  late GoRouter _router;

  StreamSubscription? _constructsSubscription;
  StreamSubscription? _tokensSubscription;

  StreamSubscription? _botAudioSubscription;
  StreamSubscription? _readingAssistanceTutorialSubscription;

  StreamSubscription? _forwardTutorialSubscription;
  StreamSubscription? _goBackTutorialSubscription;

  StreamSubscription? _goalCompletionSubscription;
  StreamSubscription? _activityRolesSubscription;

  late final ValueNotifier<ActivityRoleGoal?> activeGoalNotifier;

  /// The event used to start the reading-assistance tutorial. Stored so the
  /// tutorial can be re-opened when the user navigates back through the sequence.
  Event? _tutorialEvent;
  PangeaToken? tutorialToken;

  final timelineUpdateNotifier = _TimelineUpdateNotifier();
  late final ActivityChatController activityController;
  late final TutorialOverlayController tutorialOverlayController;
  late final WritingAssistancePopupManager _spanCardOverlayController;
  final ValueNotifier<bool> scrollableNotifier = ValueNotifier(false);
  // Pangea#
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  /// True while this room's timeline subscriptions are cancelled but the
  /// controller stays mounted (the panel lost focus without being removed). On
  /// refocus the timeline is reloaded. See [_suspendTimeline]/[_resumeTimeline].
  bool _timelineSuspended = false;

  /// True while a [_getTimeline] load is in flight (including waiting on the
  /// serialization gate), so [_resumeTimeline] won't queue a duplicate load on
  /// top of the initial one when focus is published just after mount.
  bool _timelineLoading = false;

  String? activeThreadId;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  // #Pangea
  // bool dragging = false;

  // void onDragEntered(dynamic _) => setState(() => dragging = true);

  // void onDragExited(dynamic _) => setState(() => dragging = false);

  // void onDragDone(DropDoneDetails details) async {
  //   setState(() => dragging = false);
  //   if (details.files.isEmpty) return;

  //   await showAdaptiveDialog(
  //     context: context,
  //     builder: (c) => SendFileDialog(
  //       files: details.files,
  //       room: room,
  //       outerContext: context,
  //       threadRootEventId: activeThreadId,
  //       threadLastEventId: threadLastEventId,
  //     ),
  //   );
  // }
  String? get tutorialTokenTargetKey =>
      _tutorialEvent != null && tutorialToken != null
      ? tutorialToken!.overlayTargetKey(_tutorialEvent!.eventId)
      : null;
  // Pangea#

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  // #Pangea
  // Event? replyEvent;

  // Event? editEvent;

  ValueNotifier<Event?> replyEvent = ValueNotifier(null);
  ValueNotifier<Event?> editEvent = ValueNotifier(null);
  // Pangea#

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

  String? get threadLastEventId {
    final threadId = activeThreadId;
    if (threadId == null) return null;
    return timeline?.events
        .filterByVisibleInGui(threadId: threadId)
        .firstOrNull
        ?.eventId;
  }

  void enterThread(String eventId) => setState(() {
    activeThreadId = eventId;
    selectedEvents.clear();
  });

  void closeThread() => setState(() {
    activeThreadId = null;
    selectedEvents.clear();
  });

  void recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  void leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (success.error != null) return;
    // #Pangea
    // context.go('/rooms');
    _closeLeftRoom();
    // Pangea#
  }

  /// Close ONLY the left room's token after the user leaves it — the rest of
  /// the workspace, notably the chat list, survives (#7561). Falls back to the
  /// bare exit when the room isn't open as a token (a pushed route).
  void _closeLeftRoom() => closeOwnRoomPanel(context, room.id);

  // #Pangea
  // void requestHistory([dynamic _]) async {
  Future<void> requestHistory() async {
    if (timeline == null) return;
    if (!timeline!.canRequestHistory) return;
    if (room.membership != Membership.join) return;
    // Pangea#
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  void requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    Logs().v('Requesting future...');

    final mostRecentEvent = timeline.events.filterByVisibleInGui().firstOrNull;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final index = timeline.events.filterByVisibleInGui().indexOf(
          mostRecentEvent,
        );
        if (index >= 0) {
          scrollController.scrollToIndex(
            index,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
    }
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    // #Pangea
    // if (timeline?.allowNewEvent == false ||
    //     scrollController.position.pixels > 0 && _scrolledUp == false) {
    //   setState(() => _scrolledUp = true);
    // } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
    //   setState(() => _scrolledUp = false);
    //   setReadMarker();
    // }
    // Pangea#
  }

  void _loadDraft() async {
    final prefs = Matrix.of(context).store;
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      // #Pangea
      // sendController.text = draft;
      sendController.setSystemText(draft, EditTypeEnum.other);
      // Pangea#
    }
  }

  void _shareItems([dynamic _]) {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      // #Pangea
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
        assertive: true,
      );
      // Pangea#
      return;
    }
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) room.sendEvent(item.value);
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        // #Pangea
        // send();
        onInputBarSubmitted();
        // Pangea#
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);

    scrollController.addListener(_updateScrollController);
    // #Pangea
    // inputFocus.addListener(_inputFocusListener);
    // Pangea#

    // #Pangea
    // _loadDraft();
    // Pangea#
    WidgetsBinding.instance.addPostFrameCallback(_shareItems);
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    sendingClient = Matrix.of(context).client;
    final lastEventThreadId =
        room.lastEvent?.relationshipType == RelationshipTypes.thread
        ? room.lastEvent?.relationshipEventId
        : null;
    readMarkerEventId = room.hasNewMessages
        ? lastEventThreadId ?? room.fullyRead
        : '';
    WidgetsBinding.instance.addObserver(this);
    // #Pangea
    // Learn "am I the focused left panel" from the shell's focus signal instead
    // of subscribing to every route change (which used to tear the chat down on
    // unrelated left-navigation). Registered on the global singleton, so no
    // BuildContext is needed and it can't double-subscribe via
    // didChangeDependencies.
    PanelFocusController.instance.addListener(_onFocusChanged);
    // Pangea#
    _tryLoadTimeline();
    // #Pangea
    _pangeaInit();
    _loadDraft();
    // Pangea#
  }

  // #Pangea
  // The level-up top-down snackbar is gone (#7432): level-ups now celebrate
  // at the level badge itself via [LevelUpBadgeCelebration], which the badge
  // surfaces (world cluster, analytics bar, chat app-bar avatar) subscribe to
  // the same `levelUpdateStream` this page used to consume.
  void _onUnlockConstructs(UnlockedConstructsUpdate update) {
    final constructs = update.constructs;
    final targetId = update.targetId;

    if (constructs.isEmpty || targetId == null) return;
    for (final construct in constructs) {
      GrowthAnimation.show(
        context,
        targetId,
        "${targetId}_unlocked_${construct.string}",
        MorphIcon(
          feature: MorphFeaturesEnum.fromString(construct.category),
          tag: construct.lemma,
          size: Size(24.0, 24.0),
        ),
      );
    }
  }

  void _onTokenUpdate(Set<ConstructIdentifier> constructs) {
    if (constructs.isEmpty) return;
    TokensUtil.instance.clearNewTokenCache();
  }

  Future<void> _botAudioListener(SyncUpdate update) async {
    if (update.rooms?.join?[roomId]?.timeline?.events == null) return;
    final timeline = update.rooms!.join![roomId]!.timeline!;
    final botAudioEvent = timeline.events!.firstWhereOrNull(
      (e) =>
          e.senderId == BotName.byEnvironment &&
          e.content.tryGet<String>('msgtype') == MessageTypes.Audio &&
          DateTime.now().difference(e.originServerTs) <
              const Duration(seconds: 10),
    );
    if (botAudioEvent == null) return;

    final matrix = Matrix.of(context);
    if (matrix.voiceMessageEventId.value != null) return;

    matrix.voiceMessageEventId.value = botAudioEvent.eventId;
    matrix.audioPlayer?.dispose();
    matrix.audioPlayer = AudioPlayer();

    final event = Event.fromMatrixEvent(botAudioEvent, room);
    final audioFile = await event.getPangeaAudioFile();
    if (audioFile == null) return;

    final player = MultiPlatformAudioPlayer(
      audioPlayer: matrix.audioPlayer!,
      bytes: audioFile.bytes,
      name: audioFile.name,
      mimeType: audioFile.mimeType,
    );

    await player.setAudioSourceAndPlay();
  }

  void _readingAssistanceTutorialListener(SyncUpdate update) {
    if (!_canLaunchTutorialSequence) return;

    final timeline = this.timeline;
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    if (timeline == null || l2 == null) return;

    final latestEvent = update.rooms?.join?[roomId]?.timeline?.events
        ?.firstWhereOrNull(
          (event) => event.eventId == timeline.events.firstOrNull?.eventId,
        );
    if (latestEvent == null) return;

    final event = Event.fromMatrixEvent(latestEvent, room);
    if (event.type != EventTypes.Message) return;
    if (event.messageType != MessageTypes.Text) return;
    if (event.redacted || !event.status.isSynced) return;

    final pangeaMessageEvent = PangeaMessageEvent(
      event: event,
      timeline: timeline,
      ownMessage: event.senderId == Matrix.of(context).client.userID,
    );

    final msgLang = pangeaMessageEvent.originalSent?.langCode.split('-').first;

    if (msgLang != l2) return;

    final newTokens = TokensUtil.instance.getNewTokensByEvent(
      pangeaMessageEvent,
    );
    if (newTokens.isEmpty) return;
    final newTokenText = newTokens.first;
    final token = pangeaMessageEvent.originalSent?.tokens?.firstWhereOrNull(
      (t) => newTokenText == t.text,
    );
    if (token == null) return;

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startAssistanceTutorialSequence(event, token),
    );
  }

  void _writingAssistanceTutorialListener(TutorialEnum? tutorial) {
    if (tutorial != TutorialEnum.writingAssistance) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _launchWritingAssistanceTutorial(),
    );
  }

  /// Called when the user navigates back across a tutorial-model boundary.
  /// Re-prepares the required UI state and re-opens the appropriate tutorial
  /// at its last step.
  Future<void> _goBackTutorialListener(TutorialEnum? tutorial) async {
    if (!mounted) return;
    if (tutorial == null) return;

    switch (tutorial) {
      case TutorialEnum.readingAssistance:
        final event = _tutorialEvent;
        final token = tutorialToken;
        if (event == null || token == null) return;
        // Hide the toolbar (if open) before re-showing the reading-assistance
        // tutorial which points at the message bubble itself.
        clearSelectedEvents();
        await Future.delayed(FluffyThemes.animationDuration);
        if (!mounted) return;
        _relaunchReadingAssistanceTutorial(event, token);
        return;
      case TutorialEnum.selectModeButtons:
        final event = _tutorialEvent;
        final token = tutorialToken;
        if (event == null) return;
        // Re-open the toolbar so SelectModeButtons mounts and picks up the queued tutorial.
        showToolbar(event, bypassBlockingOverlays: true, selectedToken: token);
        return;
      case TutorialEnum.writingAssistance:
        // The writing-assistance tutorial starts from the text input which is
        // always visible, so no extra state preparation is needed.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _launchWritingAssistanceTutorial(),
        );
        return;
    }
  }

  void _launchReadingAssistanceTutorial(Event event, PangeaToken token) {
    inputFocus.unfocus();
    _tutorialEvent = event;
    tutorialToken = token;

    tutorialOverlayController.launchTutorial(
      context: context,
      tutorial: ReadingAssistantTutorialModel(
        data: [
          TutorialStepData(
            targetKey: event.eventId,
            onTap: () async {
              showToolbar(event, bypassBlockingOverlays: true);
            },
            canShowNextStep: () => isToolbarOpen,
          ),
        ],
      ),
      isFocused: isFocused,
    );
  }

  void _launchWritingAssistanceTutorial() {
    tutorialOverlayController.launchTutorial(
      context: context,
      tutorial: WritingAssistantTutorialModel(
        data: [
          TutorialStepData(
            targetKey: ChoreoConstants.inputTransformTargetKey,
            onTap: () async => inputFocus.requestFocus(),
            canShowNextStep: () => true,
          ),
        ],
      ),
      isFocused: isFocused,
    );
  }

  void _relaunchReadingAssistanceTutorial(Event event, PangeaToken token) {
    _launchReadingAssistanceTutorial(event, token);
  }

  void _activityConfettiListener() {
    if (activityController.confettiNotifier.value) {
      final renderBox = context.findRenderObject();
      if (renderBox != null) {
        final box = renderBox as RenderBox;
        final offset = box.localToGlobal(Offset.zero);
        Logs().w("Chat context size: ${box.size}. Offset: $offset");
      }
      StarRainWidget.show(context, "star-rain-${widget.room.id}");
    }
  }

  void _activityRolesListener() {
    if (activeGoalNotifier.value != null || room.currentGoal == null) return;
    activeGoalNotifier.value = room.currentGoal;
  }

  Future<void> _goalCompletionListener(Set<ActivityRoleGoal> goals) async {
    if (goals.isEmpty) return;

    final visibleGoal =
        activeGoalNotifier.value ?? room.ownRole?.allGoals.lastOrNull;

    if (visibleGoal == null) {
      activeGoalNotifier.value = room.currentGoal;
      return;
    }

    final completer = Completer();
    GoalStarAnimation.show(
      context,
      overlayKey: "goal-completion-star-${widget.room.id}",
      startTarget: ChoreoConstants.inputTransformTargetKey,
      endTarget: ActivitySessionConstants.goalMenuStarTargetId(visibleGoal.id),
      onClose: () => completer.complete(),
    );

    await completer.future.timeout(
      Duration(seconds: 15),
      onTimeout: () => ErrorHandler.logError(
        e: "Goal completion star animation timeout",
        data: {},
        level: SentryLevel.warning,
      ),
    );

    activeGoalNotifier.value = room.currentGoal;
  }

  /// Whether this chat is the focused/active surface right now. The shell
  /// publishes the one live left panel's token via [PanelFocusController] — a
  /// `room:` OR a `session:` token — and this matches by **bare room id**, so a
  /// completed-activity `session` review (a `session` token over its analytics
  /// list) is focused exactly like a live `room` chat; matching the full token
  /// type instead would leave a session permanently unfocused (frozen timeline,
  /// dead reading-assistance toolbar). Until navigation is fully `?left=`-driven
  /// (Phase 3+), a chat may still open as the route-driven center detail with no
  /// token, so fall back to the legacy route match; `_router` and this fallback
  /// retire once that migration completes. See `panel_focus.dart`.
  bool get isFocused {
    final focused = PanelFocusController.instance.focusedLeftToken;
    final fallback = _router.state.path == ':roomid';
    if (focused == null) {
      return fallback;
    }

    try {
      final panel = PanelToken.parse(focused);
      final param = panel?.param;
      if (param is! RoomTokenParam) return false;
      return shortRoomId(param.id) == shortRoomId(room.id);
    } catch (e) {
      return fallback;
    }
  }

  bool get _canLaunchTutorialSequence {
    if (tutorialOverlayController.state.hasCompletedSequence) {
      return false;
    }

    if (scrollController.hasClients) {
      return scrollController.position.pixels == 0;
    }

    return true;
  }

  void _startAssistanceTutorialSequence(Event event, PangeaToken token) {
    if (!_canLaunchTutorialSequence) return;
    if (tutorialOverlayController.isTutorialQueued(
      TutorialEnum.readingAssistance,
    )) {
      _launchReadingAssistanceTutorial(event, token);
    }
  }

  void _pangeaInit() {
    choreographer = Choreographer(inputFocus: inputFocus, room: room);
    sendController.addListener(onInputBarChanged);
    final updater = Matrix.of(context).analyticsDataService.updateDispatcher;

    _spanCardOverlayController = WritingAssistancePopupManager(
      choreographer: choreographer,
      onFeedbackSubmitted: onWritingAssistanceFeedback,
    );

    _constructsSubscription?.cancel();
    _constructsSubscription = updater.unlockedConstructsStream.stream.listen(
      _onUnlockConstructs,
    );

    _tokensSubscription?.cancel();
    _tokensSubscription = updater.newConstructsStream.stream.listen(
      _onTokenUpdate,
    );

    _botAudioSubscription?.cancel();
    _botAudioSubscription = room.client.onSync.stream.listen(_botAudioListener);

    _readingAssistanceTutorialSubscription?.cancel();
    _readingAssistanceTutorialSubscription = room.client.onSync.stream.listen(
      _readingAssistanceTutorialListener,
    );

    activityController = ActivityChatController(
      userID: Matrix.of(context).client.userID!,
      room: room,
      inputFocus: inputFocus,
    );

    activityController.confettiNotifier.addListener(_activityConfettiListener);
    if (activityController.hasSummary) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        activityController.showConfetti();
      });
    }

    activeGoalNotifier = ValueNotifier(room.currentGoal);

    // Re-fetch the localized activity plan once on session open. The plan cache
    // keys on the canonical version, which a re-translation does NOT bump, so a
    // client holding a cached plan would otherwise never see updated goal text /
    // role names until the TTL lapses. Scoped to room open (not the per-getter
    // read, which the world map calls for every room) and stale-while-revalidate
    // so the visible plan never flickers.
    final activitySessionId = room.activityId;
    if (activitySessionId != null) {
      // Revalidate pinned to the session's version: this refreshes the
      // re-translation of the pinned version (goal text / role names) without
      // pulling newer canonical content into a live pinned session.
      ActivityPlanRepo.instance.ensure(
        activitySessionId,
        version: room.pinnedActivityVersionId,
        revalidate: true,
      );
    }

    _goalCompletionSubscription?.cancel();
    _goalCompletionSubscription = choreographer
        .orchestratorController
        .goalCompletionStream
        .stream
        .listen(_goalCompletionListener);

    _activityRolesSubscription?.cancel();
    _activityRolesSubscription = room.client.onRoomState.stream
        .where(
          (event) =>
              event.roomId == room.id &&
              event.state.type == PangeaEventTypes.activityRole,
        )
        .listen((_) => _activityRolesListener());

    tutorialOverlayController = TutorialOverlayController(
      TutorialSequences.chatTutorialSequence,
    );

    _forwardTutorialSubscription?.cancel();
    _forwardTutorialSubscription = tutorialOverlayController
        .forwardTutorialStream
        .listen(_writingAssistanceTutorialListener);

    _goBackTutorialSubscription?.cancel();
    _goBackTutorialSubscription = tutorialOverlayController.backNavigationStream
        .listen(_goBackTutorialListener);

    inputFocus.addListener(_inputFocusListener);

    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;
      await LanguageService.showDialogOnEmptyLanguage(context);
      if (mounted) setState(() {});
    });
  }
  // Pangea#

  final Set<String> expandedEventIds = {};

  void expandEventsFrom(Event event, bool expand) {
    final events = timeline!.events.filterByVisibleInGui(
      threadId: activeThreadId,
    );
    final start = events.indexOf(event);
    setState(() {
      for (var i = start; i < events.length; i++) {
        final event = events[i];
        if (!event.isCollapsedState) return;
        if (expand) {
          expandedEventIds.add(event.eventId);
        } else {
          expandedEventIds.remove(event.eventId);
        }
      }
    });
  }

  void _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      // We launched the chat with a given initial event ID:
      if (initialEventId != null) {
        scrollToEventId(initialEventId);
        return;
      }

      var readMarkerEventIndex = readMarkerEventId.isEmpty
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: activeThreadId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      // Read marker is existing but not found in first events. Try a single
      // requestHistory call before opening timeline on event context:
      if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: activeThreadId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, highlightEvent: false);
        return;
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      // Mark room as read on first visit if requirements are fulfilled
      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  void updateView() {
    if (!mounted) return;
    setReadMarker();
    // #Pangea
    // setState(() {});
    if (mounted) timelineUpdateNotifier.notify();
    // Pangea#
  }

  Future<void>? loadTimelineFuture;

  int? animateInEventIndex;

  void onInsert(int i) {
    // setState will be called by updateView() anyway
    if (timeline?.allowNewEvent == true) animateInEventIndex = i;
  }

  // #Pangea
  List<Event> get visibleEvents =>
      timeline?.events.where((x) => x.isVisibleInGui).toList() ?? <Event>[];
  // Pangea#

  Future<void> _getTimeline({String? eventContextId}) async {
    _timelineLoading = true;
    try {
      // Serialize with any other controller's in-flight load (see
      // _getTimelineGate): a focus swap must not run two getTimeline calls at
      // once, since getTimeline overwrites the shared room.timeline.
      while (_getTimelineGate != null) {
        await _getTimelineGate!.future;
      }
      final gate = _getTimelineGate = Completer<void>();
      try {
        await _getTimelineInner(eventContextId: eventContextId);
      } finally {
        _getTimelineGate = null;
        gate.complete();
      }
    } finally {
      _timelineLoading = false;
    }
  }

  Future<void> _getTimelineInner({String? eventContextId}) async {
    // May resume here after an unbounded wait on the gate; bail if this
    // controller was disposed meanwhile so we don't touch a defunct context.
    if (!mounted) return;
    // Subscriptions are (re)attached below, so this room is no longer suspended.
    _timelineSuspended = false;
    await Matrix.of(context).client.roomsLoading;
    await Matrix.of(context).client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixId || eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    try {
      timeline?.cancelSubscriptions();
      timeline = await room.getTimeline(
        onUpdate: updateView,
        eventContextId: eventContextId,
        onInsert: onInsert,
      );
      // #Pangea
      if (visibleEvents.length < 10 && timeline != null) {
        var prevNumEvents = timeline!.events.length;
        await requestHistory();
        var numRequests = 0;
        while (timeline != null &&
            timeline!.events.length > prevNumEvents &&
            visibleEvents.length < 10 &&
            numRequests <= 5) {
          prevNumEvents = timeline!.events.length;
          await requestHistory();
          numRequests++;
        }
      }
      // Pangea#
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      if (!mounted) return;
      timeline = await room.getTimeline(
        onUpdate: updateView,
        onInsert: onInsert,
      );
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
    timeline!.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  String? scrollToEventIdMarker;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // #Pangea
    super.didChangeAppLifecycleState(state);
    // On iOS, if the toolbar is open and the app is closed, then the user goes
    // back to do more toolbar activities, the toolbar buttons / selection don't
    // update properly. So, when the user closes the app, close the toolbar overlay.
    if (state == AppLifecycleState.paused) {
      clearSelectedEvents();
    }
    if (state == AppLifecycleState.hidden && !stopMediaStream.isClosed) {
      stopMediaStream.add(null);
    }
    // Pangea#
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    setReadMarker();
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    // #Pangea
    if (room.client.userID == null ||
        eventId != null &&
            (eventId.contains("web") ||
                eventId.contains("android") ||
                eventId.contains("ios"))) {
      return;
    }
    // Pangea#
    if (eventId?.isValidMatrixId == false) return;
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp) return;
    if (scrollUpBannerEventId != null) return;

    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    // Do not send read markers when app is not in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    // ignore: unawaited_futures
    _setReadMarkerFuture = timeline
        .setReadMarker(
          eventId: eventId,
          public: AppSettings.sendPublicReadReceipts.value,
        )
        // #Pangea
        // .then((_) {
        //   _setReadMarkerFuture = null;
        // });
        .then((_) {
          _setReadMarkerFuture = null;
        })
        .catchError((e, s) {
          ErrorHandler.logError(
            e: PangeaWarningError("Failed to set read marker: $e"),
            s: s,
            data: {'eventId': eventId, 'roomId': roomId},
          );
          Sentry.captureException(
            e,
            stackTrace: s,
            withScope: (scope) {
              scope.setTag('where', 'setReadMarker');
            },
          );
        });
    // Pangea#
    if (eventId == null || eventId == timeline.room.lastEvent?.eventId) {
      Matrix.of(context).backgroundPush?.cancelNotification(roomId);
    }
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    inputFocus.removeListener(_inputFocusListener);
    // #Pangea
    WidgetsBinding.instance.removeObserver(this);
    _storeInputTimeoutTimer?.cancel();
    _displayChatDetailsColumn.dispose();
    timelineUpdateNotifier.dispose();
    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    scrollController.removeListener(_updateScrollController);
    sendController.removeListener(onInputBarChanged);
    activityController.confettiNotifier.removeListener(
      _activityConfettiListener,
    );
    choreographer.dispose();
    activityController.dispose();
    MatrixState.pAnyState.closeAllOverlays(force: true);
    stopMediaStream.close();
    _constructsSubscription?.cancel();
    _botAudioSubscription?.cancel();
    _tokensSubscription?.cancel();
    _readingAssistanceTutorialSubscription?.cancel();
    PanelFocusController.instance.removeListener(_onFocusChanged);
    _router.routeInformationProvider.removeListener(_onRouteChanged);
    scrollController.dispose();
    inputFocus.dispose();
    depressMessageButton.dispose();
    scrollableNotifier.dispose();
    TokensUtil.instance.clearNewTokenCache();
    _forwardTutorialSubscription?.cancel();
    _goBackTutorialSubscription?.cancel();
    _goalCompletionSubscription?.cancel();
    _activityRolesSubscription?.cancel();
    tutorialOverlayController.dispose();
    activeGoalNotifier.dispose();
    //Pangea#
    super.dispose();
  }

  // #Pangea
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router = GoRouter.of(context);
    // Transient UI teardown (stop media, close overlays) stays bound to route
    // changes — it must fire even in the legacy route-driven flow, where no
    // ?left= token exists so the focus signal never changes. Timeline focus is
    // handled separately by _onFocusChanged via PanelFocusController. _router is
    // also read for the legacy fallback in [isFocused].
    _router.routeInformationProvider
      ..removeListener(_onRouteChanged)
      ..addListener(_onRouteChanged);
    if (room.isSpace && isFocused) {
      ErrorHandler.logError(
        e: "Space chat opened",
        s: StackTrace.current,
        data: {"roomId": roomId},
      );
      NavigationUtil.goToSpaceRoute(null, [], context);
    }
  }

  /// Transient UI teardown on navigation, matching the pre-decoupling behavior:
  /// stop in-progress media and close this chat's overlays whenever the route
  /// changes. Bound to the router (not focus) so it also fires in the legacy
  /// route-driven flow — e.g. opening a chat subroute (search/details/invite)
  /// that keeps this controller mounted underneath — where no ?left= token
  /// exists and the focus signal therefore never changes.
  void _onRouteChanged() {
    if (!mounted) return;
    if (!stopMediaStream.isClosed) {
      stopMediaStream.add(null);
    }
    MatrixState.pAnyState.closeOverlay("star-rain-${widget.room.id}");
    MatrixState.pAnyState.closeAllOverlays();
  }

  /// Timeline lifecycle follows panel focus (the URL-driven left column): resume
  /// when this room becomes the live panel, suspend when another panel takes
  /// over while we stay mounted. In the legacy route-driven flow no focus signal
  /// is published, so this never fires and the timeline simply stays loaded (as
  /// before); [_onRouteChanged] handles transient teardown there instead.
  void _onFocusChanged() {
    if (!mounted) return;
    if (isFocused) {
      _resumeTimeline();
    } else {
      _suspendTimeline();
    }
  }

  /// Cancel timeline subscriptions but keep the [timeline] object and this
  /// controller mounted, so a refocus can resume without losing draft/scroll.
  void _suspendTimeline() {
    if (timeline == null || _timelineSuspended) return;
    timeline?.cancelSubscriptions();
    _timelineSuspended = true;
  }

  /// Reload the timeline on (re)focus if it was never loaded or was suspended.
  /// `room.getTimeline` overwrites `room.timeline`, so a full reload is the safe
  /// way to re-attach `onUpdate` after a suspend. Skips when a load is already
  /// in flight, so the post-mount focus publish can't double-load.
  void _resumeTimeline() {
    if (_timelineLoading) return;
    if (timeline != null && !_timelineSuspended) return;
    loadTimelineFuture = _getTimeline();
  }

  // TextEditingController sendController = TextEditingController();
  PangeaTextController get sendController => choreographer.textController;
  // Pangea#

  void setSendingClient(Client c) {
    // #Pangea
    // // first cancel typing with the old sending client
    // if (currentlyTyping) {
    //   // no need to have the setting typing to false be blocking
    //   typingCoolDown?.cancel();
    //   typingCoolDown = null;
    //   room.setTyping(false);
    //   currentlyTyping = false;
    // }
    // // then cancel the old timeline
    // // fixes bug with read reciepts and quick switching
    // loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
    //   ErrorReporter(
    //     context,
    //     'Unable to load timeline after changing sending Client',
    //   ).onErrorCallback,
    // );

    // // then set the new sending client
    // setState(() => sendingClient = c);
    // Pangea#
  }

  // #Pangea
  // void setActiveClient(Client c) => setState(() {
  //   Matrix.of(context).setActiveClient(c);
  // });
  // Pangea#

  // #Pangea
  Event? pangeaEditingEvent;
  void clearEditingEvent() {
    pangeaEditingEvent = null;
  }

  /// Add a fake event to the timeline to visually indicate that a message is being sent.
  /// Used when tokenizing after message send, specifically because tokenization for some
  /// languages takes some time.
  Future<String?> sendFakeMessage(Event? edit, Event? reply) async {
    if (sendController.text.trim().isEmpty) return null;
    final message = sendController.text;
    sendController.setSystemText("", EditTypeEnum.other);

    return room.sendFakeMessage(
      text: message,
      inReplyTo: reply,
      editEventId: edit?.eventId,
    );
  }

  // Future<void> send() async {
  //   if (sendController.text.trim().isEmpty) return;
  Future<void> send() async {
    // Close span card if open
    MatrixState.pAnyState.closeAllOverlays();

    final message = sendController.text;
    final edit = editEvent.value;
    final reply = replyEvent.value;
    editEvent.value = null;
    replyEvent.value = null;
    pendingText = '';

    choreographer.clearSuggestions();
    final tempEventId = await sendFakeMessage(edit, reply);
    if (!inputFocus.hasFocus) {
      inputFocus.requestFocus();
    }

    final content = await choreographer.getMessageContent(message);
    choreographer.clearWritingAssistance();

    if (message.trim().isEmpty) return;
    // Pangea#
    _storeInputTimeoutTimer?.cancel();
    final prefs = Matrix.of(context).store;
    prefs.remove('draft_$roomId');
    var parseCommands = true;

    // #Pangea
    // final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(message);
    // Pangea#
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      // #Pangea
      // final l10n = L10n.of(context);
      // final dialogResult = await showOkCancelAlertDialog(
      //   context: context,
      //   title: l10n.commandInvalid,
      //   message: l10n.commandMissing(commandMatch[0]!),
      //   okLabel: l10n.sendAsText,
      //   cancelLabel: l10n.cancel,
      // );
      // if (dialogResult == OkCancelResult.cancel) return;
      // Pangea#
      parseCommands = false;
    }

    // ignore: unawaited_futures
    // #Pangea
    // room.sendTextEvent(
    //   sendController.text,
    //   inReplyTo: replyEvent,
    //   editEventId: editEvent.eventId,
    //   parseCommands: parseCommands,
    //   threadRootEventId: activeThreadId,
    // );
    // If the message and the sendController text don't match, it's possible
    // that there was a delay in tokenization before send, and the user started
    // typing a new message. We don't want to erase that, so only reset the input
    // bar text if the message is the same as the sendController text.
    if (message == sendController.text) {
      sendController.setSystemText("", EditTypeEnum.other);
    }

    final previousEdit = edit;
    if (showEmojiPicker) {
      hideEmojiPicker();
    }

    room
        .pangeaSendTextEvent(
          message,
          inReplyTo: reply,
          editEventId: edit?.eventId,
          parseCommands: parseCommands,
          originalWritten: content.originalWritten,
          tokensSent: content.tokensSent,
          tokensWritten: content.tokensWritten,
          choreo: content.choreo,
          txid: tempEventId,
          threadRootEventId: activeThreadId,
        )
        .then((String? msgEventId) async {
          // #Pangea
          // There's a listen in my_analytics_controller that decides when to auto-update
          // analytics based on when / how many messages the logged in user send. This
          // stream sends the data for newly sent messages.
          _sendMessageAnalytics(
            msgEventId,
            originalSent: PangeaRepresentation(
              langCode:
                  content.tokensSent?.detections?.firstOrNull?.langCode ??
                  LanguageKeys.unknownLanguage,
              text: message,
              originalSent: true,
              originalWritten: false,
            ),
            tokensSent: content.tokensSent,
            choreo: content.choreo,
          );

          if (previousEdit != null) {
            pangeaEditingEvent = previousEdit;
          }

          GoogleAnalytics.sendMessage(room.id, room.joinCode ?? "");

          if (msgEventId == null) {
            ErrorHandler.logError(
              e: Exception('msgEventId is null'),
              s: StackTrace.current,
              data: {
                'roomId': roomId,
                'text': message,
                'inReplyTo': reply?.eventId,
                'editEventId': edit?.eventId,
              },
            );
            return;
          }
        })
        .catchError((err, s) {
          if (err is EventTooLarge) {
            showAdaptiveDialog(
              context: context,
              builder: (context) => const EventTooLargeDialog(),
            );
            return;
          }
          ErrorHandler.logError(
            e: err,
            s: s,
            data: {
              'roomId': roomId,
              'text': message,
              'inReplyTo': reply?.eventId,
              'editEventId': edit?.eventId,
            },
          );
        });
    // sendController.value = TextEditingValue(
    //   text: pendingText,
    //   selection: const TextSelection.collapsed(offset: 0),
    // );

    // setState(() {
    //   sendController.text = pendingText;
    //   _inputTextIsEmpty = pendingText.isEmpty;
    //   replyEvent = null;
    //   editEvent = null;
    //   pendingText = '';
    // });
    // Pangea#
  }

  void sendFileAction({FileType type = FileType.any}) async {
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  void sendImageFromClipBoard(Uint8List? image) async {
    if (image == null) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [XFile.fromData(image)],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  void openCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  void openVideoCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: activeThreadId,
        threadLastEventId: threadLastEventId,
      ),
    );
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String? fileName,
  ) async {
    // #Pangea
    // Capture EVERYTHING context-derived at the ABSOLUTE TOP -- before
    // `stopMediaStream.add` and before the FIRST await (the Android sdkInt
    // check) -- while the context is GUARANTEED alive. Nothing context-derived
    // is resolved after ANY await, so navigation during the send can never
    // leave a capture (esp. `Matrix.of(context)` for the analytics sink)
    // reading a deactivated context.
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final decoupleTokenizer = Environment.voiceTranscriptDecoupleEnabled;
    final VoiceAnalyticsSink? voiceAnalyticsSink = decoupleTokenizer
        ? Matrix.of(context).analyticsDataService.updateService.addAnalytics
        : null;
    final capturedRoom = room;
    final capturedRoomId = roomId;
    final capturedClientUserId = sendingClient.userID;
    // BOTH forms from the SAME t0 read: the embed uses the raw setting codes
    // (baseline speaker_l1/l2), the ASR uses the normalized short codes
    // (baseline ASR hint). Distinct representations -> flag-OFF ASR bytes stay
    // byte-identical to baseline; single read -> no mid-send drift (H3/BLOCKER).
    final voiceLangs = VoiceSendLanguages.capture(
      sourceCode: pangeaController.userController.userL1Code,
      targetCode: pangeaController.userController.userL2Code,
      sourceShort: pangeaController.userController.userL1?.langCodeShort,
      targetShort: pangeaController.userController.userL2?.langCodeShort,
    );

    stopMediaStream.add(null);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 19) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context).unsupportedAndroidVersion,
          message: L10n.of(context).unsupportedAndroidVersionLong,
          okLabel: L10n.of(context).close,
        );
        return;
      }
    }
    // Pangea#

    final audioFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: audioFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final file = MatrixAudioFile(
      bytes: bytes,
      name: fileName ?? audioFile.path,
    );

    // #Pangea
    final reply = replyEvent.value;
    replyEvent.value = null;

    // Get transcript first so we can embed it in the audio event,
    // allowing the bot (and other clients) to read it immediately
    // without waiting for a separate representation event. When the
    // tokenizer-decouple flag is on, fetch TEXT-ONLY (skip_tokenize) so the
    // send does not block on the LLM tokenizer; the tokens are computed and
    // attached in the background after send (_scheduleVoiceTranscriptEnrichment).
    final transcriptResult = await _getVoiceMessageTranscript(
      file,
      skipTokenize: decoupleTokenizer,
      // Thread the ASR short codes captured at t0 (baseline representation),
      // never re-read current settings -- byte-identical to baseline yet
      // drift-free across a mid-send change (BLOCKER/H3).
      userL1: voiceLangs.asrL1,
      userL2: voiceLangs.asrL2,
    );
    final stt = transcriptResult.result;

    // The background tokenize snapshot is EVENT-sourced (D6): full_text /
    // lang_code / sender_l2 come from the embed, sender_l1 from the speaker_l1
    // captured at the top (before any await) and embedded below. It cannot
    // drift if the user changes their L1/L2 while the send is in flight, and
    // the background never re-reads current settings. A non-usable
    // (exhausted-fallback) transcript has nothing to tokenize -> no snapshot,
    // no background work.
    final decoupleSnapshot =
        decoupleTokenizer && stt != null && stt.hasUsableTranscript
        ? SttLangSnapshot.fromBaseStt(stt, speakerL1: voiceLangs.speakerL1)
        : null;
    // Pangea#

    // #Pangea
    // room
    final eventId = await room
        // Pangea#
        .sendFileEvent(
          file,
          // #Pangea
          // inReplyTo: replyEvent,
          inReplyTo: reply,
          // Pangea#
          threadRootEventId: activeThreadId,
          extraContent: {
            'info': {...file.info, 'duration': duration},
            'org.matrix.msc3245.voice': {},
            'org.matrix.msc1767.audio': {
              'duration': duration,
              'waveform': waveform,
            },
            // #Pangea
            'speaker_l1': voiceLangs.speakerL1,
            'speaker_l2': voiceLangs.speakerL2,
            if (stt != null) MessageConstants.userStt: stt.toJson(),
            // Pangea#
          },
        )
        // #Pangea
        // .catchError((e) {
        .catchError((e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {'roomId': roomId, 'file': file.name},
          );
          // Pangea#
          // #Pangea
          scaffoldMessenger.showSnackBarAnnounced(
            SnackBar(content: Text((e as Object).toLocalizedString(context))),
            assertive: true,
          );
          // Pangea#
          return null;
        });
    // #Pangea
    // setState(() {
    //   replyEvent = null;
    // });
    if (eventId == null) {
      ErrorHandler.logError(
        e: Exception('eventID null in voiceMessageAction'),
        s: StackTrace.current,
        data: {'roomId': roomId},
      );
      return;
    }

    if (stt != null) {
      // Route through the pure predicate so the flag-gated decision is
      // unit-tested (see shouldScheduleDecoupledEnrichment).
      if (shouldScheduleDecoupledEnrichment(
        decoupleFlag: decoupleTokenizer,
        snapshot: decoupleSnapshot,
        sink: voiceAnalyticsSink,
      )) {
        // Send is done and the bot can reply from the embedded text; only a
        // usable transcript reaches here (an exhausted-fallback yields a null
        // snapshot -> the message stands, no background work, no crash).
        // Fire-and-forget so send is not blocked. The predicate above
        // guarantees both are non-null.
        _scheduleVoiceTranscriptEnrichment(
          eventId: eventId,
          baseStt: stt,
          snapshot: decoupleSnapshot!,
          analyticsSink: voiceAnalyticsSink!,
          room: capturedRoom,
          roomId: capturedRoomId,
          clientUserId: capturedClientUserId,
        );
      } else if (!decoupleTokenizer) {
        // Flag OFF: unchanged legacy inline analytics path (byte-parity).
        _sendVoiceMessageAnalytics(eventId, stt);
      }
    }
    // Pangea#
    return;
  }

  /// Thin wiring for the decoupled voice send's background half: builds the
  /// injected dependencies from the refs captured at the top of
  /// [onVoiceMessageSend] and fires the coordinator. The coordinator owns the
  /// real-event lookup, the feedback dispatch, and ALL error-wrapping, so this
  /// returns immediately, reads NO widget `context`, and nothing escapes.
  void _scheduleVoiceTranscriptEnrichment({
    required String eventId,
    required SpeechToTextResponseModel baseStt,
    required SttLangSnapshot snapshot,
    required VoiceAnalyticsSink analyticsSink,
    required Room room,
    required String roomId,
    required String? clientUserId,
  }) {
    unawaited(
      runVoiceTranscriptEnrichment(
        baseStt: baseStt,
        snapshot: snapshot,
        clientUserId: clientUserId,
        // Real-event sender lookup deferred INTO the coordinator's guarded scope
        // (a DB/decryption throw there is caught, not an unhandled async error).
        // Own-ness is thus bound to the REAL sent event, never a hardcoded bool.
        resolveSenderId: () async =>
            (await room.getEventById(eventId))?.senderId,
        enrich: enrichSttWithTokens,
        recordAnalytics: buildVoiceAnalyticsRecorder(
          roomId: roomId,
          eventId: eventId,
          sink: analyticsSink,
        ),
        showFeedback: (richStt) =>
            _showVoiceAnalyticsFeedback(richStt, roomId, eventId),
        attach: (richStt) => attachSttRepresentation(
          send: room.sendPangeaEvent,
          parentEventId: eventId,
          richStt: richStt,
        ),
        onError: (e, s) => ErrorHandler.logError(
          e: e,
          s: s,
          data: {'roomId': roomId, 'eventId': eventId},
        ),
      ),
    );
  }

  /// Thin visual-feedback dispatch for the decoupled path: compute the
  /// constructs from [richStt] and show the (mounted-safe) overlay. The
  /// coordinator wraps this in its own catch, so a throw here is swallowed +
  /// logged and never affects the analytics recording.
  Future<void> _showVoiceAnalyticsFeedback(
    SpeechToTextResponseModel richStt,
    String roomId,
    String eventId,
  ) async {
    final constructs = richStt.constructs(roomId, eventId);
    if (constructs.isEmpty) return;
    final langCode = richStt.langCode.split('-').first;
    await _showAnalyticsFeedback(constructs, eventId, langCode);
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  // #Pangea
  // void _inputFocusListener() {
  //   if (showEmojiPicker && inputFocus.hasFocus) {
  //     setState(() => showEmojiPicker = false);
  //   }
  // }
  void _inputFocusListener() {
    if (!inputFocus.hasFocus) return;
    if (!tutorialOverlayController.isTutorialQueued(
      TutorialEnum.writingAssistance,
    )) {
      return;
    }

    _launchWritingAssistanceTutorial();
  }
  // Pangea#

  void sendLocationAction() async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  String _getSelectedEventString() {
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)));
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: true,
          );
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    // #Pangea
    // setState(() {
    //   showEmojiPicker = false;
    //   selectedEvents.clear();
    // });
    clearSelectedEvents();
    // Pangea#
  }

  void deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      // #Pangea
      // setState(selectedEvents.clear);
      clearSelectedEvents();
      await room.refreshLastEvent();
      // Pangea#
    } catch (e, s) {
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  void redactEventsAction() async {
    final reasonInput = selectedEvents.any((event) => event.status.isSent)
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            maxLength: 255,
            maxLines: 3,
            minLines: 1,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
            // #Pangea
            autoSubmit: true,
            // Pangea#
          )
        : null;
    // #Pangea
    // if (reasonInput == null) return;
    if (reasonInput == null) {
      clearSelectedEvents();
      return;
    }
    // Pangea#
    final reason = reasonInput.isEmpty ? null : reasonInput;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = selectedEvents.length;
        for (final (i, event) in selectedEvents.indexed) {
          onProgress(i / count);
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = currentRoomBundle.firstWhere(
                (cl) => selectedEvents.first.senderId == cl!.userID,
                orElse: () => null,
              );
              if (client == null) {
                return;
              }
              final room = client.getRoomById(roomId)!;
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
        }
      },
    );
    // #Pangea
    // setState(() {
    //   showEmojiPicker = false;
    //   selectedEvents.clear();
    // });
    clearSelectedEvents();
    // Pangea#
  }

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    final clients = Matrix.of(context).currentBundle;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !(clients!.any((cl) => event.senderId == cl!.userID))) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent ||
        activeThreadId != null) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (cl) => selectedEvents.first.senderId == cl!.userID,
    );
  }

  void forwardEventsAction() async {
    if (selectedEvents.isEmpty) return;
    final timeline = this.timeline;
    if (timeline == null) return;

    final forwardEvents = List<Event>.from(
      selectedEvents,
    ).map((event) => event.getDisplayEvent(timeline)).toList();

    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: forwardEvents
            // #Pangea
            // .map((event) => ContentShareItem(event.content))
            // .toList(),
            .map((event) {
              final content = Map<String, dynamic>.from(event.content);
              content.remove("m.relates_to");
              return ContentShareItem(content);
            })
            .toList(),
        // Pangea#
      ),
    );
    if (!mounted) return;
    // #Pangea
    // see https://github.com/pangeachat/client/issues/2536
    // setState(() => selectedEvents.clear());
    // Pangea#
  }

  void sendAgainAction() {
    // #Pangea
    if (selectedEvents.isEmpty) {
      ErrorHandler.logError(
        e: "No selected events in send again action",
        s: StackTrace.current,
        data: {"roomId": roomId},
      );
      clearSelectedEvents();
      return;
    }
    // Pangea#
    final event = selectedEvents.first;
    // #Pangea
    clearSelectedEvents();
    // Pangea#
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    // #Pangea
    // setState(() => selectedEvents.clear());
    // Pangea#
  }

  void replyAction({Event? replyTo}) {
    // #Pangea
    replyEvent.value = replyTo ?? selectedEvents.first;
    clearSelectedEvents();
    // setState(() {
    //   replyEvent = replyTo ?? selectedEvents.first;
    //   selectedEvents.clear();
    // });
    // Pangea#
    inputFocus.requestFocus();
  }

  // #Pangea
  // void scrollToEventId(String eventId, {bool highlightEvent = true}) async {
  Future<bool> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
    int calls = 0,
  }) async {
    if (timeline == null) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: 'Timeline is null when trying to scroll to event ID',
        ),
      );
      return false;
    }

    if (calls > 2) {
      ErrorHandler.logError(
        e: Exception('Too many attempts to scroll to event ID $eventId'),
        data: {'roomId': roomId, 'eventId': eventId, 'calls': calls},
      );
      return false;
    }
    // Pangea#
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    final eventIndex = foundEvent == null
        ? -1
        : timeline!.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: activeThreadId,
              )
              .indexOf(foundEvent);

    if (eventIndex == -1) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        // #Pangea
        // scrollToEventId(eventId);
        scrollToEventId(
          eventId,
          calls: calls + 1,
          highlightEvent: highlightEvent,
        );
        // Pangea#
      });
      // #Pangea
      // return;
      return true;
      // Pangea#
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    await scrollController.scrollToIndex(
      eventIndex + 1,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
    // #Pangea
    return true;
    // Pangea#
  }

  void scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(dynamic _, Emoji? emoji) {
    typeEmoji(emoji);
    // #Pangea
    // onInputBarChanged(sendController.text);
    onInputBarChanged();
    // Pangea#
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;

    // #Pangea
    if (!sendController.selection.isValid) {
      sendController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    // Pangea#
    final selection = sendController.selection;
    final newText = sendController.text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: selection.baseOffset + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  // #Pangea
  // void clearSelectedEvents() => setState(() {
  //   selectedEvents.clear();
  //   showEmojiPicker = false;
  // });

  // void clearSingleSelectedEvent() {
  //   if (selectedEvents.length <= 1) {
  //     clearSelectedEvents();
  //   }
  // }
  void clearSelectedEvents() {
    if (!mounted) return;
    if (!isToolbarOpen && selectedEvents.isEmpty) return;
    MatrixState.pAnyState.closeAllOverlays();
    depressMessageButton.value = false;

    setState(() {
      selectedEvents.clear();
      showEmojiPicker = false;
    });
  }

  void setSelectedEvent(Event event) {
    setState(() {
      selectedEvents.clear();
      selectedEvents.add(event);
    });
  }
  // Pangea#

  void editSelectedEventAction() {
    // #Pangea
    // final client = currentRoomBundle.firstWhere(
    //   (cl) => selectedEvents.first.senderId == cl!.userID,
    //   orElse: () => null,
    // );
    // if (client == null) {
    //   return;
    // }
    // setSendingClient(client);
    // setState(() {
    //   pendingText = sendController.text;
    //   editEvent = selectedEvents.first;
    //   sendController.text = editEvent
    //       .getDisplayEvent(timeline!)
    //       .calcLocalizedBodyFallback(
    //         MatrixLocals(L10n.of(context)),
    //         withSenderNamePrefix: false,
    //         hideReply: true,
    //       );
    //   selectedEvents.clear();
    // });
    pendingText = sendController.text;
    editEvent.value = selectedEvents.first;
    sendController.text = editEvent.value!
        .getDisplayEvent(timeline!)
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );
    clearSelectedEvents();
    // Pangea#
    inputFocus.requestFocus();
  }

  void goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.compareTo(b.powerLevel));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go(
      WorkspaceNav.openRoomById(GoRouterState.of(context).uri, result.result!),
    );

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  // #Pangea
  // void onSelectMessage(Event event) {
  //   if (!event.redacted) {
  //     if (selectedEvents.contains(event)) {
  //       setState(() => selectedEvents.remove(event));
  //     } else {
  //       setState(() => selectedEvents.add(event));
  //     }
  //     selectedEvents.sort(
  //       (a, b) => a.originServerTs.compareTo(b.originServerTs),
  //     );
  //   }
  // }
  // Pangea#

  int? findChildIndexCallback(Key key, Map<String, int> thisEventsKeyMap) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) {
      return null;
    }
    final eventId = key.value;
    if (eventId is! String) {
      return null;
    }
    // first fetch the last index the event was at
    final index = thisEventsKeyMap[eventId];
    if (index == null) {
      return null;
    }
    // we need to +1 as 0 is the typing thing at the bottom
    return index + 1;
  }

  // #Pangea
  // void onInputBarSubmitted(String _) {
  //   send();
  //   FocusScope.of(context).requestFocus(inputFocus);
  // }
  Future<void> onInputBarSubmitted() async {
    if (MatrixState.pangeaController.subscriptionController.shouldShowPaywall) {
      PaywallCard.show(context, ChoreoConstants.inputTransformTargetKey);
      return;
    }
    await _onRequestWritingAssistance(manual: false, autosend: true);
  }
  // Pangea#

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    room.client.getConfig();

    switch (choice) {
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.poll:
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  void unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      // #Pangea
      // message: L10n.of(context).confirmEventUnpin,
      message: L10n.of(context).confirmMessageUnpin,
      // Pangea#
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      // #Pangea
      if (scrollToEventIdMarker == eventId) {
        scrollToEventIdMarker = null;
      }
      // Pangea#
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  // #Pangea
  // void pinEvent() {
  Future<void> pinEvent() async {
    // Pangea#
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      // #Pangea
      //pinnedEventIds.removeWhere(selectedEventIds.contains);
      unpinEvent(selectedEventIds.single);
      // Pangea#
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    // #Pangea
    // showFutureLoadingDialog(
    //   context: context,
    //   future: () => room.setPinnedEvents(pinnedEventIds),
    // );
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
    clearSelectedEvents();
    // Pangea#
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  // #Pangea
  // void onInputBarChanged(String text) {
  void onInputBarChanged() {
    // if (_inputTextIsEmpty != text.isEmpty) {
    //   setState(() {
    //     _inputTextIsEmpty = text.isEmpty;
    //   });
    // }
    final text = sendController.text;
    // Pangea#
    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = Matrix.of(context).store;
      await prefs.setString('draft_$roomId', text);
    });
    // #Pangea
    // if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
    //   final clients = currentRoomBundle;
    //   for (final client in clients) {
    //     final prefix = client!.sendPrefix;
    //     if ((prefix.isNotEmpty) &&
    //         text.toLowerCase() == '${prefix.toLowerCase()} ') {
    //       setSendingClient(client);
    //       setState(() {
    //         sendController.clear();
    //       });
    //       return;
    //     }
    //   }
    // }
    // Pangea#
    if (AppSettings.sendTypingNotifications.value) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  // #Pangea
  // bool _inputTextIsEmpty = true;
  // Pangea#

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  // #Pangea
  // void showEventInfo([Event? event]) =>
  //     (event ?? selectedEvents.single).showInfoDialog(context);
  void showEventInfo([Event? event]) {
    (event ?? selectedEvents.single).showInfoDialog(context);
    clearSelectedEvents();
  }
  // Pangea#

  void cancelReplyEventAction() => setState(() {
    // #Pangea
    // sendController.text = pendingText;
    sendController.setSystemText(pendingText, EditTypeEnum.other);
    // Pangea#
    pendingText = '';
    // #Pangea
    // replyEvent = null;
    // editEvent = null;
    replyEvent.value = null;
    editEvent.value = null;
    // Pangea#
  });
  // #Pangea
  LayerLinkAndKey get igcButtonLink =>
      MatrixState.pAnyState.layerLinkAndKey("start_igc_button_${room.id}");

  ValueNotifier<bool> depressMessageButton = ValueNotifier(false);

  String? get buttonEventID => timeline?.events
      .firstWhereOrNull(
        (event) =>
            event.isVisibleInGui &&
            event.senderId != room.client.userID &&
            !event.redacted,
      )
      ?.eventId;

  String? get refreshEventID {
    final candidate = timeline!.events.firstWhereOrNull(
      (event) =>
          event.isVisibleInGui &&
          event.senderId != room.client.userID &&
          event.senderId == BotName.byEnvironment,
    );
    if (candidate == null) return null;

    final hasEdit = candidate.hasAggregatedEvents(
      timeline!,
      RelationshipTypes.edit,
    );
    final isRedacted = candidate.redacted;
    final isFirstBotDMMessage = candidate.isFirstBotDMMessage;

    if (hasEdit || isRedacted || isFirstBotDMMessage) return null;
    return candidate.eventId;
  }

  final StreamController<void> stopMediaStream = StreamController.broadcast();

  bool get isToolbarOpen => MatrixState.pAnyState.isOverlayOpen(
    overlayKey: "message_toolbar_overlay",
  );

  void showToolbar(
    Event event, {
    PangeaMessageEvent? pangeaMessageEvent,
    PangeaToken? selectedToken,
    MessagePracticeMode? mode,
    Event? nextEvent,
    Event? prevEvent,
    bool bypassBlockingOverlays = false,
  }) async {
    if (event.redacted ||
        event.text == '' ||
        event.status == EventStatus.sending) {
      return;
    }

    // Close emoji picker, if open
    if (showEmojiPicker) {
      hideEmojiPicker();
      return;
    }

    // Check if the user has set their languages. If not, prompt them to do so.
    if (!MatrixState.pangeaController.userController.languagesSet) {
      await LanguageService.showDialogOnEmptyLanguage(context);
      return;
    }

    final overlayEntry = MessageSelectionOverlay(
      chatController: this,
      event: event,
      timeline: timeline!,
      initialSelectedToken: selectedToken,
      nextEvent: nextEvent,
      prevEvent: prevEvent,
    );

    // you've clicked a message so lets turn this off
    if (!InstructionsEnum.clickMessage.isToggledOff) {
      InstructionsEnum.clickMessage.setToggledOff(true);
    }

    if (!kIsWeb) {
      HapticFeedback.mediumImpact();
    }
    stopMediaStream.add(null);

    final isButton = buttonEventID == event.eventId;
    final keyboardOpen = inputFocus.hasFocus && PlatformInfos.isMobile;

    final delay = keyboardOpen
        ? const Duration(milliseconds: 500)
        : isButton
        ? const Duration(milliseconds: 200)
        : null;

    if (isButton) {
      depressMessageButton.value = true;
    }

    inputFocus.unfocus();

    if (delay != null) {
      OverlayUtil.showOverlay(
        context: context,
        child: TransparentBackdrop(
          backgroundColor: Colors.black,
          onDismiss: clearSelectedEvents,
          blurBackground: true,
          animateBackground: true,
          backgroundAnimationDuration: delay,
        ),
        displayDetails: CenteredOverlayDisplayDetails(
          overlayKey: "button_message_backdrop",
          bypassBlockingOverlays: bypassBlockingOverlays,
        ),
      );

      await Future.delayed(delay);

      if (!isFocused) {
        // The user has navigated away from the chat,
        // so we don't want to show the overlay.
        return;
      }
      OverlayUtil.showOverlay(
        context: context,
        child: overlayEntry,
        displayDetails: CenteredOverlayDisplayDetails(
          onDismiss: clearSelectedEvents,
          blurBackground: true,
          backgroundColor: Colors.black,
          overlayKey: "message_toolbar_overlay",
          bypassBlockingOverlays: bypassBlockingOverlays,
        ),
      );
    } else {
      OverlayUtil.showOverlay(
        context: context,
        child: overlayEntry,
        displayDetails: CenteredOverlayDisplayDetails(
          onDismiss: clearSelectedEvents,
          blurBackground: true,
          backgroundColor: Colors.black,
          overlayKey: "message_toolbar_overlay",
          bypassBlockingOverlays: bypassBlockingOverlays,
        ),
      );
    }

    GoogleAnalytics.openMessageToolbar();
  }

  bool get displayChatDetailsColumn {
    try {
      return _displayChatDetailsColumn.value;
    } catch (e) {
      // if not set, default to false
      return false;
    }
  }

  void _sendMessageAnalytics(
    String? eventId, {
    PangeaRepresentation? originalSent,
    PangeaMessageTokens? tokensSent,
    ChoreoRecordModel? choreo,
  }) {
    // There's a listen in my_analytics_controller that decides when to auto-update
    // analytics based on when / how many messages the logged in user send. This
    // stream sends the data for newly sent messages.
    if (originalSent?.langCodeMatchesL2 != true) {
      return;
    }

    final metadata = ConstructUseMetaData(
      roomId: roomId,
      timeStamp: DateTime.now(),
      eventId: eventId,
    );

    if (eventId != null && originalSent != null && tokensSent != null) {
      final List<OneConstructUse> constructs = [
        ...originalSent.vocabAndMorphUses(
          choreo: choreo,
          tokens: tokensSent.tokens,
          metadata: metadata,
        ),
      ];

      final langCode = originalSent.langCode.split('-').first;
      _showAnalyticsFeedback(constructs, eventId, langCode);
      addAnalytics(constructs, eventId, langCode);
    }
  }

  Future<void> _sendVoiceMessageAnalytics(
    String eventId,
    SpeechToTextResponseModel stt,
  ) async {
    try {
      // Exhausted-fallback: fromJson no longer throws for `results: []`
      // (R0-2), so a voice message can now carry a real-but-empty stt. There
      // is nothing to score; `transcript` assumes at least one result and
      // would throw otherwise.
      if (stt.results.isEmpty || stt.transcript.sttTokens.isEmpty) return;
      final constructs = stt.constructs(roomId, eventId);
      if (constructs.isEmpty) return;

      final langCode = stt.langCode.split('-').first;
      // Fire-and-forget the visual feedback, but wrap it so a fetch/overlay
      // throw can never escape as an unhandled async error -- P1b made
      // `_showAnalyticsFeedback` async/heavier, so the flag-OFF path needs the
      // same swallow the decouple coordinator applies (H2, ON/OFF symmetric).
      unawaited(
        guardFeedbackDispatch(
          () => _showAnalyticsFeedback(constructs, eventId, langCode),
          (e, s) => ErrorHandler.logError(
            e: e,
            s: s,
            data: {'roomId': roomId, 'eventId': eventId},
          ),
        ),
      );
      Matrix.of(context).analyticsDataService.updateService.addAnalytics(
        eventId,
        constructs,
        langCode,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': roomId, 'eventId': eventId},
      );
    }
  }

  Future<async.Result<SpeechToTextResponseModel>> _getVoiceMessageTranscript(
    MatrixAudioFile file, {
    required String userL1,
    required String userL2,
    bool skipTokenize = false,
  }) async {
    // Use the CAPTURED t0 languages (threaded in), never re-read current
    // settings -- so the ASR language matches the embed's speaker_l1/l2 even if
    // the user changes their L1/L2 mid-send (H3).
    return SpeechToTextRepo.instance.get(
      buildVoiceSttRequest(
        audioContent: file.bytes,
        mimeType: file.mimeType,
        userL1: userL1,
        userL2: userL2,
        skipTokenize: skipTokenize,
      ),
    );
  }

  void showNextMatch({PangeaMatchState? match}) {
    final matchToShow =
        match ?? choreographer.igcController.openMatches.firstOrNull;

    if (matchToShow == null) {
      inputFocus.requestFocus();
      return;
    }

    final isSpanCardOpen = _spanCardOverlayController.isOpen;

    try {
      choreographer.igcController.setMatchToShow(matchToShow);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'match': matchToShow.toJson()});
      return;
    }

    if (!isSpanCardOpen) {
      _spanCardOverlayController.open(
        context,
        openOverlay: (overlayKey) => OverlayUtil.showPositionedCard(
          context: context,
          cardToShow: SpanCard(controller: _spanCardOverlayController),
          displayDetails: PositionedOverlayDisplayDetails(
            overlayKey: overlayKey,
            maxHeight: 325,
            maxWidth: 325,
            transformTargetId: ChoreoConstants.inputTransformTargetKey,
            ignorePointer: true,
            isScrollable: false,
          ),
          overlayPosition: OverlayPosition.above,
        ),
      );
    }
  }

  void showSuggestion() {
    final suggestion = choreographer.orchestratorController.activeSuggestion;
    if (suggestion == null || suggestion.shuffledChoices.isEmpty) {
      Logs().w("Show suggestion called without active suggestion");
      return;
    }

    _spanCardOverlayController.open(
      context,
      openOverlay: (overlayKey) => OverlayUtil.showOverlay(
        context: context,
        child: SuggestionCard(
          overlayKey: overlayKey,
          controller: choreographer.orchestratorController,
          popupManager: _spanCardOverlayController,
        ),
        displayDetails: TransformOverlayDisplayDetails(
          overlayKey: overlayKey,
          transformTargetId: ChoreoConstants.inputTransformTargetKey,
          ignorePointer: true,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Future<void> onManualWritingAssistance() =>
      _onRequestWritingAssistance(manual: true);

  Future<void> onWritingAssistanceFeedback(String feedback) =>
      _onRequestWritingAssistance(feedback: feedback);

  Future<void> _onRequestWritingAssistance({
    bool manual = false,
    bool autosend = false,
    String? feedback,
  }) async {
    if (shouldShowLanguageMismatchPopupByActivity) {
      return showLanguageMismatchPopup(manual: manual, autosend: autosend);
    }

    if (_spanCardOverlayController.isOpen && !manual) {
      await _spanCardOverlayController.close();
    }

    final assistanceState = choreographer.assistanceState;

    if (assistanceState == AssistanceStateEnum.error) {
      final error = choreographer.errorService.error!;
      // #Pangea
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
          content: Text(error.toLocalizedString(context)),
        ),
        assertive: true,
      );
      // Pangea#
      choreographer.errorService.clear();
      return;
    }

    if (assistanceState == AssistanceStateEnum.noSub) {
      if (manual) {
        PaywallCard.show(
          context,
          ChoreoConstants.inputTransformTargetKey,
          force: true,
        );
      } else {
        await send();
      }
      return;
    }

    if (assistanceState == AssistanceStateEnum.fetching) {
      return;
    }

    // If this request should send on a success, and is not a manual request,
    // and assistance has already been requested or writing assistance should not run automatically in this room,
    // then just send the message instead of requesting assistance.
    if (autosend && !manual) {
      if (assistanceState != AssistanceStateEnum.notFetched ||
          !room.enableAutomaticWritingAssistance) {
        await send();
        return;
      }
    }

    if (assistanceState == AssistanceStateEnum.suggestionComplete) {
      if (autosend) {
        await send();
      }
      return;
    }

    // If assistance is complete, but the user manually requests corrections,
    // update the feedback to say that the message still contains errors
    if (feedback == null &&
        manual &&
        assistanceState == AssistanceStateEnum.igcComplete) {
      feedback = ChoreoConstants.incorrectCompleteIgcFeedback;
    }

    feedback == null
        ? await choreographer.requestWritingAssistance(manual: manual)
        : await choreographer.rerunWithFeedback(feedback);

    if (choreographer.assistanceState == AssistanceStateEnum.fetched) {
      showNextMatch();
    } else if (choreographer.assistanceState ==
        AssistanceStateEnum.suggesting) {
      _spanCardOverlayController.isOpen
          ? _spanCardOverlayController.close()
          : showSuggestion();
    } else if (autosend) {
      await send();
    } else {
      inputFocus.requestFocus();
    }
  }

  void showLanguageMismatchPopup({bool manual = false, bool autosend = false}) {
    if (!shouldShowLanguageMismatchPopupByActivity) {
      return;
    }

    final langCode = room.activityPlan!.req.targetLanguage;
    final targetLanguage = PLanguageStore.byLangCode(langCode);

    if (targetLanguage == null) {
      ErrorHandler.logError(
        e: "Skipping language mismatch popup for missing language",
        data: {'activity_lang_code': langCode},
      );
      _onRequestWritingAssistance(manual: manual, autosend: autosend);
      return;
    }

    LanguageMismatchRepo.setRoom(roomId);
    LanguageMismatchPopup.show(
      context: context,
      targetId: ChoreoConstants.inputTransformTargetKey,
      message: L10n.of(context).languageMismatchDesc,
      targetLanguage: targetLanguage,
      onConfirm: () => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onRequestWritingAssistance(manual: manual, autosend: autosend),
      ),
    );
  }

  Future<void> updateLanguageOnMismatch(LanguageModel target) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        clearSelectedEvents();
        await MatrixState.pangeaController.userController.updateProfile((
          profile,
        ) {
          final baseLangShort = profile.userSettings.sourceLanguage
              ?.split('-')
              .first;

          if (baseLangShort != null && baseLangShort == target.langCodeShort) {
            throw IdenticalLanguageException();
          }

          return profile.copyWith(
            userSettings: profile.userSettings.copyWith(
              targetLanguage: target.langCode,
            ),
          );
        }, waitForDataInSync: true);
      },
    );
    if (resp.isError) return;
    if (mounted) {
      messenger.hideCurrentSnackBar();
      // #Pangea
      messenger.showSnackBarAnnounced(
        SnackBar(
          content: Text(
            L10n.of(context).languageUpdated,
            textAlign: TextAlign.center,
          ),
        ),
      );
      // Pangea#
    }
  }

  void showDisableLanguageToolsPopup() {
    if (InstructionsEnum.disableLanguageTools.isToggledOff) {
      return;
    }

    InstructionsEnum.disableLanguageTools.setToggledOff(true);
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: const DisableLanguageToolsPopup(
        overlayId: 'disable_language_tools_popup',
      ),
      displayDetails: PositionedOverlayDisplayDetails(
        maxHeight: 325,
        maxWidth: 325,
        transformTargetId: ChoreoConstants.inputTransformTargetKey,
        overlayKey: 'disable_language_tools_popup',
      ),
      overlayPosition: OverlayPosition.above,
    );
  }

  Future<void> _showAnalyticsFeedback(
    List<OneConstructUse> constructs,
    String eventId,
    String language,
  ) async {
    // Visual-only, best-effort. Because this now also runs from the background
    // decoupled-send path, the widget can be disposed mid-await; never touch
    // `context` after an await. `guardedAnalyticsFeedbackCounts` re-checks
    // `mounted` after each fetch and bails (null) cleanly, and we re-check once
    // more before rendering the overlay -- so navigation during the awaits can
    // never throw a late-context error (and never affects the recording).
    if (!mounted) return;
    final analyticsService = Matrix.of(context).analyticsDataService;
    final counts = await guardedAnalyticsFeedbackCounts(
      isMounted: () => mounted,
      fetchGrammar: () => analyticsService.getNewConstructCount(
        constructs,
        ConstructTypeEnum.morph,
        language,
      ),
      fetchVocab: () => analyticsService.getNewConstructCount(
        constructs,
        ConstructTypeEnum.vocab,
        language,
      ),
    );
    if (counts == null || !mounted) return;

    OverlayUtil.showOverlay(
      context: context,
      child: MessageAnalyticsFeedback(
        newGrammarConstructs: counts.grammar,
        newVocabConstructs: counts.vocab,
        close: () => MatrixState.pAnyState.closeOverlay(
          "msg_analytics_feedback_$eventId",
        ),
      ),
      displayDetails: TransformOverlayDisplayDetails(
        overlayKey: "msg_analytics_feedback_$eventId",
        transformTargetId: eventId,
        ignorePointer: true,
        closePrevOverlay: false,
        followerAnchor: Alignment.bottomRight,
        targetAnchor: Alignment.topRight,
      ),
    );
  }

  Future<void> showTokenFeedbackDialog(
    TokenInfoFeedbackRequestData requestData,
    String langCode,
    PangeaMessageEvent event,
  ) async {
    clearSelectedEvents();
    await TokenFeedbackUtil.showTokenFeedbackDialog(
      context,
      requestData: requestData,
      langCode: langCode,
      event: event,
    );
  }

  void toggleShowDropdown() {
    inputFocus.unfocus();
    activityController.toggleShowDropdown();

    if (!InstructionsEnum.showedActivityMenu.isToggledOff) {
      InstructionsEnum.showedActivityMenu.setToggledOff(true);
    }
  }

  Future<void> onLeave() async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).areYouSure,
      message: L10n.of(context).leaveRoomDescription,
      okLabel: L10n.of(context).leave,
      cancelLabel: L10n.of(context).cancel,
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: widget.room.leave,
    );

    if (result.isError) return;
    final r = Matrix.of(context).client.getRoomById(widget.room.id);
    if (r != null && r.membership != Membership.leave) {
      await Matrix.of(
        context,
      ).client.waitForRoomInSync(widget.room.id, leave: true);
    }

    if (!mounted) return;
    _closeLeftRoom();
  }

  Future<void> requestRegeneration(String eventId) async {
    final reason = await showTextInputDialog(
      context: context,
      title: L10n.of(context).requestRegeneration,
      hintText: L10n.of(context).optionalRegenerateReason,
      autoSubmit: true,
      maxLines: 5,
    );

    if (reason == null) return;

    clearSelectedEvents();
    await showFutureLoadingDialog(
      context: context,
      future: () => room.sendRegenerationRequest(eventId, reason: reason),
    );
  }
  // Pangea#

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  void toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    // #Pangea
    return LoadParticipantsBuilder(
      room: room,
      builder: (context, participants) {
        if (!room.participantListComplete && participants.loading) {
          return Scaffold(
            appBar: AppBar(leading: widget.backButton),
            body: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        // Pangea#
        final theme = Theme.of(context);
        return Row(
          children: [
            Expanded(child: ChatView(this)),
            ValueListenableBuilder(
              valueListenable: _displayChatDetailsColumn,
              builder: (context, displayChatDetailsColumn, _) =>
                  !FluffyThemes.isThreeColumnMode(context) ||
                      room.membership != Membership.join ||
                      !displayChatDetailsColumn
                  ? const SizedBox(height: double.infinity, width: 0)
                  : Container(
                      width: FluffyThemes.columnWidth,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(width: 1, color: theme.dividerColor),
                        ),
                      ),
                      child: ChatDetails(
                        roomId: roomId,
                        embeddedCloseButton: IconButton(
                          // #Pangea
                          tooltip: L10n.of(context).close,
                          // Pangea#
                          icon: const Icon(Icons.close),
                          onPressed: toggleDisplayChatDetailsColumn,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

enum AddPopupMenuActions {
  image,
  video,
  file,
  poll,
  photoCamera,
  videoCamera,
  location,
}
