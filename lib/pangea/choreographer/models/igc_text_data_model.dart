import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';
import 'package:fluffychat/pangea/choreographer/repo/igc_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A model representing the mutable text and match state used by
/// Interactive Grammar Correction (IGC).
///
/// This class tracks the original input text, the current working text,
/// and the states of open and closed grammar matches as the user accepts,
/// ignores, or reverses suggested corrections.
class IGCTextData {
  /// The user's original text before any corrections or replacements.
  final String _originalInput;

  /// The full list of detected matches from the initial grammar analysis.
  final List<PangeaMatch> _matches;

  /// Matches currently pending user action (neither accepted nor ignored).
  final List<PangeaMatchState> _openMatches = [];

  /// Matches that have been resolved by either accepting or ignoring them.
  final List<PangeaMatchState> _closedMatches = [];

  /// The current text content after applying all accepted corrections.
  String _currentText;

  IGCTextData({
    required String originalInput,
    required List<PangeaMatch> matches,
  })  : _currentText = originalInput,
        _originalInput = originalInput,
        _matches = matches {
    for (final match in matches) {
      final matchState = PangeaMatchState(
        match: match.match,
        status: PangeaMatchStatus.open,
        original: match,
      );
      if (match.status == PangeaMatchStatus.open) {
        _openMatches.add(matchState);
      } else {
        _closedMatches.add(matchState);
      }
    }
    _filterPreviouslyIgnoredMatches();
  }

  Map<String, dynamic> toJson() => {
        "original_input": _originalInput,
        "matches": _matches.map((e) => e.toJson()).toList(),
      };

  String get currentText => _currentText;

  List<PangeaMatchState> get openMatches => _openMatches;

  bool get hasOpenMatches => _openMatches.isNotEmpty;

  PangeaMatchState? get firstOpenMatch => _openMatches.firstOrNull;

  /// Normalization matches that have been closed in the last choreo step(s).
  /// Used to display automatic corrections made by the IGC system.
  List<PangeaMatchState> get recentNormalizationMatches =>
      _closedMatches.reversed
          .takeWhile(
            (m) => m.updatedMatch.status == PangeaMatchStatus.automatic,
          )
          .toList();

  /// Convenience getter for open normalization error matches.
  /// Used for auto-correction of normalization errors.
  List<PangeaMatchState> get openNormalizationMatches => _openMatches
      .where((match) => match.updatedMatch.match.isNormalizationError())
      .toList();

  /// Returns the open match that contains the given text offset, if any.
  PangeaMatchState? getOpenMatchByOffset(int offset) =>
      _openMatches.firstWhereOrNull(
        (match) => match.updatedMatch.match.isOffsetInMatchSpan(offset),
      );

  /// Returns the match whose span card overlay is currently open, if any.
  PangeaMatchState? get currentlyOpenMatch {
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

  /// Clears all matches from the IGC text data.
  /// Call on error that make continuing IGC processing invalid.
  void clearIGCMatches() {
    _openMatches.clear();
    _closedMatches.clear();
  }

  /// Filters out previously ignored matches from the open matches list.
  void _filterPreviouslyIgnoredMatches() {
    for (final match in _openMatches) {
      if (IgcRepo.isIgnored(match.updatedMatch)) {
        makeIgnoredMatchUpdates(match);
      }
    }
  }

  /// Replaces the span data for a given match.
  void setSpanData(PangeaMatchState match, SpanData spanData) {
    final openMatch = _openMatches.firstWhereOrNull(
      (m) => m.originalMatch == match.originalMatch,
    );

    match.setMatch(spanData);
    _openMatches.remove(openMatch);
    _openMatches.add(match);
  }

  /// Accepts the specified [match] and updates both the open/closed match lists
  /// and the [_currentText] to include the chosen replacement text.
  PangeaMatch makeAcceptedMatchUpdates(
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

  /// Ignores a given match and updates the IGC text data state accordingly.
  PangeaMatch makeIgnoredMatchUpdates(PangeaMatchState match) {
    final openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == match.originalMatch,
      orElse: () => throw Exception(
        'No open match found for makeIgnoredMatchUpdates',
      ),
    );

    match.setStatus(PangeaMatchStatus.ignored);
    _openMatches.remove(openMatch);
    _closedMatches.add(match);
    return match.updatedMatch;
  }

  /// Removes a given match from the closed match history and undoes the
  /// changes to igc text data state caused by accepting the match.
  void removeMatchUpdates(PangeaMatchState match) {
    final closedMatch = _closedMatches.firstWhere(
      (m) => m.originalMatch == match.originalMatch,
      orElse: () => throw Exception(
        'No closed match found for removeMatchUpdates',
      ),
    );

    _closedMatches.remove(closedMatch);
    final choice = match.updatedMatch.match.selectedChoice?.value;

    if (choice == null) {
      throw Exception(
        "match.match.selectedChoice is null in removeMatchUpdates",
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

  /// Runs a text replacement and updates match offsets / current text accordingly.
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
