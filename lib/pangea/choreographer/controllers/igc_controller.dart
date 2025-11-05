import 'dart:async';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/igc_text_data_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/span_data_request.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IgcController {
  final Function(Object) onError;

  bool _isFetching = false;
  IGCTextData? _igcTextData;

  IgcController(this.onError);

  String? get currentText => _igcTextData?.currentText;
  bool get hasOpenMatches => _igcTextData?.hasOpenMatches == true;
  bool get hasOpenITMatches => _igcTextData?.hasOpenITMatches == true;
  bool get hasOpenIGCMatches => _igcTextData?.hasOpenIGCMatches == true;

  PangeaMatchState? get openMatch => _igcTextData?.openMatch;
  PangeaMatchState? get firstOpenMatch => _igcTextData?.firstOpenMatch;
  List<PangeaMatchState>? get openMatches => _igcTextData?.openMatches;
  List<PangeaMatchState>? get recentNormalizationMatches =>
      _igcTextData?.recentNormalizationMatches;
  List<PangeaMatchState>? get openNormalizationMatches =>
      _igcTextData?.openNormalizationMatches;

  bool get canShowFirstMatch => _igcTextData?.firstOpenMatch != null;
  bool get hasIGCTextData => _igcTextData != null;

  void clear() {
    _isFetching = false;
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
    final updateMatch = _igcTextData!.acceptReplacement(match, status);
    return updateMatch;
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

  Future<void> getIGCTextData(
    String text,
    List<PreviousMessage> prevMessages,
  ) async {
    if (text.isEmpty) return clear();
    if (_isFetching) return;
    _isFetching = true;
    final IGCRequestModel reqBody = IGCRequestModel(
      fullText: text,
      userId: MatrixState.pangeaController.userController.userId!,
      userL1: MatrixState.pangeaController.languageController.activeL1Code()!,
      userL2: MatrixState.pangeaController.languageController.activeL2Code()!,
      enableIGC: true,
      enableIT: true,
      prevMessages: prevMessages,
    );

    final res = await IgcRepo.get(
      MatrixState.pangeaController.userController.accessToken,
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
      onError(res.asError!);
      clear();
      return;
    }

    if (!_isFetching) return;
    final response = res.result!;
    _igcTextData = IGCTextData(
      originalInput: response.originalInput,
      matches: response.matches,
    );
    _isFetching = false;
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
      MatrixState.pangeaController.userController.accessToken,
      request: SpanDetailsRequest(
        userL1: MatrixState.pangeaController.languageController.activeL1Code()!,
        userL2: MatrixState.pangeaController.languageController.activeL2Code()!,
        enableIGC: true,
        enableIT: true,
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
}
