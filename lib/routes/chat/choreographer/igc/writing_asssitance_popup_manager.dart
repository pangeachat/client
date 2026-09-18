import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/routes/chat/choreographer/choreographer.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum _WritingAsssitancePopupState { closed, open, closing }

class WritingAssistancePopupManager {
  final Choreographer choreographer;
  final Future Function(String) onFeedbackSubmitted;

  WritingAssistancePopupManager({
    required this.choreographer,
    required this.onFeedbackSubmitted,
  });

  static const _overlayKey = 'writing-assistance-popup-overlay';

  _WritingAsssitancePopupState _state = _WritingAsssitancePopupState.closed;

  Completer<void>? _closingCompleter;
  Future<void>? _closingFuture;

  bool get isOpen => _state == _WritingAsssitancePopupState.open;

  /// [openOverlay] reports whether an entry was actually inserted.
  ///
  /// The state may only advance to `open` on a card that really mounted. The
  /// only thing that ever brings it back to `closed` is the overlay's own
  /// `WritingAssistancePopup` being disposed, so recording `open` for a card
  /// that never appeared wedges this manager for the life of the chat: every
  /// later `open` returns early here, `showNextMatch` skips its open block on
  /// [isOpen] while still moving the active match, and the [close] a writing
  /// assistance run awaits never completes. The learner sees highlights that
  /// answer their taps with no card, until they reload the page (#8980).
  void open(
    BuildContext context, {
    required bool Function(String) openOverlay,
  }) {
    if (_state != _WritingAsssitancePopupState.closed) return;

    MatrixState.pAnyState.closeAllOverlays();
    if (!openOverlay(_overlayKey)) {
      // Expected when something is legitimately in the way — a blocking
      // tutorial overlay, or a composer too torn down to measure. Staying
      // `closed` is what lets the next attempt succeed.
      Logs().w("Writing assistance popup did not open");
      return;
    }

    _state = _WritingAsssitancePopupState.open;
  }

  Future<void> close() {
    if (_state == _WritingAsssitancePopupState.closed) {
      return Future.value();
    }

    if (_state == _WritingAsssitancePopupState.closing) {
      return _closingFuture!;
    }

    _state = _WritingAsssitancePopupState.closing;

    _closingCompleter = Completer<void>();
    _closingFuture = _closingCompleter!.future;

    MatrixState.pAnyState.closeOverlay(_overlayKey);

    return _closingFuture!;
  }

  void onOverlayClosed() {
    if (_state != _WritingAsssitancePopupState.closing) {
      Logs().w("Received close callback while not closing");
    }

    _closingCompleter?.complete();
    _closingCompleter = null;
    _closingFuture = null;
    _state = _WritingAsssitancePopupState.closed;
  }
}
