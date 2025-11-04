import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IGCTextState {
  String _currentText;
  final List<PangeaMatchState> _openMatches = [];
  final List<PangeaMatchState> _closedMatches = [];

  IGCTextState({
    required String currentText,
    required List<PangeaMatch> matches,
  }) : _currentText = currentText {
    _openMatches.addAll(
      matches
          .where((match) => match.status == PangeaMatchStatus.open)
          .map((match) {
        return PangeaMatchState(
          match: match.match,
          status: match.status,
          original: match,
        );
      }),
    );

    _closedMatches.addAll(
      matches
          .where((match) => match.status != PangeaMatchStatus.open)
          .map((match) {
        return PangeaMatchState(
          match: match.match,
          status: match.status,
          original: match,
        );
      }),
    );

    _filterIgnoredMatches();
  }

  String get currentText => _currentText;

  List<PangeaMatchState> get openMatches => _openMatches;

  List<PangeaMatchState> get closedMatches => _closedMatches;

  List<PangeaMatchState> get openNormalizationMatches => _openMatches
      .where((match) => match.updatedMatch.match.isNormalizationError())
      .toList();

  bool get hasOpenMatches => _openMatches.isNotEmpty;

  bool get hasOpenITMatches =>
      _openMatches.any((match) => match.updatedMatch.isITStart);

  bool get hasOpenIGCMatches =>
      _openMatches.any((match) => !match.updatedMatch.isITStart);

  PangeaMatchState? get firstOpenMatch => _openMatches.firstOrNull;

  PangeaMatchState? getMatchByOffset(int offset) =>
      _openMatches.firstWhereOrNull(
        (match) => match.updatedMatch.match.isOffsetInMatchSpan(offset),
      );

  PangeaMatchState? get openMatch {
    final RegExp pattern = RegExp(r'span_card_overlay_.+');
    final String? matchingKeys =
        MatrixState.pAnyState.getMatchingOverlayKeys(pattern).firstOrNull;
    if (matchingKeys == null) return null;

    final parts = matchingKeys.split("_");
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

  void clearMatches() {
    _openMatches.clear();
    _closedMatches.clear();
  }

  void _filterIgnoredMatches() {
    for (final match in _openMatches) {
      if (IgcRepo.isIgnored(match.updatedMatch)) {
        ignoreReplacement(match);
      }
    }
  }

  void setSpanData(PangeaMatchState match, SpanData spanData) {
    final openMatch = _openMatches.firstWhereOrNull(
      (m) => m.originalMatch == match.originalMatch,
    );

    match.setMatch(spanData);
    _openMatches.remove(openMatch);
    _openMatches.add(match);
  }

  PangeaMatch acceptReplacement(
    PangeaMatchState match,
    PangeaMatchStatus status,
  ) {
    final openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == match.originalMatch,
      orElse: () => throw Exception(
        'No open match found for acceptReplacement',
      ),
    );

    if (match.updatedMatch.match.selectedChoice == null) {
      throw Exception(
        'acceptReplacement called with null selectedChoice',
      );
    }

    match.setStatus(status);
    _openMatches.remove(openMatch);
    _closedMatches.add(match);

    _runReplacement(
      match.updatedMatch.match.offset,
      match.updatedMatch.match.length,
      match.updatedMatch.match.selectedChoice!.value,
    );

    return match.updatedMatch;
  }

  PangeaMatch ignoreReplacement(PangeaMatchState match) {
    final openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == match.originalMatch,
      orElse: () => throw Exception(
        'No open match found for ignoreReplacement',
      ),
    );

    match.setStatus(PangeaMatchStatus.ignored);
    _openMatches.remove(openMatch);
    _closedMatches.add(match);
    return match.updatedMatch;
  }

  void undoReplacement(PangeaMatchState match) {
    final closedMatch = _closedMatches.firstWhere(
      (m) => m.originalMatch == match.originalMatch,
      orElse: () => throw Exception(
        'No closed match found for undoReplacement',
      ),
    );

    _closedMatches.remove(closedMatch);

    final choice = match.updatedMatch.match.selectedChoice?.value;

    if (choice == null) {
      throw Exception(
        "match.match.selectedChoice is null in undoReplacement",
      );
    }

    final String replacement = match.originalMatch.match.fullText.characters
        .getRange(
          match.originalMatch.match.offset,
          match.originalMatch.match.offset + match.originalMatch.match.length,
        )
        .toString();

    _runReplacement(
      match.originalMatch.match.offset,
      choice.characters.length,
      replacement,
    );
  }

  void _runReplacement(
    int offset,
    int length,
    String replacement,
  ) {
    final start = _currentText.characters.take(offset);
    final end = _currentText.characters.skip(offset + length);
    final fullText = start + replacement.characters + end;
    _currentText = fullText.toString();

    for (int i = 0; i < _openMatches.length; i++) {
      final match = _openMatches[i].updatedMatch.match;
      final updatedMatch = match.copyWith(
        fullText: _currentText,
        offset: match.offset > offset
            ? match.offset + replacement.characters.length - length
            : match.offset,
      );
      _openMatches[i].setMatch(updatedMatch);
    }

    for (int i = 0; i < _closedMatches.length; i++) {
      final match = _closedMatches[i].updatedMatch.match;
      final updatedMatch = match.copyWith(
        fullText: _currentText,
        offset: match.offset > offset
            ? match.offset + replacement.characters.length - length
            : match.offset,
      );
      _closedMatches[i].setMatch(updatedMatch);
    }
  }
}
