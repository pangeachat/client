import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/models/igc_text_data_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_request.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/span_card.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/error_handler.dart';
import '../../common/utils/overlay.dart';

class IgcController {
  Choreographer choreographer;
  IGCTextData? igcTextData;

  IgcController(this.choreographer);

  Future<void> getIGCTextData() async {
    if (choreographer.currentText.isEmpty) return clear();
    debugPrint('getIGCTextData called with ${choreographer.currentText}');

    final IGCRequestModel reqBody = IGCRequestModel(
      fullText: choreographer.currentText,
      userId: choreographer.pangeaController.userController.userId!,
      userL1: choreographer.l1LangCode!,
      userL2: choreographer.l2LangCode!,
      enableIGC:
          choreographer.igcEnabled && choreographer.choreoMode != ChoreoMode.it,
      enableIT:
          choreographer.itEnabled && choreographer.choreoMode != ChoreoMode.it,
      prevMessages: _prevMessages(),
    );

    final res = await IgcRepo.get(
      choreographer.accessToken,
      reqBody,
    ).timeout(
      (const Duration(seconds: 10)),
      onTimeout: () {
        return Result.error(
          TimeoutException('IGC request timed out'),
        );
      },
    );

    if (res.isError) {
      choreographer.errorService.setError(ChoreoError(raw: res.error));
      clear();
      return;
    }

    // this will happen when the user changes the input while igc is fetching results
    if (res.result!.originalInput.trim() != choreographer.currentText.trim()) {
      return;
    }

    final response = res.result!;
    igcTextData = IGCTextData(
      originalInput: response.originalInput,
      matches: response.matches,
    );
    choreographer.acceptNormalizationMatches();

    for (final match in igcTextData!.openMatches) {
      setSpanDetails(match: match);
    }
  }

  void onIgnoreMatch(PangeaMatch match) {
    IgcRepo.ignore(match);
  }

  bool get canShowFirstMatch {
    return igcTextData?.firstOpenMatch != null;
  }

  void showFirstMatch(BuildContext context) {
    if (!canShowFirstMatch) {
      debugger(when: kDebugMode);
      ErrorHandler.logError(
        m: "should not be calling showFirstMatch with this igcTextData.",
        s: StackTrace.current,
        data: {
          "igcTextData": igcTextData?.toJson(),
        },
      );
      return;
    }

    final match = igcTextData!.firstOpenMatch!;
    if (match.updatedMatch.isITStart && igcTextData != null) {
      choreographer.onITStart(match);
      return;
    }

    choreographer.chatController.inputFocus.unfocus();
    MatrixState.pAnyState.closeAllOverlays();
    OverlayUtil.showPositionedCard(
      overlayKey:
          "span_card_overlay_${match.updatedMatch.match.offset}_${match.updatedMatch.match.length}",
      context: context,
      cardToShow: SpanCard(
        match: match,
        choreographer: choreographer,
      ),
      maxHeight: 325,
      maxWidth: 325,
      transformTargetId: choreographer.inputTransformTargetKey,
      onDismiss: () => choreographer.setState(),
      ignorePointer: true,
      isScrollable: false,
    );
  }

  /// Get the content of previous text and audio messages in chat.
  /// Passed to IGC request to add context.
  List<PreviousMessage> _prevMessages({int numMessages = 5}) {
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
            ).getSpeechToTextLocal()?.transcript.text.trim(); // trim whitespace
      if (content == null) continue;
      messages.add(
        PreviousMessage(
          content: content,
          sender: event.senderId,
          timestamp: event.originServerTs,
        ),
      );
      if (messages.length >= numMessages) {
        return messages;
      }
    }
    return messages;
  }

  bool get hasRelevantIGCTextData {
    if (igcTextData == null) return false;

    if (igcTextData!.currentText != choreographer.currentText) {
      debugPrint(
        "returning isIGCTextDataRelevant false because text has changed",
      );
      return false;
    }
    return true;
  }

  clear() {
    igcTextData = null;
    MatrixState.pAnyState.closeAllOverlays();
  }

  Future<void> setSpanDetails({
    required PangeaMatchState match,
    bool force = false,
  }) async {
    final span = match.updatedMatch.match;
    if (span.isNormalizationError() && !force) {
      return;
    }

    final response = await SpanDataRepo.get(
      choreographer.accessToken,
      request: SpanDetailsRequest(
        userL1: choreographer.l1LangCode!,
        userL2: choreographer.l2LangCode!,
        enableIGC: choreographer.igcEnabled,
        enableIT: choreographer.itEnabled,
        span: span,
      ),
    );

    if (response.isError) {
      choreographer.errorService.setError(ChoreoError(raw: response.error));
      clear();
      return;
    }

    igcTextData?.setSpanData(match, response.result!.span);
    choreographer.setState();
  }
}
