import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choregrapher_user_settings_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';
import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/igc_text_data_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_request.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/error_handler.dart';

class IgcController {
  final Choreographer _choreographer;
  IGCTextData? _igcTextData;

  IgcController(this._choreographer);

  String? get currentText => _igcTextData?.currentText;
  bool get hasOpenMatches => _igcTextData?.hasOpenMatches == true;
  bool get hasOpenITMatches => _igcTextData?.hasOpenITMatches == true;
  bool get hasOpenIGCMatches => _igcTextData?.hasOpenIGCMatches == true;

  PangeaMatchState? get openMatch => _igcTextData?.openMatch;
  PangeaMatchState? get firstOpenMatch => _igcTextData?.firstOpenMatch;
  List<PangeaMatchState>? get openMatches => _igcTextData?.openMatches;
  List<PangeaMatchState>? get closedMatches => _igcTextData?.closedMatches;
  List<PangeaMatchState>? get openNormalizationMatches =>
      _igcTextData?.openNormalizationMatches;

  bool get canShowFirstMatch => _igcTextData?.firstOpenMatch != null;
  bool get hasIGCTextData {
    if (_igcTextData == null) return false;
    return _igcTextData!.currentText == _choreographer.currentText;
  }

  void clear() {
    _igcTextData = null;
    MatrixState.pAnyState.closeAllOverlays();
  }

  void clearMatches() => _igcTextData?.clearMatches();

  PangeaMatchState? getMatchByOffset(int offset) =>
      _igcTextData?.getMatchByOffset(offset);

  PangeaMatch acceptReplacement(
    PangeaMatchState match,
    PangeaMatchStatus status,
  ) {
    if (_igcTextData == null) {
      throw "acceptReplacement called with null igcTextData";
    }
    return _igcTextData!.acceptReplacement(match, status);
  }

  PangeaMatch ignoreReplacement(PangeaMatchState match) {
    IgcRepo.ignore(match.updatedMatch);
    if (_igcTextData == null) {
      throw "should not be in onIgnoreMatch with null igcTextData";
    }
    return _igcTextData!.ignoreReplacement(match);
  }

  void undoReplacement(PangeaMatchState match) {
    if (_igcTextData == null) {
      throw "undoReplacement called with null igcTextData";
    }
    _igcTextData!.undoReplacement(match);
  }

  Future<void> getIGCTextData() async {
    if (_choreographer.currentText.isEmpty) return clear();
    debugPrint('getIGCTextData called with ${_choreographer.currentText}');

    final IGCRequestModel reqBody = IGCRequestModel(
      fullText: _choreographer.currentText,
      userId: _choreographer.pangeaController.userController.userId!,
      userL1: _choreographer.l1LangCode!,
      userL2: _choreographer.l2LangCode!,
      enableIGC: _choreographer.igcEnabled &&
          _choreographer.choreoMode != ChoreoMode.it,
      enableIT: _choreographer.itEnabled &&
          _choreographer.choreoMode != ChoreoMode.it,
      prevMessages: _prevMessages(),
    );

    final res = await IgcRepo.get(
      _choreographer.pangeaController.userController.accessToken,
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
      _choreographer.errorService.setErrorAndLock(
        ChoreoError(raw: res.asError),
      );
      clear();
      return;
    }

    // this will happen when the user changes the input while igc is fetching results
    if (res.result!.originalInput.trim() != _choreographer.currentText.trim()) {
      return;
    }

    final response = res.result!;
    _igcTextData = IGCTextData(
      originalInput: response.originalInput,
      matches: response.matches,
    );

    try {
      _choreographer.acceptNormalizationMatches();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "igcResponse": response.toJson(),
        },
      );
    }

    if (_igcTextData != null) {
      for (final match in _igcTextData!.openMatches) {
        fetchSpanDetails(match: match).catchError((e) {});
      }
    }
  }

  Future<void> fetchSpanDetails({
    required PangeaMatchState match,
    bool force = false,
  }) async {
    final span = match.updatedMatch.match;
    if (span.isNormalizationError() && !force) {
      return;
    }

    final response = await SpanDataRepo.get(
      _choreographer.pangeaController.userController.accessToken,
      request: SpanDetailsRequest(
        userL1: _choreographer.l1LangCode!,
        userL2: _choreographer.l2LangCode!,
        enableIGC: _choreographer.igcEnabled,
        enableIT: _choreographer.itEnabled,
        span: span,
      ),
    ).timeout(
      (const Duration(seconds: 10)),
      onTimeout: () {
        return Result.error(
          TimeoutException('Span details request timed out'),
        );
      },
    );

    if (response.isError) {
      throw response.error!;
    }

    _igcTextData?.setSpanData(match, response.result!.span);
  }

  List<PreviousMessage> _prevMessages({int numMessages = 5}) {
    final List<Event> events = _choreographer.chatController.visibleEvents
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
              timeline: _choreographer.chatController.timeline!,
              ownMessage: event.senderId ==
                  _choreographer.pangeaController.matrixState.client.userID,
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
}
