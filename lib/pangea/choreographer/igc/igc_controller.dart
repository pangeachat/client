import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/igc/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/igc/igc_request_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_repo.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_request.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IgcController {
  final Function(Object) onError;
  final VoidCallback onFetch;
  IgcController(this.onError, this.onFetch);

  bool _isFetching = false;
  String? _currentText;

  final List<PangeaMatchState> _openMatches = [];
  final List<PangeaMatchState> _closedMatches = [];

  StreamController<PangeaMatchState> matchUpdateStream =
      StreamController.broadcast();

  String? get currentText => _currentText;
  List<PangeaMatchState> get openMatches => _openMatches;

  List<PangeaMatchState> get recentAutomaticCorrections =>
      _closedMatches.reversed
          .takeWhile(
            (m) => m.updatedMatch.status == PangeaMatchStatusEnum.automatic,
          )
          .toList();

  List<PangeaMatchState> get openAutomaticMatches => _openMatches
      .where((match) => match.updatedMatch.match.isNormalizationError())
      .toList();

  PangeaMatchState? get currentlyOpenMatch {
    final RegExp pattern = RegExp(r'span_card_overlay_.+');
    final String? matchingKey =
        MatrixState.pAnyState.getMatchingOverlayKeys(pattern).firstOrNull;
    if (matchingKey == null) return null;

    final parts = matchingKey.split('_');
    if (parts.length != 5) return null;
    final offset = int.tryParse(parts[3]);
    final length = int.tryParse(parts[4]);
    if (offset == null || length == null) return null;

    return _openMatches.firstWhereOrNull(
      (match) =>
          match.updatedMatch.match.offset == offset &&
          match.updatedMatch.match.length == length,
    );
  }

  IGCRequestModel _igcRequest(
    String text,
    List<PreviousMessage> prevMessages,
  ) =>
      IGCRequestModel(
        fullText: text,
        userId: MatrixState.pangeaController.userController.client.userID!,
        userL1: MatrixState.pangeaController.userController.userL1Code!,
        userL2: MatrixState.pangeaController.userController.userL2Code!,
        enableIGC: true,
        enableIT: true,
        prevMessages: prevMessages,
      );

  SpanDetailsRequest _spanDetailsRequest(SpanData span) => SpanDetailsRequest(
        userL1: MatrixState.pangeaController.userController.userL1Code!,
        userL2: MatrixState.pangeaController.userController.userL2Code!,
        enableIGC: true,
        enableIT: true,
        span: span,
      );

  void dispose() {
    matchUpdateStream.close();
  }

  void clear() {
    _isFetching = false;
    _currentText = null;
    _openMatches.clear();
    _closedMatches.clear();
    MatrixState.pAnyState.closeAllOverlays();
  }

  void clearMatches() {
    _openMatches.clear();
    _closedMatches.clear();
  }

  void _filterPreviouslyIgnoredMatches() {
    for (final match in _openMatches) {
      if (IgcRepo.isIgnored(match.updatedMatch)) {
        updateOpenMatch(match, PangeaMatchStatusEnum.ignored);
      }
    }
  }

  PangeaMatchState? getMatchByOffset(int offset) =>
      _openMatches.firstWhereOrNull(
        (match) => match.updatedMatch.match.isOffsetInMatchSpan(offset),
      );

  void setSpanData(PangeaMatchState matchState, SpanData spanData) {
    final openMatch = _openMatches.firstWhereOrNull(
      (m) => m.originalMatch == matchState.originalMatch,
    );

    matchState.setMatch(spanData);
    _openMatches.remove(openMatch);
    _openMatches.add(matchState);
  }

  void updateMatch(
    PangeaMatchState match,
    PangeaMatchStatusEnum status,
  ) {
    PangeaMatchState updated;
    switch (status) {
      case PangeaMatchStatusEnum.accepted:
      case PangeaMatchStatusEnum.automatic:
        updated = updateOpenMatch(match, status);
      case PangeaMatchStatusEnum.ignored:
        IgcRepo.ignore(match.updatedMatch);
        updated = updateOpenMatch(match, status);
      case PangeaMatchStatusEnum.undo:
        updated = updateClosedMatch(match, status);
      default:
        throw "updateMatch called with unsupported status: $status";
    }
    matchUpdateStream.add(updated);
  }

  PangeaMatchState updateOpenMatch(
    PangeaMatchState matchState,
    PangeaMatchStatusEnum status,
  ) {
    final PangeaMatchState openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == matchState.originalMatch,
      orElse: () => throw StateError(
        'No open match found while updating match.',
      ),
    );

    matchState.setStatus(status);
    _openMatches.remove(openMatch);
    _closedMatches.add(matchState);

    switch (status) {
      case PangeaMatchStatusEnum.accepted:
      case PangeaMatchStatusEnum.automatic:
        final choice = matchState.updatedMatch.match.selectedChoice;
        if (choice == null) {
          throw ArgumentError(
            'acceptMatch called with a null selectedChoice.',
          );
        }
        _applyReplacement(
          matchState.updatedMatch.match.offset,
          matchState.updatedMatch.match.length,
          choice.value,
        );
      case PangeaMatchStatusEnum.ignored:
        break;
      default:
        throw ArgumentError(
          'updateOpenMatch called with unsupported status: $status',
        );
    }

    return matchState;
  }

  PangeaMatchState updateClosedMatch(
    PangeaMatchState matchState,
    PangeaMatchStatusEnum status,
  ) {
    final closedMatch = _closedMatches.firstWhere(
      (m) => m.originalMatch == matchState.originalMatch,
      orElse: () => throw StateError(
        'No closed match found while updating match.',
      ),
    );

    matchState.setStatus(status);
    _closedMatches.remove(closedMatch);

    final selectedValue = matchState.updatedMatch.match.selectedChoice?.value;
    if (selectedValue == null) {
      throw StateError(
        'Cannot update match without a selectedChoice value.',
      );
    }

    final replacement = matchState.originalMatch.match.fullText.characters
        .getRange(
          matchState.originalMatch.match.offset,
          matchState.originalMatch.match.offset +
              matchState.originalMatch.match.length,
        )
        .toString();

    _applyReplacement(
      matchState.originalMatch.match.offset,
      selectedValue.characters.length,
      replacement,
    );

    return matchState;
  }

  Future<void> acceptNormalizationMatches() async {
    final matches = openAutomaticMatches;
    if (matches.isEmpty) return;

    final expectedSpans = matches.map((m) => m.originalMatch).toSet();
    final completer = Completer<void>();

    int completedCount = 0;

    late final StreamSubscription<PangeaMatchState> sub;
    sub = matchUpdateStream.stream.listen((match) {
      if (expectedSpans.remove(match.originalMatch)) {
        completedCount++;
        if (completedCount >= matches.length) {
          completer.complete();
          sub.cancel();
        }
      }
    });

    try {
      for (final match in matches) {
        match.selectBestChoice();
        updateMatch(match, PangeaMatchStatusEnum.automatic);
      }

      // If no updates arrive (edge case), auto-timeout after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (!completer.isCompleted) {
          completer.complete();
          sub.cancel();
        }
      });
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"currentText": currentText},
      );
      if (!completer.isCompleted) completer.complete();
    }

    return completer.future;
  }

  /// Applies a text replacement to [_currentText] and adjusts match offsets.
  ///
  /// Called internally when a correction is accepted or undone.
  void _applyReplacement(
    int offset,
    int length,
    String replacement,
  ) {
    if (_currentText == null) {
      throw StateError('_applyReplacement called with null _currentText');
    }
    final start = _currentText!.characters.take(offset);
    final end = _currentText!.characters.skip(offset + length);
    final updatedText = start + replacement.characters + end;
    _currentText = updatedText.toString();

    for (final list in [_openMatches, _closedMatches]) {
      for (final matchState in list) {
        final match = matchState.updatedMatch.match;
        final updatedMatch = match.copyWith(
          fullText: _currentText,
          offset: match.offset > offset
              ? match.offset + replacement.characters.length - length
              : match.offset,
        );
        matchState.setMatch(updatedMatch);
      }
    }
  }

  Future<void> getIGCTextData(
    String text,
    List<PreviousMessage> prevMessages,
  ) async {
    if (text.isEmpty) return clear();
    if (_isFetching) return;
    _isFetching = true;

    final res = await IgcRepo.get(
      MatrixState.pangeaController.userController.accessToken,
      _igcRequest(text, prevMessages),
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
    } else {
      onFetch();
    }

    if (!_isFetching) return;
    _currentText = res.result!.originalInput;
    for (final match in res.result!.matches) {
      final matchState = PangeaMatchState(
        match: match.match,
        status: PangeaMatchStatusEnum.open,
        original: match,
      );
      if (match.status == PangeaMatchStatusEnum.open) {
        _openMatches.add(matchState);
      } else {
        _closedMatches.add(matchState);
      }
    }
    _filterPreviouslyIgnoredMatches();
    _isFetching = false;
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
      request: _spanDetailsRequest(span),
    ).timeout(
      (const Duration(seconds: 10)),
      onTimeout: () {
        return Result.error(
          TimeoutException('Span details request timed out'),
        );
      },
    );

    if (response.isError) throw response.error!;
    setSpanData(match, response.result!);
  }

  Future<void> fetchAllSpanDetails() async {
    final fetches = <Future>[];
    for (final match in _openMatches) {
      fetches.add(fetchSpanDetails(match: match));
    }
    await Future.wait(fetches);
  }
}
