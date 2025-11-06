import 'dart:async';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choregrapher_user_settings_extension.dart';
import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/choreo_mode_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';
import 'package:fluffychat/pangea/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/igc/igc_controller.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/text_editing/edit_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/text_editing/pangea_text_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../widgets/matrix.dart';
import 'choreographer_error_controller.dart';
import 'it/it_controller.dart';

class OpenMatchesException implements Exception {}

class ShowPaywallException implements Exception {}

class Choreographer extends ChangeNotifier {
  final PangeaController pangeaController;
  final ChatController chatController;

  late PangeaTextController textController;
  late ITController itController;
  late IgcController igcController;
  late ChoreographerErrorController errorService;

  ChoreoRecordModel? _choreoRecord;

  final ValueNotifier<bool> _isFetching = ValueNotifier(false);

  int _timesClicked = 0;
  Timer? _debounceTimer;
  String? _lastChecked;
  ChoreoModeEnum _choreoMode = ChoreoModeEnum.igc;

  StreamSubscription? _languageStream;
  StreamSubscription? _settingsUpdateStream;

  Choreographer(this.pangeaController, this.chatController) {
    _initialize();
  }

  int get timesClicked => _timesClicked;
  ValueNotifier<bool> get isFetching => _isFetching;
  ChoreoModeEnum get choreoMode => _choreoMode;
  String get currentText => textController.text;

  void _initialize() {
    textController = PangeaTextController(choreographer: this);
    textController.addListener(_onChange);

    errorService = ChoreographerErrorController();
    errorService.addListener(notifyListeners);

    itController = ITController(
      (e) => errorService.setErrorAndLock(ChoreoError(raw: e)),
    );
    itController.open.addListener(_onCloseIT);

    igcController = IgcController(
      (e) => errorService.setErrorAndLock(ChoreoError(raw: e)),
    );

    _languageStream =
        pangeaController.userController.languageStream.stream.listen((update) {
      clear();
      notifyListeners();
    });

    _settingsUpdateStream =
        pangeaController.userController.settingsUpdateStream.stream.listen((_) {
      notifyListeners();
    });
    clear();
  }

  void clear() {
    setChoreoMode(ChoreoModeEnum.igc);
    _lastChecked = null;
    _timesClicked = 0;
    _isFetching.value = false;
    _choreoRecord = null;
    itController.clear();
    itController.clearSourceText();
    igcController.clear();
    _resetDebounceTimer();
  }

  @override
  void dispose() {
    super.dispose();
    itController.dispose();
    errorService.dispose();
    textController.dispose();
    _languageStream?.cancel();
    _settingsUpdateStream?.cancel();
    _debounceTimer?.cancel();
    _isFetching.dispose();
    TtsController.stop();
  }

  void onPaste(value) {
    _initChoreoRecord();
    _choreoRecord!.pastedStrings.add(value);
  }

  void onClickSend() {
    if (assistanceState == AssistanceStateEnum.fetched) {
      _timesClicked++;

      // if user is doing IT, call closeIT here to
      // ensure source text is replaced when needed
      if (itController.open.value && _timesClicked > 1) {
        itController.closeIT();
      }
    }
  }

  void setChoreoMode(ChoreoModeEnum mode) {
    _choreoMode = mode;
    notifyListeners();
  }

