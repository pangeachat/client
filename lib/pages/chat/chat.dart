import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat_view.dart';
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
import 'package:fluffychat/pages/chat/recording_dialog.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/enum/use_type.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/models/choreo_record.dart';
import 'package:fluffychat/pangea/models/class_model.dart';
import 'package:fluffychat/pangea/models/representation_content_model.dart';
import 'package:fluffychat/pangea/models/student_analytics_summary_model.dart';
import 'package:fluffychat/pangea/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/utils/firebase_analytics.dart';
import 'package:fluffychat/pangea/utils/report_message.dart';
import 'package:fluffychat/pangea/widgets/chat/message_toolbar.dart';
import 'package:fluffychat/pangea/widgets/igc/pangea_text_controller.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import '../../utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

class ChatPage extends StatelessWidget {
  final String roomId;
  final String? shareText;
  final String? eventId;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareText,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context)!.oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Text(L10n.of(context)!.youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareText: shareText,
      eventId: eventId,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final String? shareText;
  final String? eventId;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.shareText,
    this.eventId,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  // #Pangea
  final PangeaController pangeaController = MatrixState.pangeaController;
  late Choreographer choreographer = Choreographer(pangeaController, this);
  // Pangea#
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;

  late Client sendingClient;

  Timeline? timeline;

  String? readMarkerEventId;

  String get roomId => widget.room.id;

  final AutoScrollController scrollController = AutoScrollController();

  FocusNode inputFocus = FocusNode();
  StreamSubscription<html.Event>? onFocusSub;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  // #Pangea
  // bool dragging = false;

  // void onDragEntered(_) => setState(() => dragging = true);

  // void onDragExited(_) => setState(() => dragging = false);

  // void onDragDone(DropDoneDetails details) async {
  //   setState(() => dragging = false);
  //   if (details.files.isEmpty) return;
  //   final result = await showFutureLoadingDialog(
  //     context: context,
  //     future: () async {
  //       final clientConfig = await room.client.getConfig();
  //       final maxUploadSize = clientConfig.mUploadSize ?? 100 * 1024 * 1024;
  //       final matrixFiles = await Future.wait(
  //         details.files.map(
  //           (xfile) async {
  //             final length = await xfile.length();
  //             if (length > maxUploadSize) {
  //               throw FileTooBigMatrixException(length, maxUploadSize);
  //             }
  //             return MatrixFile(
  //               bytes: await xfile.readAsBytes(),
  //               name: xfile.name,
  //               mimeType: xfile.mimeType,
  //             ).detectFileType;
  //           },
  //         ),
  //       );
  //       return matrixFiles;
  //     },
  //   );
  //   final matrixFiles = result.result;
  //   if (matrixFiles == null || matrixFiles.isEmpty) return;

  //   await showAdaptiveDialog(
  //     context: context,
  //     builder: (c) => SendFileDialog(
  //       files: matrixFiles,
  //       room: room,
  //     ),
  //   );
  // }
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

  void saveSelectedEvent(context) => selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;

  Event? editEvent;

  bool _scrolledUp = false;

  bool get showScrollDownButton =>
      _scrolledUp || timeline?.allowNewEvent == false;

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;

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
    context.go('/rooms');
  }

  // #Pangea
  void archiveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.archive,
    );
    if (success.error != null) return;
    context.go('/rooms');
  }
  // Pangea#

  EmojiPickerType emojiPickerType = EmojiPickerType.keyboard;

  // #Pangea
  // void requestHistory([_]) async {
  Future<void> requestHistory() async {
    if (timeline == null) return;
    // Pangea#
    if (!timeline!.canRequestHistory) return;
    Logs().v('Requesting history...');
    await timeline!.requestHistory(historyCount: _loadHistoryCount);
  }

  void requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    if (!timeline.canRequestFuture) return;
    Logs().v('Requesting future...');
    final mostRecentEventId = timeline.events.first.eventId;
    await timeline.requestFuture(historyCount: _loadHistoryCount);
    setReadMarker(eventId: mostRecentEventId);
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;
    if (timeline?.allowNewEvent == false ||
        scrollController.position.pixels > 0 && _scrolledUp == false) {
      setState(() => _scrolledUp = true);
    } else if (scrollController.position.pixels <= 0 && _scrolledUp == true) {
      setState(() => _scrolledUp = false);
      setReadMarker();
    }

    if (scrollController.position.pixels == 0 ||
        scrollController.position.pixels == 64) {
      requestFuture();
    }
  }

  void _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = widget.shareText ?? prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  // #Pangea
  bool showPermissionsError = false;
  // #Pangea

  @override
  void initState() {
    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      Matrix.of(context).store.getBool(SettingKeys.displayChatDetailsColumn) ??
          false,
    );

    sendingClient = Matrix.of(context).client;
    WidgetsBinding.instance.addObserver(this);
    // #Pangea
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;
      debugPrint(
        "chat.dart l1 ${pangeaController.languageController.activeL1Code(roomID: roomId)}",
      );
      debugPrint(
        "chat.dart l2 ${pangeaController.languageController.activeL2Code(roomID: roomId)}",
      );
      if (mounted) {
        pangeaController.languageController.showDialogOnEmptyLanguage(
          context,
          () => Future.delayed(
            Duration.zero,
            () => setState(
              () {},
            ),
          ),
        );
      }
      await Matrix.of(context).client.roomsLoading;
      choreographer.setRoomId(roomId);
      choreographer.messageOptions.resetSelectedDisplayLang();
      choreographer.stateListener.stream.listen((event) {
        debugPrint("chat.dart choreo event $event");
        setState(() {});
      });
      showPermissionsError = !pangeaController.permissionsController
              .isToolEnabled(ToolSetting.interactiveTranslator, room) ||
          !pangeaController.permissionsController
              .isToolEnabled(ToolSetting.interactiveGrammar, room);
    });

    Future.delayed(
      const Duration(seconds: 5),
      () {
        if (mounted) setState(() => showPermissionsError = false);
      },
    );
    // Pangea#
    _tryLoadTimeline();
    if (kIsWeb) {
      onFocusSub = html.window.onFocus.listen((_) => setReadMarker());
    }
  }

  void _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    try {
      await loadTimelineFuture;
      if (initialEventId != null) scrollToEventId(initialEventId);

      final fullyRead = room.fullyRead;
      if (fullyRead.isEmpty) {
        setReadMarker();
        return;
      }
      if (timeline?.events.any((event) => event.eventId == fullyRead) ??
          false) {
        Logs().v('Scroll up to visible event', fullyRead);
        setReadMarker();
        return;
      }
      if (!mounted) return;
      _showScrollUpMaterialBanner(fullyRead);
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
    setState(() {});
  }

  Future<void>? loadTimelineFuture;

  int? animateInEventIndex;

  void onInsert(int i) {
    if (timeline?.events[i].status == EventStatus.synced) {
      final index = timeline!.events.firstIndexWhereNotError;
      if (i == index) setReadMarker(eventId: timeline?.events[i].eventId);
    }

    // setState will be called by updateView() anyway
    animateInEventIndex = i;
  }

  // #Pangea
  List<Event> get visibleEvents =>
      timeline?.events
          .where(
            (x) => x.isVisibleInGui,
          )
          .toList() ??
      <Event>[];
  // Pangea#

  Future<void> _getTimeline({
    String? eventContextId,
  }) async {
    await Matrix.of(context).client.roomsLoading;
    await Matrix.of(context).client.accountDataLoading;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixId || eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    try {
      timeline = await room.getTimeline(
        onUpdate: updateView,
        eventContextId: eventContextId,
        onInsert: onInsert,
      );
      // #Pangea
      if (visibleEvents.length < 10) {
        int prevNumEvents = timeline!.events.length;
        await requestHistory();
        int numRequests = 0;
        while (timeline!.events.length > prevNumEvents &&
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
    if (state != AppLifecycleState.resumed) return;
    setReadMarker();
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp) return;
    if (scrollUpBannerEventId != null) return;
    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    // Do not send read markers when app is not in foreground
    // #Pangea
    try {
      // Pangea#
      if (kIsWeb && !Matrix.of(context).webHasFocus) return;
      // #Pangea
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s);
      return;
    }
    // Pangea#
    if (!kIsWeb &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    // ignore: unawaited_futures
    _setReadMarkerFuture = timeline
        .setReadMarker(
      eventId: eventId,
      public: AppConfig.sendPublicReadReceipts,
    )
        .then((_) {
      _setReadMarkerFuture = null;
    });
    if (eventId == null || eventId == timeline.room.lastEvent?.eventId) {
      Matrix.of(context).backgroundPush?.cancelNotification(roomId);
    }
  }

  @override
  void dispose() {
    timeline?.cancelSubscriptions();
    timeline = null;
    inputFocus.removeListener(_inputFocusListener);
    onFocusSub?.cancel();
    //#Pangea
    choreographer.stateListener.close();
    choreographer.dispose();
    //Pangea#
    super.dispose();
  }

  // #Pangea
  // TextEditingController sendController = TextEditingController();
  PangeaTextController get sendController => choreographer.textController;
  // #Pangea

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
        Matrix.of(context).setActiveClient(c);
      });

  // #Pangea
  final List<String> edittingEvents = [];
  void clearEdittingEvent(String eventId) {
    edittingEvents.remove(eventId);
    setState(() {});
  }

  // Future<void> send() async {
  // Original send function gets the tx id within the matrix lib,
  // but for choero, the tx id is generated before the message send.
  // Also, adding PangeaMessageData
  Future<void> send({
    PangeaRepresentation? originalSent,
    PangeaRepresentation? originalWritten,
    PangeaMessageTokens? tokensSent,
    PangeaMessageTokens? tokensWritten,
    ChoreoRecord? choreo,
    UseType? useType,
  }) async {
    // Pangea#
    if (sendController.text.trim().isEmpty) return;
    _storeInputTimeoutTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('draft_$roomId');
    var parseCommands = true;

    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      final l10n = L10n.of(context)!;
      final dialogResult = await showOkCancelAlertDialog(
        context: context,
        title: l10n.commandInvalid,
        message: l10n.commandMissing(commandMatch[0]!),
        okLabel: l10n.sendAsText,
        cancelLabel: l10n.cancel,
      );
      if (dialogResult == OkCancelResult.cancel) return;
      parseCommands = false;
    }

    // ignore: unawaited_futures
    // #Pangea
    // room.sendTextEvent(
    //   sendController.text,
    //   inReplyTo: replyEvent,
    //   editEventId: editEvent?.eventId,
    //   parseCommands: parseCommands,
    // );
    final previousEdit = editEvent;
    room
        .pangeaSendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      editEventId: editEvent?.eventId,
      parseCommands: parseCommands,
      originalSent: originalSent,
      originalWritten: originalWritten,
      tokensSent: tokensSent,
      tokensWritten: tokensWritten,
      choreo: choreo,
      useType: useType,
    )
        .then(
      (String? msgEventId) async {
        // #Pangea
        setState(() {
          if (previousEdit != null) {
            edittingEvents.add(previousEdit.eventId);
          }
        });

        GoogleAnalytics.sendMessage(
          room.id,
          room.classCode,
          useType ?? UseType.un,
        );

        if (msgEventId == null) {
          ErrorHandler.logError(
            e: Exception('msgEventId is null'),
            s: StackTrace.current,
          );
          return;
        }

        // ensure that analytics room exists / is created for the active langCode
        await room.ensureAnalyticsRoomExists();
        pangeaController.myAnalytics.handleMessage(
          room,
          RecentMessageRecord(
            eventId: msgEventId,
            chatId: room.id,
            useType: useType ?? UseType.un,
            time: DateTime.now(),
          ),
          isEdit: previousEdit != null,
        );

        if (choreo != null &&
            tokensSent != null &&
            originalSent?.langCode ==
                pangeaController.languageController
                    .activeL2Code(roomID: room.id)) {
          pangeaController.myAnalytics.saveConstructsMixed(
            [
              // ...choreo.toVocabUse(tokensSent.tokens, room.id, msgEventId),
              ...choreo.toGrammarConstructUse(msgEventId, room.id),
            ],
            originalSent!.langCode,
            isEdit: previousEdit != null,
          );
        }
      },
      onError: (err, stack) => ErrorHandler.logError(e: err, s: stack),
    );
    // Pangea#
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );

    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
  }

  void sendFileAction() async {
    final result = await AppLock.of(context).pauseWhile(
      FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      ),
    );
    if (result == null || result.files.isEmpty) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: result.files
            .map(
              (xfile) => MatrixFile(
                bytes: xfile.bytes!,
                name: xfile.name,
              ).detectFileType,
            )
            .toList(),
        room: room,
      ),
    );
  }

  void sendImageFromClipBoard(Uint8List? image) async {
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [
          MatrixFile(
            bytes: image!,
            name: "image from Clipboard",
          ).detectFileType,
        ],
        room: room,
      ),
    );
  }

  void sendImageAction() async {
    final result = await AppLock.of(context).pauseWhile(
      FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      ),
    );
    if (result == null || result.files.isEmpty) return;

    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: result.files
            .map(
              (xfile) => MatrixFile(
                bytes: xfile.bytes!,
                name: xfile.name,
              ).detectFileType,
            )
            .toList(),
        room: room,
      ),
    );
  }

  void openCameraAction() async {
    // Make sure the textfield is unfocused before opening the camera
    FocusScope.of(context).requestFocus(FocusNode());
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [
          MatrixImageFile(
            bytes: bytes,
            name: file.path,
          ),
        ],
        room: room,
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
    final bytes = await file.readAsBytes();
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [
          MatrixVideoFile(
            bytes: bytes,
            name: file.path,
          ),
        ],
        room: room,
      ),
    );
  }

  void voiceMessageAction() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt < 19) {
        showOkAlertDialog(
          context: context,
          title: L10n.of(context)!.unsupportedAndroidVersion,
          message: L10n.of(context)!.unsupportedAndroidVersionLong,
          okLabel: L10n.of(context)!.close,
        );
        return;
      }
    }

    // #Pangea
    // if (await AudioRecorder().hasPermission() == false) return;
    // Pangea#
    final result = await showDialog<RecordingResult>(
      context: context,
      barrierDismissible: false,
      builder: (c) => const RecordingDialog(),
    );
    if (result == null) return;
    final audioFile = File(result.path);
    final file = MatrixAudioFile(
      bytes: audioFile.readAsBytesSync(),
      name: audioFile.path,
    );
    await room.sendFileEvent(
      file,
      inReplyTo: replyEvent,
      extraContent: {
        'info': {
          ...file.info,
          'duration': result.duration,
        },
        'org.matrix.msc3245.voice': {},
        'org.matrix.msc1767.audio': {
          'duration': result.duration,
          'waveform': result.waveform,
        },
      },
    ).catchError((e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            (e as Object).toLocalizedString(context),
          ),
        ),
      );
      return null;
    });
    setState(() {
      replyEvent = null;
    });
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
    emojiPickerType = EmojiPickerType.keyboard;
    setState(() => showEmojiPicker = !showEmojiPicker);
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      emojiPickerType = EmojiPickerType.keyboard;
      setState(() => showEmojiPicker = false);
    }
  }

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
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)!));
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event.getDisplayEvent(timeline!).calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)!),
            withSenderNamePrefix: true,
          );
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  void reportEventAction() async {
    final event = selectedEvents.single;
    final score = await showConfirmationDialog<int>(
      context: context,
      title: L10n.of(context)!.reportMessage,
      message: L10n.of(context)!.howOffensiveIsThisContent,
      cancelLabel: L10n.of(context)!.cancel,
      okLabel: L10n.of(context)!.ok,
      actions: [
        AlertDialogAction(
          key: -100,
          label: L10n.of(context)!.extremeOffensive,
        ),
        AlertDialogAction(
          key: -50,
          label: L10n.of(context)!.offensive,
        ),
        AlertDialogAction(
          key: 0,
          label: L10n.of(context)!.inoffensive,
        ),
      ],
    );
    if (score == null) return;
    final reason = await showTextInputDialog(
      context: context,
      title: L10n.of(context)!.whyDoYouWantToReportThis,
      okLabel: L10n.of(context)!.ok,
      cancelLabel: L10n.of(context)!.cancel,
      textFields: [DialogTextField(hintText: L10n.of(context)!.reason)],
    );
    if (reason == null || reason.single.isEmpty) return;
    // #Pangea
    // final result = await showFutureLoadingDialog(
    //   context: context,
    //   future: () => Matrix.of(context).client.reportContent(
    //         event.roomId!,
    //         event.eventId,
    //         reason: reason.single,
    //         score: score,
    //       ),
    // );
    // if (result.error != null) return;
    try {
      await reportMessage(
        context,
        roomId,
        reason.single,
        event.senderId,
        event.content['body'].toString(),
      );
    } catch (err) {
      ErrorHandler.logError(e: err, s: StackTrace.current);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.of(context)!.oopsSomethingWentWrong,
          ),
        ),
      );
    }
    // final result = await showFutureLoadingDialog(
    //   context: context,
    //   future: () => Matrix.of(context).client.reportContent(
    //         event.roomId!,
    //         event.eventId,
    //         reason: reason.single,
    //         score: score,
    //       ),
    // );
    // if (result.error != null) return;
    // Pangea#
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context)!.contentHasBeenReported)),
    );
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
      setState(selectedEvents.clear);
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
            title: L10n.of(context)!.redactMessage,
            message: L10n.of(context)!.redactMessageDescription,
            isDestructiveAction: true,
            textFields: [
              DialogTextField(
                hintText: L10n.of(context)!.optionalRedactReason,
              ),
            ],
            okLabel: L10n.of(context)!.remove,
            cancelLabel: L10n.of(context)!.cancel,
          )
        : <String>[];
    if (reasonInput == null) return;
    final reason = reasonInput.single.isEmpty ? null : reasonInput.single;
    for (final event in selectedEvents) {
      await showFutureLoadingDialog(
        context: context,
        future: () async {
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
              await Event.fromJson(event.toJson(), room).redactEvent(
                reason: reason,
              );
            }
          } else {
            await event.cancelSend();
          }
        },
      );
    }
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
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
          !(clients!.any((cl) => event.senderId == cl!.userID))) return false;
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        // #Pangea
        selectedEvents.single.messageType != MessageTypes.Text ||
        // Pangea#
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle
        .any((cl) => selectedEvents.first.senderId == cl!.userID);
  }

  void forwardEventsAction() async {
    if (selectedEvents.length == 1) {
      Matrix.of(context).shareContent =
          selectedEvents.first.getDisplayEvent(timeline!).content;
    } else {
      Matrix.of(context).shareContent = {
        'msgtype': 'm.text',
        'body': _getSelectedEventString(),
      };
    }
    setState(() => selectedEvents.clear());
    context.go('/rooms');
  }

  void sendAgainAction() {
    final event = selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void scrollToEventId(String eventId) async {
    final eventIndex = timeline!.events.indexWhere((e) => e.eventId == eventId);
    if (eventIndex == -1) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(context, 'Unable to load timeline after scroll to ID')
              .onErrorCallback,
        );
      });
      await loadTimelineFuture;
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(eventId);
      });
      return;
    }
    setState(() {
      scrollToEventIdMarker = eventId;
    });
    await scrollController.scrollToIndex(
      eventIndex,
      preferPosition: AutoScrollPosition.middle,
    );
    _updateScrollController();
  }

  void scrollDown() async {
    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(context, 'Unable to load timeline after scroll down')
              .onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    scrollController.jumpTo(0);
  }

  void onEmojiSelected(_, Emoji? emoji) {
    switch (emojiPickerType) {
      case EmojiPickerType.reaction:
        senEmojiReaction(emoji);
        break;
      case EmojiPickerType.keyboard:
        typeEmoji(emoji);
        onInputBarChanged(sendController.text);
        break;
    }
  }

  void senEmojiReaction(Emoji? emoji) {
    setState(() => showEmojiPicker = false);
    if (emoji == null) return;
    // make sure we don't send the same emoji twice
    if (_allReactionEvents.any(
      (e) => e.content.tryGetMap('m.relates_to')?['key'] == emoji.emoji,
    )) {
      return;
    }
    return sendEmojiAction(emoji.emoji);
  }

  void typeEmoji(Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
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

  late Iterable<Event> _allReactionEvents;

  void emojiPickerBackspace() {
    switch (emojiPickerType) {
      case EmojiPickerType.reaction:
        setState(() => showEmojiPicker = false);
        break;
      case EmojiPickerType.keyboard:
        sendController
          ..text = sendController.text.characters.skipLast(1).toString()
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: sendController.text.length),
          );
        break;
    }
  }

  void pickEmojiReactionAction(Iterable<Event> allReactionEvents) async {
    _allReactionEvents = allReactionEvents;
    emojiPickerType = EmojiPickerType.reaction;
    setState(() => showEmojiPicker = true);
  }

  void sendEmojiAction(String? emoji) async {
    final events = List<Event>.from(selectedEvents);
    setState(() => selectedEvents.clear());
    for (final event in events) {
      await room.sendReaction(
        event.eventId,
        emoji!,
      );
    }
  }

  void clearSelectedEvents() => setState(() {
        selectedEvents.clear();
        showEmojiPicker = false;
        //#Pangea
        choreographer.messageOptions.resetSelectedDisplayLang();
        //Pangea#
      });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void editSelectedEventAction() {
    final client = currentRoomBundle.firstWhere(
      (cl) => selectedEvents.first.senderId == cl!.userID,
      orElse: () => null,
    );
    if (client == null) {
      return;
    }
    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = selectedEvents.first;
      sendController.text =
          editEvent!.getDisplayEvent(timeline!).calcLocalizedBodyFallback(
                MatrixLocals(L10n.of(context)!),
                withSenderNamePrefix: false,
                hideReply: true,
              );
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void goToNewRoomAction() async {
    if (OkCancelResult.ok !=
        await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context)!.goToTheNewRoom,
          message: room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .body,
          okLabel: L10n.of(context)!.ok,
          cancelLabel: L10n.of(context)!.cancel,
        )) {
      return;
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.client.joinRoom(
        room
            .getState(EventTypes.RoomTombstone)!
            .parsedTombstoneContent
            .replacementRoom,
      ),
    );
    await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (result.error == null) {
      context.go('/rooms/${result.result!}');
    }
  }

  void onSelectMessage(Event event) {
    // #Pangea
    if (choreographer.itController.isOpen) {
      return;
    }
    // Pangea#
    if (!event.redacted) {
      if (selectedEvents.contains(event)) {
        setState(
          () => selectedEvents.remove(event),
        );
      } else {
        setState(
          () => selectedEvents.add(event),
        );
      }
      selectedEvents.sort(
        (a, b) => a.originServerTs.compareTo(b.originServerTs),
      );
    }
  }

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
  void onInputBarSubmitted(String _, BuildContext context) {
    // void onInputBarSubmitted(_) {
    //   send();
    choreographer.send(context);
    // Pangea#
    FocusScope.of(context).requestFocus(inputFocus);
  }

  //#Pangea
  void onAddPopupMenuButtonSelected(String? choice) {
    // void onAddPopupMenuButtonSelected(String choice) {
    if (choice == null) {
      debugger(when: kDebugMode);
    }
    //Pangea#
    if (choice == 'file') {
      sendFileAction();
    }
    if (choice == 'image') {
      sendImageAction();
    }
    if (choice == 'camera') {
      openCameraAction();
    }
    if (choice == 'camera-video') {
      openVideoCameraAction();
    }
    if (choice == 'location') {
      sendLocationAction();
    }
  }

  unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context)!.unpin,
      message: L10n.of(context)!.confirmEventUnpin,
      okLabel: L10n.of(context)!.unpin,
      cancelLabel: L10n.of(context)!.cancel,
    );
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent() {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = selectedEvents.map((e) => e.eventId).toSet();
    final unpin = selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('draft_$roomId', text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (AppConfig.sendTypingNotifications) {
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

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  void onPhoneButtonTap() async {
    // VoIP required Android SDK 21
    if (PlatformInfos.isAndroid) {
      DeviceInfoPlugin().androidInfo.then((value) {
        if (value.version.sdkInt < 21) {
          Navigator.pop(context);
          showOkAlertDialog(
            context: context,
            title: L10n.of(context)!.unsupportedAndroidVersion,
            message: L10n.of(context)!.unsupportedAndroidVersionLong,
            okLabel: L10n.of(context)!.close,
          );
        }
      });
    }
    final callType = await showModalActionSheet<CallType>(
      context: context,
      title: L10n.of(context)!.warning,
      message: L10n.of(context)!.videoCallsBetaWarning,
      cancelLabel: L10n.of(context)!.cancel,
      actions: [
        SheetAction(
          label: L10n.of(context)!.voiceCall,
          icon: Icons.phone_outlined,
          key: CallType.kVoice,
        ),
        SheetAction(
          label: L10n.of(context)!.videoCall,
          icon: Icons.video_call_outlined,
          key: CallType.kVideo,
        ),
      ],
    );
    if (callType == null) return;

    final voipPlugin = Matrix.of(context).voipPlugin;
    try {
      await voipPlugin!.voip.inviteToCall(room, callType);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
  }

  void cancelReplyEventAction() => setState(() {
        if (editEvent != null) {
          sendController.text = pendingText;
          pendingText = '';
        }
        replyEvent = null;
        editEvent = null;
      });

  // #Pangea
  double? availableSpace;
  double? inputRowSize;
  bool? lastState;
  bool get isRowScrollable {
    if (availableSpace == null || inputRowSize == null) {
      if (lastState == null) {
        lastState = false;
        Future.delayed(Duration.zero, () {
          setState(() {});
        });
      }
      return false;
    }
    const double offSetValue = 10;
    final bool currentState = inputRowSize! > (availableSpace! - offSetValue);
    if (!lastState! && currentState) {
      Future.delayed(Duration.zero, () {
        setState(() {});
      });
    }
    if (lastState! && !currentState) {
      Future.delayed(Duration.zero, () {
        setState(() {});
      });
    }
    lastState = currentState;
    return currentState;
  }

  final Map<String, PangeaMessageEvent> _pangeaMessageEvents = {};
  final Map<String, ToolbarDisplayController> _toolbarDisplayControllers = {};

  void setPangeaMessageEvent(String eventId) {
    final Event? event = timeline!.events.firstWhereOrNull(
      (e) => e.eventId == eventId,
    );
    if (event == null || timeline == null) return;
    _pangeaMessageEvents[eventId] = PangeaMessageEvent(
      event: event,
      timeline: timeline!,
      ownMessage: event.senderId == room.client.userID,
    );
  }

  void setToolbarDisplayController(
    String eventId, {
    Event? nextEvent,
    Event? previousEvent,
  }) {
    final Event? event = timeline!.events.firstWhereOrNull(
      (e) => e.eventId == eventId,
    );
    if (event == null || timeline == null) return;
    if (_pangeaMessageEvents[eventId] == null) {
      setPangeaMessageEvent(eventId);
      if (_pangeaMessageEvents[eventId] == null) return;
    }

    try {
      _toolbarDisplayControllers[eventId] = ToolbarDisplayController(
        targetId: event.eventId,
        pangeaMessageEvent: _pangeaMessageEvents[eventId]!,
        immersionMode: choreographer.immersionMode,
        controller: this,
        nextEvent: nextEvent,
        previousEvent: previousEvent,
      );
      _toolbarDisplayControllers[eventId]!.setToolbar();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        m: "Failed to set toolbar display controller",
        data: {
          "eventId": eventId,
          "event": event.toJson(),
          "pangeaMessageEvent": _pangeaMessageEvents[eventId]?.toString(),
        },
      );
    }
  }

  PangeaMessageEvent? getPangeaMessageEvent(String eventId) {
    if (_pangeaMessageEvents[eventId] == null) {
      setPangeaMessageEvent(eventId);
    }
    return _pangeaMessageEvents[eventId];
  }

  ToolbarDisplayController? getToolbarDisplayController(
    String eventId, {
    Event? nextEvent,
    Event? previousEvent,
  }) {
    if (_toolbarDisplayControllers[eventId] == null) {
      setToolbarDisplayController(
        eventId,
        nextEvent: nextEvent,
        previousEvent: previousEvent,
      );
    }
    return _toolbarDisplayControllers[eventId];
  }
  // Pangea#

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  void toggleDisplayChatDetailsColumn() async {
    await Matrix.of(context).store.setBool(
          SettingKeys.displayChatDetailsColumn,
          !_displayChatDetailsColumn.value,
        );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: ChatView(this),
          ),
          AnimatedSize(
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            child: ValueListenableBuilder(
              valueListenable: _displayChatDetailsColumn,
              builder: (context, displayChatDetailsColumn, _) {
                if (!FluffyThemes.isThreeColumnMode(context) ||
                    room.membership != Membership.join ||
                    !displayChatDetailsColumn) {
                  return const SizedBox(
                    height: double.infinity,
                    width: 0,
                  );
                }
                return Container(
                  width: FluffyThemes.columnWidth,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  child: ChatDetails(
                    roomId: roomId,
                    embeddedCloseButton: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: toggleDisplayChatDetailsColumn,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

enum EmojiPickerType { reaction, keyboard }

extension on List<Event> {
  int get firstIndexWhereNotError {
    if (isEmpty) return 0;
    final index = indexWhere((event) => !event.status.isError);
    if (index == -1) return length;
    return index;
  }
}
