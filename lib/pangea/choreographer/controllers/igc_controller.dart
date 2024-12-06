import 'dart:async';
import 'dart:developer';

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/controllers/span_data_controller.dart';
import 'package:fluffychat/pangea/matrix_event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/models/igc_text_data_model.dart';
import 'package:fluffychat/pangea/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/repo/igc_repo.dart';
import 'package:fluffychat/pangea/widgets/igc/span_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../models/span_card_model.dart';
import '../../utils/error_handler.dart';
import '../../utils/overlay.dart';

class IgcController {
  Choreographer choreographer;
  IGCTextData? igcTextData;
  Object? igcError;
  Completer<IGCTextData> igcCompleter = Completer();
  late SpanDataController spanDataController;

  // cache for IGC data and prev message
  final Map<String, IGCTextData> _igcTextDataCache = {};
  final Map<int, List<PreviousMessage>> _prevMessagesCache = {};
  final Map<int, dynamic> _spaDetailsCache = {};

  // map to track individuall expiration timers
  final Map<String, Timer> _cacheTimers = {};

  // Timer for cache clearing
  //Timer? _cacheClearTimer;

  IgcController(this.choreographer) {
    spanDataController = SpanDataController(choreographer);
    //_startCacheClearTimer();
  }

  // Start the cache clear timer
  // void _startCacheClearTimer() {
  //   _cacheClearTimer
  //       ?.cancel(); // Cancel any existing timer to avoid multiple timers running concurrently
  //   _cacheClearTimer = Timer(const Duration(minutes: 1), () {
  //     clearCache(); // Call the cache clearing method after 1 minute
  //   });
  // }

  // Clear cache method
  void clearCache() {
    _igcTextDataCache.clear();
    _prevMessagesCache.clear();
    _spaDetailsCache.clear();
    debugPrint("Cache cleared after 1 minute.");
  }

  Future<void> getIGCTextData({
    required bool onlyTokensAndLanguageDetection,
  }) async {
    try {
      if (choreographer.currentText.isEmpty) return clear();

      final trimmedText = choreographer.currentText.trim();
      debugPrint('getIGCTextData called with ${choreographer.currentText}');
      debugPrint(
        'getIGCTextData called with tokensOnly = $onlyTokensAndLanguageDetection',
      );

      // Check if cached data exists
      if (_igcTextDataCache.containsKey(trimmedText)) {
        igcTextData = _igcTextDataCache[trimmedText];
        return;
      }

      final IGCRequestBody reqBody = IGCRequestBody(
        fullText: choreographer.currentText,
        userId: choreographer.pangeaController.userController.userId!,
        userL1: choreographer.l1LangCode!,
        userL2: choreographer.l2LangCode!,
        enableIGC: choreographer.igcEnabled && !onlyTokensAndLanguageDetection,
        enableIT: choreographer.itEnabled && !onlyTokensAndLanguageDetection,
        prevMessages: prevMessages(),
      );

      final IGCTextData igcTextDataResponse = await IgcRepo.getIGC(
        choreographer.accessToken,
        igcRequest: reqBody,
      );

      // this will happen when the user changes the input while igc is fetching results
      if (igcTextDataResponse.originalInput != choreographer.currentText) {
        return;
      }
      // get ignored matches from the original igcTextData
      // if the new matches are the same as the original match
      // could possibly change the status of the new match
      // thing is the same if the text we are trying to change is the smae
      // as the new text we are trying to change (suggestion is the same)

      // Check for duplicate or minor text changes that shouldn't trigger suggestions
      // checks for duplicate input

      igcTextData = igcTextDataResponse;

      // Cache the fetched data
      _igcTextDataCache[trimmedText] = igcTextDataResponse;

      // Set a 1-minute timer for the specific cache entry
      _setCacheExpirationTimer(trimmedText);

      // TODO - for each new match,
      // check if existing igcTextData has one and only one match with the same error text and correction
      // if so, keep the original match and discard the new one
      // if not, add the new match to the existing igcTextData

      // After fetching igc data, pre-call span details for each match optimistically.
      // This will make the loading of span details faster for the user
      if (igcTextData?.matches.isNotEmpty ?? false) {
        for (int i = 0; i < igcTextData!.matches.length; i++) {
          spanDataController.getSpanDetails(i);
        }
      }

      debugPrint("igc text ${igcTextData.toString()}");

      // Reset the cache clearing timer on successful request
      //_startCacheClearTimer();
    } catch (err, stack) {
      debugger(when: kDebugMode);
      choreographer.errorService.setError(
        ChoreoError(type: ChoreoErrorType.unknown, raw: err),
      );
      ErrorHandler.logError(e: err, s: stack);
      clear();
    }
  }