  void _resetDebounceTimer() {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
    }
  }

  void _initChoreoRecord() {
    _choreoRecord ??= ChoreoRecordModel(
      originalText: textController.text,
      choreoSteps: [],
      openMatches: [],
    );
  }

  void _startLoading() {
    _lastChecked = textController.text;
    _isFetching.value = true;
    notifyListeners();
  }

  void _stopLoading() {
    _isFetching.value = false;
    notifyListeners();
  }

  Future<void> requestLanguageAssistance() =>
      _startWritingAssistance(manual: true);

  /// Handles any changes to the text input
  void _onChange() {
    if (_lastChecked != null && _lastChecked == textController.text) {
      return;
    }

    _lastChecked = textController.text;
    if (textController.editType == EditTypeEnum.it) {
      return;
    }

    if (textController.editType == EditTypeEnum.igc ||
        textController.editType == EditTypeEnum.itDismissed) {
      textController.editType = EditTypeEnum.keyboard;
      return;
    }

    // Close any open IGC overlays
    MatrixState.pAnyState.closeOverlay();
    if (errorService.isError) return;

    igcController.clear();
    if (textController.editType == EditTypeEnum.keyboard) {
      itController.clearSourceText();
    }

    _resetDebounceTimer();
    _debounceTimer ??= Timer(
      const Duration(milliseconds: ChoreoConstants.msBeforeIGCStart),
      () => _startWritingAssistance(),
    );

    //Note: we don't set the keyboard type on each keyboard stroke so this is how we default to
    //a change being from the keyboard unless explicitly set to one of the other
    //types when that action happens (e.g. an it/igc choice is selected)
    textController.editType = EditTypeEnum.keyboard;
  }

  Future<void> _startWritingAssistance({
    bool manual = false,
  }) async {
    if (errorService.isError || isRunningIT) return;
    final SubscriptionStatus canSendStatus =
        pangeaController.subscriptionController.subscriptionStatus;

    if (canSendStatus != SubscriptionStatus.subscribed ||
        l2Lang == null ||
        l1Lang == null ||
        (!igcEnabled && !itEnabled) ||
        (!isAutoIGCEnabled && !manual && _choreoMode != ChoreoModeEnum.it)) {
      return;
    }

    _resetDebounceTimer();
    _initChoreoRecord();
    _startLoading();
    await igcController.getIGCTextData(
      textController.text,
      chatController.room.getPreviousMessages(),
    );
    _acceptNormalizationMatches();
    _stopLoading();
  }

  Future<void> send([int recurrence = 0]) async {
    // if isFetching, already called to getLanguageHelp and hasn't completed yet
    // could happen if user clicked send button multiple times in a row
    if (_isFetching.value) return;

    if (errorService.isError) {
      await _sendWithIGC();
      return;
    }

    if (recurrence > 1) {
      ErrorHandler.logError(
        e: Exception("Choreographer send exceeded max recurrences"),
        level: SentryLevel.warning,
        data: {
          "currentText": chatController.sendController.text,
          "l1LangCode": l1LangCode,
          "l2LangCode": l2LangCode,
          "choreoRecord": _choreoRecord?.toJson(),
        },
      );
      await _sendWithIGC();
      return;
    }

    if (igcController.canShowFirstMatch) {
      throw OpenMatchesException();
    } else if (isRunningIT) {
      // If the user is in the middle of IT, don't send the message.
      // If they've already clicked the send button once, this will
      // not be true, so they can still send it if they want.
      return;
    }

    final subscriptionStatus =
        pangeaController.subscriptionController.subscriptionStatus;

    if (subscriptionStatus != SubscriptionStatus.subscribed) {
      if (subscriptionStatus == SubscriptionStatus.shouldShowPaywall) {
        throw ShowPaywallException();
      }
      chatController.send(message: chatController.sendController.text);
      return;
    }

    if (chatController.shouldShowLanguageMismatchPopup) {
      chatController.showLanguageMismatchPopup();
      return;
    }

    if (!igcController.hasIGCTextData && !itController.dismissed) {
      await _startWritingAssistance();
      // it's possible for this not to be true, i.e. if IGC has an error
      if (igcController.hasIGCTextData) {
        await send(recurrence + 1);
      }
    } else {
      await _sendWithIGC();
    }
  }

  Future<void> _sendWithIGC() async {
    if (chatController.sendController.text.trim().isEmpty) {
      return;
    }

    final message = chatController.sendController.text;
    final fakeEventId = chatController.sendFakeMessage();

    TokensResponseModel? tokensResp;
    if (l1LangCode != null && l2LangCode != null) {
      final res = await pangeaController.messageData
          .getTokens(
            repEventId: null,
            room: chatController.room,
            req: TokensRequestModel(
              fullText: message,
              senderL1: l1LangCode!,
              senderL2: l2LangCode!,
            ),
          )
          .timeout(const Duration(seconds: 10));
      tokensResp = res.isValue ? res.result : null;
    }

    final hasOriginalWritten = _choreoRecord?.includedIT == true &&
        itController.sourceText.value != null;

    chatController.send(
      message: message,
      originalSent: PangeaRepresentation(
        langCode: tokensResp?.detections.firstOrNull?.langCode ??
            LanguageKeys.unknownLanguage,
        text: message,
        originalSent: true,
        originalWritten: hasOriginalWritten,
      ),
      originalWritten: hasOriginalWritten
          ? PangeaRepresentation(
              langCode: l1LangCode ?? LanguageKeys.unknownLanguage,
              text: itController.sourceText.value!,
              originalWritten: true,
              originalSent: false,
            )
          : null,
      tokensSent: tokensResp != null
          ? PangeaMessageTokens(
              tokens: tokensResp.tokens,
              detections: tokensResp.detections,
            )
          : null,
      choreo: _choreoRecord,
      tempEventId: fakeEventId,
    );

    clear();
  }

  void openIT(PangeaMatchState itMatch) {
    if (!itMatch.updatedMatch.isITStart) {
      throw Exception("Attempted to open IT with a non-IT start match");
    }

    chatController.inputFocus.unfocus();
    setChoreoMode(ChoreoModeEnum.it);

    final sourceText = currentText;
    textController.setSystemText("", EditTypeEnum.it);
    itController.openIT(sourceText);
    igcController.clear();

    _initChoreoRecord();
    itMatch.setStatus(PangeaMatchStatusEnum.accepted);
    _choreoRecord!.addRecord(
      "",
      match: itMatch.updatedMatch,
    );
    notifyListeners();
  }

  void _onCloseIT() {
    if (itController.open.value) return;
    if (currentText.isEmpty && itController.sourceText.value != null) {
      textController.setSystemText(
        itController.sourceText.value!,
        EditTypeEnum.itDismissed,
      );
    }

    setChoreoMode(ChoreoModeEnum.igc);
    errorService.resetError();
    notifyListeners();
  }

  void onSubmitEdits(String text) {
    textController.setSystemText("", EditTypeEnum.it);
    itController.onSubmitEdits(text);
  }

  void onAcceptContinuance(int index) {
    final step = itController.onAcceptContinuance(index);
    textController.setSystemText(
      textController.text + step.continuances[step.chosen].text,
      EditTypeEnum.it,
    );

    _initChoreoRecord();
    _choreoRecord!.addRecord(textController.text, step: step);
    chatController.inputFocus.requestFocus();
    notifyListeners();
  }

  void clearMatches(Object error) {
    MatrixState.pAnyState.closeAllOverlays();
    igcController.clearMatches();
    errorService.setError(ChoreoError(raw: error));
  }

  void onAcceptReplacement({
    required PangeaMatchState match,
  }) {
    final updatedMatch = igcController.acceptReplacement(
      match,
      PangeaMatchStatusEnum.accepted,
    );

    textController.setSystemText(
      igcController.currentText!,
      EditTypeEnum.igc,
    );

    if (!updatedMatch.match.isNormalizationError()) {
      _initChoreoRecord();
      _choreoRecord!.addRecord(
        textController.text,
        match: updatedMatch,
      );
    }
    MatrixState.pAnyState.closeOverlay();
    chatController.inputFocus.requestFocus();
    notifyListeners();
  }

  void onUndoReplacement(PangeaMatchState match) {
    igcController.undoReplacement(match);
    _choreoRecord?.choreoSteps.removeWhere(
      (step) => step.acceptedOrIgnoredMatch == match.updatedMatch,
    );

    textController.setSystemText(
      igcController.currentText!,
      EditTypeEnum.igc,
    );
    MatrixState.pAnyState.closeOverlay();
    chatController.inputFocus.requestFocus();
    notifyListeners();
  }

  void onIgnoreReplacement({required PangeaMatchState match}) {
    final updatedMatch = igcController.ignoreReplacement(match);
    if (!updatedMatch.match.isNormalizationError()) {
      _initChoreoRecord();
      _choreoRecord!.addRecord(
        textController.text,
        match: updatedMatch,
      );
    }
    MatrixState.pAnyState.closeOverlay();
    chatController.inputFocus.requestFocus();
    notifyListeners();
  }

  void _acceptNormalizationMatches() {
    final normalizationsMatches = igcController.openNormalizationMatches;
    if (normalizationsMatches?.isEmpty ?? true) return;

    _initChoreoRecord();
    try {
      for (final match in normalizationsMatches!) {
        match.selectChoice(
          match.updatedMatch.match.choices!.indexWhere(
            (c) => c.isBestCorrection,
          ),
        );
        final updatedMatch = igcController.acceptReplacement(
          match,
          PangeaMatchStatusEnum.automatic,
        );

        textController.setSystemText(
          igcController.currentText!,
          EditTypeEnum.igc,
        );
        _choreoRecord!.addRecord(
          currentText,
          match: updatedMatch,
        );
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "currentText": currentText,
          "l1LangCode": l1LangCode,
          "l2LangCode": l2LangCode,
          "choreoRecord": _choreoRecord?.toJson(),
        },
      );
    }
    notifyListeners();
  }
}
