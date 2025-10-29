import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choregrapher_user_settings_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/controllers/igc_controller.dart';
import 'package:fluffychat/pangea/choreographer/controllers/pangea_text_controller.dart';
import 'package:fluffychat/pangea/choreographer/enums/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';
import 'package:fluffychat/pangea/choreographer/enums/edit_type.dart';
import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/choreo_record.dart';
import 'package:fluffychat/pangea/choreographer/models/it_step.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';
import 'package:fluffychat/pangea/events/repo/token_api_models.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import '../../../widgets/matrix.dart';
import 'error_service.dart';
import 'it_controller.dart';

class OpenMatchesException implements Exception {}

class ShowPaywallException implements Exception {}

class Choreographer extends ChangeNotifier {
  final PangeaController pangeaController;
  final ChatController chatController;

  late PangeaTextController textController;
  late ITController itController;
  late IgcController igc;
  late ErrorService errorService;

  ChoreoRecord? _choreoRecord;

  bool _isFetching = false;
  int _timesClicked = 0;

  Timer? _debounceTimer;
  String? _lastChecked;
  ChoreoMode _choreoMode = ChoreoMode.igc;
  String? _sourceText;

  StreamSubscription? _languageStream;
  StreamSubscription? _settingsUpdateStream;

  Choreographer(this.pangeaController, this.chatController) {
    _initialize();
  }

  int get timesClicked => _timesClicked;
  bool get isFetching => _isFetching;
  ChoreoMode get choreoMode => _choreoMode;

  String? get sourceText => _sourceText;
  String get currentText => textController.text;

  void _initialize() {
    textController = PangeaTextController(choreographer: this);

    itController = ITController(this);
    igc = IgcController(this);

    errorService = ErrorService();
    errorService.addListener(notifyListeners);

    textController.addListener(_onChange);

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
    _choreoMode = ChoreoMode.igc;
    _lastChecked = null;
    _timesClicked = 0;
    _isFetching = false;
    _choreoRecord = null;
    _sourceText = null;
    itController.clear();
    igc.clear();
    _resetDebounceTimer();
  }

  @override
  void dispose() {
    super.dispose();
    errorService.dispose();
    textController.dispose();
    _languageStream?.cancel();
    _settingsUpdateStream?.cancel();
    TtsController.stop();
  }

  void onPaste(value) {
    _initChoreoRecord();
    _choreoRecord!.pastedStrings.add(value);
  }

  void onClickSend() {
    if (assistanceState == AssistanceState.fetched) {
      _timesClicked++;

      // if user is doing IT, call closeIT here to
      // ensure source text is replaced when needed
      if (isITOpen && _timesClicked > 1) {
        closeIT();
      }
    }
  }

  void setChoreoMode(ChoreoMode mode) {
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
    _choreoRecord ??= ChoreoRecord(
      originalText: textController.text,
      choreoSteps: [],
      openMatches: [],
    );
  }

  void _startLoading() {
    _lastChecked = textController.text;
    _isFetching = true;
    notifyListeners();
  }

  void _stopLoading() {
    _isFetching = false;
    notifyListeners();
  }

  Future<PangeaMatchState?> requestLanguageAssistance() async {
    await _getLanguageAssistance(manual: true);
    if (igc.canShowFirstMatch) {
      return igc.onShowFirstMatch();
    }
    return null;
  }

