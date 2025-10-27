import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/controllers/span_data_controller.dart';
import 'package:fluffychat/pangea/choreographer/models/igc_text_data_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/span_card.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/error_handler.dart';
import '../../common/utils/overlay.dart';

class IgcController {
  Choreographer choreographer;
  IGCTextData? igcTextData;
  late SpanDataController spanDataController;

  IgcController(this.choreographer) {
    spanDataController = SpanDataController(choreographer);
  }

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
    // get ignored matches from the original igcTextData
    // if the new matches are the same as the original match
    // could possibly change the status of the new match
    // thing is the same if the text we are trying to change is the smae
    // as the new text we are trying to change (suggestion is the same)

    // Check for duplicate or minor text changes that shouldn't trigger suggestions
    // checks for duplicate input

    igcTextData = res.result!;
    final List<PangeaMatch> filteredMatches = List.from(igcTextData!.matches);
    for (final PangeaMatch match in igcTextData!.matches) {
      if (IgcRepo.isIgnored(match)) {
        filteredMatches.remove(match);
      }
    }

    igcTextData!.matches = filteredMatches;
    choreographer.acceptNormalizationMatches();

    // TODO - for each new match,
    // check if existing igcTextData has one and only one match with the same error text and correction
    // if so, keep the original match and discard the new one
    // if not, add the new match to the existing igcTextData

    // After fetching igc data, pre-call span details for each match optimistically.
    // This will make the loading of span details faster for the user
    if (igcTextData?.matches.isNotEmpty ?? false) {
      for (int i = 0; i < igcTextData!.matches.length; i++) {
        if (!igcTextData!.matches[i].isITStart) {
          spanDataController.getSpanDetails(i);
        }
      }
    }
  }

  void onIgnoreMatch(PangeaMatch match) {
    IgcRepo.ignore(match);
  }

  void showFirstMatch(BuildContext context) {
    if (igcTextData == null || igcTextData!.matches.isEmpty) {
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

    const int firstMatchIndex = 0;
    final PangeaMatch match = igcTextData!.matches[firstMatchIndex];

    if (match.isITStart &&
        // choreographer.itAutoPlayEnabled &&
        igcTextData != null) {
      choreographer.onITStart(igcTextData!.matches[firstMatchIndex]);
      return;
    }

    choreographer.chatController.inputFocus.unfocus();
    MatrixState.pAnyState.closeAllOverlays(
      filter: RegExp(r'span_card_overlay_\d+'),
    );
    OverlayUtil.showPositionedCard(
      overlayKey: "span_card_overlay_$firstMatchIndex",
      context: context,
      cardToShow: SpanCard(
        matchIndex: firstMatchIndex,
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
    MatrixState.pAnyState.closeAllOverlays(
      filter: RegExp(r'span_card_overlay_\d+'),
    );
  }
}
