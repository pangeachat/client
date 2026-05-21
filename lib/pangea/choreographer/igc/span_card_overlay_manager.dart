import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_card.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/widgets/matrix.dart';

enum _SpanCardOverlayState { closed, open, closing }

class SpanCardOverlayManager {
  final Choreographer choreographer;
  final Future Function(String) onFeedbackSubmitted;

  SpanCardOverlayManager({
    required this.choreographer,
    required this.onFeedbackSubmitted,
  });

  static const _overlayKey = 'span-card-overlay';

  _SpanCardOverlayState _state = _SpanCardOverlayState.closed;

  Completer<void>? _closingCompleter;
  Future<void>? _closingFuture;

  bool get isOpen => _state == _SpanCardOverlayState.open;

  void open(BuildContext context) {
    if (_state != _SpanCardOverlayState.closed) return;
    _state = _SpanCardOverlayState.open;

    MatrixState.pAnyState.closeAllOverlays();
    OverlayUtil.showPositionedCard(
      overlayKey: _overlayKey,
      context: context,
      cardToShow: SpanCard(controller: this),
      maxHeight: 325,
      maxWidth: 325,
      transformTargetId: ChoreoConstants.inputTransformTargetKey,
      ignorePointer: true,
      isScrollable: false,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
    );
  }

  Future<void> close() {
    if (_state == _SpanCardOverlayState.closed) {
      return Future.value();
    }

    if (_state == _SpanCardOverlayState.closing) {
      return _closingFuture!;
    }

    _state = _SpanCardOverlayState.closing;

    _closingCompleter = Completer<void>();
    _closingFuture = _closingCompleter!.future;

    MatrixState.pAnyState.closeOverlay(_overlayKey);

    return _closingFuture!;
  }

  void onOverlayClosed() {
    if (_state != _SpanCardOverlayState.closing) {
      Logs().w("Received close callback while not closing");
    }

    _closingCompleter?.complete();
    _closingCompleter = null;
    _closingFuture = null;
    _state = _SpanCardOverlayState.closed;
  }
}