  /// Set a timer to clear the cache for the specific word after 1 minute
  void _setCacheExpirationTimer(String word) {
    // If a timer already exists for this word, cancel it before setting a new one
    _cacheTimers[word]?.cancel();

    // Set a new timer to clear the cache after 1 minute
    _cacheTimers[word] = Timer(const Duration(minutes: 1), () {
      _clearCacheForWord(word);
    });
  }

  /// Clear the cache for a specific word
  void _clearCacheForWord(String word) {
    _igcTextDataCache.remove(word);
    _cacheTimers.remove(word); // Remove the timer for this word as well
    debugPrint('Cache cleared for word: $word');
  }

  void showFirstMatch(BuildContext context) {
    if (igcTextData == null || igcTextData!.matches.isEmpty) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "should not be calling showFirstMatch with this igcTextData ${igcTextData?.toJson().toString()}",
        s: StackTrace.current,
      );
      return;
    }

    const int firstMatchIndex = 0;
    final PangeaMatch match = igcTextData!.matches[firstMatchIndex];

    if (match.isITStart &&
        // choreographer.itAutoPlayEnabled &&
        igcTextData != null) {
      choreographer.onITStart(igcTextData!.matches[firstMatchIndex]);
      return;
    }

    choreographer.chatController.inputFocus.unfocus();
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: SpanCard(
        scm: SpanCardModel(
          matchIndex: firstMatchIndex,
          onReplacementSelect: choreographer.onReplacementSelect,
          onSentenceRewrite: (value) async {},
          onIgnore: () => choreographer.onIgnoreMatch(
            cursorOffset: match.match.offset,
          ),
          onITStart: () {
            if (choreographer.itEnabled && igcTextData != null) {
              choreographer.onITStart(igcTextData!.matches[firstMatchIndex]);
            }
          },
          choreographer: choreographer,
        ),
        roomId: choreographer.roomId,
      ),
      maxHeight: match.isITStart ? 260 : 350,
      maxWidth: 350,
      transformTargetId: choreographer.inputTransformTargetKey,
    );
  }

  /// Get the content of previous text and audio messages in chat.
  /// Passed to IGC request to add context.
  List<PreviousMessage> prevMessages({int numMessages = 5}) {
    // Check cache
    if (_prevMessagesCache.containsKey(numMessages)) {
      return _prevMessagesCache[numMessages]!;
    }

    final List<Event> events = choreographer.chatController.visibleEvents
        .where(
          (e) =>
              e.type == EventTypes.Message &&
              (e.messageType == MessageTypes.Text ||
                  e.messageType == MessageTypes.Audio),
        )
        .toList();

    final List<PreviousMessage> messages = [];
    for (final Event event in events) {
      final String? content = event.messageType == MessageTypes.Text
          ? event.content.toString()
          : PangeaMessageEvent(
              event: event,
              timeline: choreographer.chatController.timeline!,
              ownMessage: event.senderId ==
                  choreographer.pangeaController.matrixState.client.userID,
            )
              .getSpeechToTextLocal(
                choreographer.l1LangCode,
                choreographer.l2LangCode,
              )
              ?.transcript
              .text
              .trim(); // trim whitespace
      if (content == null) continue;
      messages.add(
        PreviousMessage(
          content: content,
          sender: event.senderId,
          timestamp: event.originServerTs,
        ),
      );
      if (messages.length >= numMessages) {
        // Cache the results
        _prevMessagesCache[numMessages] = messages;
        return messages;
      }
    }
    return messages;
  }

  bool get hasRelevantIGCTextData {
    if (igcTextData == null) return false;

    if (igcTextData!.originalInput != choreographer.currentText) {
      debugPrint(
        "returning isIGCTextDataRelevant false because text has changed",
      );
      return false;
    }
    return true;
  }

  clear() {
    igcTextData = null;
    spanDataController.clearCache();
    // Not sure why this is here
    // MatrixState.pAnyState.closeOverlay();
  }
}