  Future<void> send() async {
    // if isFetching, already called to getLanguageHelp and hasn't completed yet
    // could happen if user clicked send button multiple times in a row
    if (_isFetching) return;

    if (igc.canShowFirstMatch) {
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

    if (!igc.hasIGCTextData && !itController.dismissed) {
      await _getLanguageAssistance();
      await send();
    } else {
      _sendWithIGC();
    }
  }

  /// Handles any changes to the text input
  void _onChange() {
    if (_lastChecked != null && _lastChecked == textController.text) {
      return;
    }

    _lastChecked = textController.text;

    if (textController.editType == EditType.igc ||
        textController.editType == EditType.itDismissed) {
      textController.editType = EditType.keyboard;
      return;
    }

    // Close any open IGC/IT overlays
    MatrixState.pAnyState.closeOverlay();
    if (errorService.isError) return;

    igc.clear();
    _resetDebounceTimer();

    if (textController.editType == EditType.it) {
      _getLanguageAssistance();
    } else {
      _sourceText = null;
      _debounceTimer ??= Timer(
        const Duration(milliseconds: ChoreoConstants.msBeforeIGCStart),
        () => _getLanguageAssistance(),
      );
    }

    //Note: we don't set the keyboard type on each keyboard stroke so this is how we default to
    //a change being from the keyboard unless explicitly set to one of the other
    //types when that action happens (e.g. an it/igc choice is selected)
    textController.editType = EditType.keyboard;
  }

  /// Fetches the language help for the current text, including grammar correction, language detection,
  /// tokens, and translations. Includes logic to exit the flow if the user is not subscribed, if the tools are not enabled, or
  /// or if autoIGC is not enabled and the user has not manually requested it.
  /// [onlyTokensAndLanguageDetection] will
  Future<void> _getLanguageAssistance({
    bool manual = false,
  }) async {
    if (errorService.isError) return;
    final SubscriptionStatus canSendStatus =
        pangeaController.subscriptionController.subscriptionStatus;

    if (canSendStatus != SubscriptionStatus.subscribed ||
        l2Lang == null ||
        l1Lang == null ||
        (!igcEnabled && !itEnabled) ||
        (!isAutoIGCEnabled && !manual && _choreoMode != ChoreoMode.it)) {
      return;
    }

    _resetDebounceTimer();
    _initChoreoRecord();

    _startLoading();
    await (isRunningIT ? itController.continueIT() : igc.getIGCTextData());
    _stopLoading();
  }

  Future<void> _sendWithIGC() async {
    if (chatController.sendController.text.trim().isEmpty) {
      return;
    }

    final message = chatController.sendController.text;
    final fakeEventId = chatController.sendFakeMessage();
    final PangeaRepresentation? originalWritten =
        _choreoRecord?.includedIT == true && _sourceText != null
            ? PangeaRepresentation(
                langCode: l1LangCode ?? LanguageKeys.unknownLanguage,
                text: _sourceText!,
                originalWritten: true,
                originalSent: false,
              )
            : null;

    PangeaMessageTokens? tokensSent;
    PangeaRepresentation? originalSent;
    try {
      TokensResponseModel? res;
      if (l1LangCode != null && l2LangCode != null) {
        res = await pangeaController.messageData
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
      }

      originalSent = PangeaRepresentation(
        langCode: res?.detections.firstOrNull?.langCode ??
            LanguageKeys.unknownLanguage,
        text: message,
        originalSent: true,
        originalWritten: originalWritten == null,
      );

      tokensSent = res != null
          ? PangeaMessageTokens(
              tokens: res.tokens,
              detections: res.detections,
            )
          : null;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "currentText": message,
          "l1LangCode": l1LangCode,
          "l2LangCode": l2LangCode,
          "choreoRecord": _choreoRecord?.toJson(),
        },
        level: e is TimeoutException ? SentryLevel.warning : SentryLevel.error,
      );
    } finally {
      chatController.send(
        message: message,
        originalSent: originalSent,
        originalWritten: originalWritten,
        tokensSent: tokensSent,
        choreo: _choreoRecord,
        tempEventId: fakeEventId,
      );
      clear();
    }
  }

  void openIT(PangeaMatchState itMatch) {
    if (!itMatch.updatedMatch.isITStart) {
      throw Exception("Attempted to open IT with a non-IT start match");
    }

    _choreoMode = ChoreoMode.it;
    _sourceText = textController.text;
    itController.openIT();

    igc.clear();
    textController.setSystemText("", EditType.it);

    _initChoreoRecord();
    itMatch.setStatus(PangeaMatchStatus.accepted);
    _choreoRecord!.addRecord(
      textController.text,
      match: itMatch.updatedMatch,
    );
    notifyListeners();
  }

  void closeIT() {
    itController.closeIT();
    errorService.resetError();
    notifyListeners();
  }

  Continuance onSelectContinuance(int index) {
    final continuance = itController.onSelectContinuance(index);
    notifyListeners();
    return continuance;
  }

  void onAcceptContinuance(int index) {
    final step = itController.getAcceptedITStep(index);
    textController.setSystemText(
      textController.text + step.continuances[step.chosen].text,
      EditType.it,
    );
    textController.selection = TextSelection.collapsed(
      offset: textController.text.length,
    );

    _initChoreoRecord();
    _choreoRecord!.addRecord(textController.text, step: step);
    chatController.inputFocus.requestFocus();
    notifyListeners();
  }

  void setSourceText(String? text) {
    _sourceText = text;
  }

  void setEditingSourceText(bool value) {
    itController.setEditing(value);
    notifyListeners();
  }

  void submitSourceTextEdits(String text) {
    _sourceText = text;
    itController.onSubmitEdits();
    notifyListeners();
  }

  PangeaMatchState? getMatchByOffset(int offset) =>
      igc.getMatchByOffset(offset);

  void clearMatches(Object error) {
    MatrixState.pAnyState.closeAllOverlays();
    igc.clearMatches();
    errorService.setError(ChoreoError(raw: error));
  }

  Future<void> fetchSpanDetails({
    required PangeaMatchState match,
    bool force = false,
  }) =>
      igc.fetchSpanDetails(
        match: match,
        force: force,
      );

  void onAcceptReplacement({
    required PangeaMatchState match,
  }) {
    final updatedMatch = igc.acceptReplacement(
      match,
      PangeaMatchStatus.accepted,
    );

    textController.setSystemText(
      igc.currentText!,
      EditType.igc,
    );

    if (!updatedMatch.match.isNormalizationError()) {
      _initChoreoRecord();
      _choreoRecord!.addRecord(
        textController.text,
        match: updatedMatch,
      );
    }

    MatrixState.pAnyState.closeOverlay();
    notifyListeners();
  }

  void onUndoReplacement(PangeaMatchState match) {
    igc.undoReplacement(match);
    _choreoRecord?.choreoSteps.removeWhere(
      (step) => step.acceptedOrIgnoredMatch == match.updatedMatch,
    );

    textController.setSystemText(
      igc.currentText!,
      EditType.igc,
    );
    MatrixState.pAnyState.closeOverlay();
    notifyListeners();
  }

  void onIgnoreMatch({required PangeaMatchState match}) {
    final updatedMatch = igc.ignoreReplacement(match);
    if (!updatedMatch.match.isNormalizationError()) {
      _initChoreoRecord();
      _choreoRecord!.addRecord(
        textController.text,
        match: updatedMatch,
      );
    }
    MatrixState.pAnyState.closeOverlay();
    notifyListeners();
  }

  void acceptNormalizationMatches() {
    final normalizationsMatches = igc.openNormalizationMatches;
    if (normalizationsMatches?.isEmpty ?? true) return;

    _initChoreoRecord();
    for (final match in normalizationsMatches!) {
      match.selectChoice(
        match.updatedMatch.match.choices!.indexWhere(
          (c) => c.isBestCorrection,
        ),
      );

      final updatedMatch = igc.acceptReplacement(
        match,
        PangeaMatchStatus.automatic,
      );

      textController.setSystemText(
        igc.currentText!,
        EditType.igc,
      );

      _choreoRecord!.addRecord(
        currentText,
        match: updatedMatch,
      );
    }
    notifyListeners();
  }
}
