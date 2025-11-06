import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/choreographer/igc/igc_repo.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A model representing mutable text and match state used by
/// Interactive Grammar Correction (IGC).
///
/// This class tracks the user's original text, the current working text,
/// and the states of grammar matches detected during processing.
/// It provides methods to accept, ignore, or undo corrections, while
/// maintaining consistent text and offset updates across all matches.
class IGCTextData {
  /// The user's original text before any corrections or replacements.
  final String _originalText;

  /// The complete list of detected matches from the initial grammar analysis.
  final List<PangeaMatch> _initialMatches;

  /// Matches currently awaiting user action (neither accepted nor ignored).
  final List<PangeaMatchState> _openMatches = [];

  /// Matches that have been resolved, either accepted or ignored.
  final List<PangeaMatchState> _closedMatches = [];

  /// The current working text after applying accepted corrections.
  String _currentText;

  /// Creates a new instance of [IGCTextData] from the given [originalInput]
  /// and list of grammar [matches].
  ///
  /// Automatically initializes open and closed matches based on their status
  /// and filters out previously ignored matches.
  IGCTextData({
    required String originalInput,
    required List<PangeaMatch> matches,
  })  : _originalText = originalInput,
        _currentText = originalInput,
        _initialMatches = matches {
    for (final match in matches) {
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
  }

  /// Returns a JSON representation of this IGC text data.
  Map<String, dynamic> toJson() => {
        'original_input': _originalText,
        'matches': _initialMatches.map((e) => e.toJson()).toList(),
      };

  /// The current working text after any accepted replacements.
  String get currentText => _currentText;

  /// The list of open matches that are still awaiting user action.
  List<PangeaMatchState> get openMatches => List.unmodifiable(_openMatches);

  /// Whether there are any open matches remaining.
  bool get hasOpenMatches => _openMatches.isNotEmpty;

  /// The first open match, if one exists.
  PangeaMatchState? get firstOpenMatch => _openMatches.firstOrNull;

  /// Closed matches that were automatically corrected in recent steps.
  ///
  /// Used to display automatic normalization corrections applied
  /// by the IGC system.
  List<PangeaMatchState> get recentAutomaticCorrections =>
      _closedMatches.reversed
          .takeWhile(
            (m) => m.updatedMatch.status == PangeaMatchStatusEnum.automatic,
          )
          .toList();

  /// Open matches representing normalization errors that can be auto-corrected.
  List<PangeaMatchState> get openNormalizationMatches => _openMatches
      .where((match) => match.updatedMatch.match.isNormalizationError())
      .toList();

  /// Returns the open match that contains the given text [offset], if any.
  PangeaMatchState? getOpenMatchByOffset(int offset) =>
      _openMatches.firstWhereOrNull(
        (match) => match.updatedMatch.match.isOffsetInMatchSpan(offset),
      );

  /// Returns the match whose span card overlay is currently open, if any.
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

  /// Clears all match data from this IGC instance.
  ///
  /// Call this when an error occurs that invalidates current match data.
  void clearMatches() {
    _openMatches.clear();
    _closedMatches.clear();
  }

  /// Filters out any previously ignored matches from the open list.
  void _filterPreviouslyIgnoredMatches() {
    for (final match in _openMatches) {
      if (IgcRepo.isIgnored(match.updatedMatch)) {
        ignoreMatch(match);
      }
    }
  }

  /// Updates the [matchState] with new [spanData].
  ///
  /// Replaces the existing span information for the given match
  /// while maintaining its position in the open list.
  void setSpanData(PangeaMatchState matchState, SpanData spanData) {
    final openMatch = _openMatches.firstWhereOrNull(
      (m) => m.originalMatch == matchState.originalMatch,
    );

    matchState.setMatch(spanData);
    _openMatches.remove(openMatch);
    _openMatches.add(matchState);
  }

  /// Accepts the given [matchState], updates text and state lists,
  /// and returns the updated [PangeaMatch].
  ///
  /// Applies the selected replacement text to [_currentText] and
  /// updates offsets for all matches accordingly.
  PangeaMatch acceptMatch(
    PangeaMatchState matchState,
    PangeaMatchStatusEnum status,
  ) {
    final openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == matchState.originalMatch,
      orElse: () => throw StateError(
        'No open match found while accepting match.',
      ),
    );

    final choice = matchState.updatedMatch.match.selectedChoice;
    if (choice == null) {
      throw ArgumentError(
        'acceptMatch called with a null selectedChoice.',
      );
    }

    matchState.setStatus(status);
    _openMatches.remove(openMatch);
    _closedMatches.add(matchState);

    _applyReplacement(
      matchState.updatedMatch.match.offset,
      matchState.updatedMatch.match.length,
      choice.value,
    );

    return matchState.updatedMatch;
  }

  /// Ignores the given [matchState] and moves it to the closed match list.
  ///
  /// Returns the updated [PangeaMatch] after applying the ignore operation.
  PangeaMatch ignoreMatch(PangeaMatchState matchState) {
    final openMatch = _openMatches.firstWhere(
      (m) => m.originalMatch == matchState.originalMatch,
      orElse: () => throw StateError(
        'No open match found while ignoring match.',
      ),
    );

    matchState.setStatus(PangeaMatchStatusEnum.ignored);
    _openMatches.remove(openMatch);
    _closedMatches.add(matchState);
    return matchState.updatedMatch;
  }

  /// Undoes a previously accepted match by reverting the replacement
  /// and removing it from the closed match list.
  void undoMatch(PangeaMatchState matchState) {
    final closedMatch = _closedMatches.firstWhere(
      (m) => m.originalMatch == matchState.originalMatch,
      orElse: () => throw StateError(
        'No closed match found while undoing match.',
      ),
    );

    _closedMatches.remove(closedMatch);

    final selectedValue = matchState.updatedMatch.match.selectedChoice?.value;
    if (selectedValue == null) {
      throw StateError(
        'Cannot undo match without a selectedChoice value.',
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
  }

  /// Applies a text replacement to [_currentText] and adjusts match offsets.
  ///
  /// Called internally when a correction is accepted or undone.
  void _applyReplacement(
    int offset,
    int length,
    String replacement,
  ) {
    final start = _currentText.characters.take(offset);
    final end = _currentText.characters.skip(offset + length);
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
}
