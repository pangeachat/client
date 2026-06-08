import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/choreographer/choreographer.dart';
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

  void open(
    BuildContext context, {
    required void Function(String) openOverlay,
  }) {
    if (_state != _WritingAsssitancePopupState.closed) return;
    _state = _WritingAsssitancePopupState.open;

    MatrixState.pAnyState.closeAllOverlays();
    openOverlay(_overlayKey);
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
