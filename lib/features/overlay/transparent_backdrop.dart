import 'dart:ui';

import 'package:flutter/material.dart';

import '../../widgets/matrix.dart';

class TransparentBackdrop extends StatelessWidget {
  final Color? backgroundColor;
  final VoidCallback? onDismiss;
  final bool blurBackground;

  /// Accessible name of the backdrop as a dismiss control, the way a
  /// `ModalBarrier` names its barrier (#8783). Unset, the backdrop publishes
  /// no name and no dismiss action.
  final String? dismissLabel;

  final bool animateBackground;
  final Duration backgroundAnimationDuration;

  const TransparentBackdrop({
    super.key,
    this.onDismiss,
    this.backgroundColor,
    this.blurBackground = false,
    this.dismissLabel,
    this.animateBackground = false,
    this.backgroundAnimationDuration = const Duration(milliseconds: 200),
  });

  void _dismiss() {
    onDismiss?.call();
    MatrixState.pAnyState.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final Color targetColor =
        backgroundColor?.withAlpha((0.8 * 255).round()) ?? Colors.transparent;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: animateBackground ? 0.0 : 1.0, end: 1.0),
      duration: animateBackground ? backgroundAnimationDuration : Duration.zero,
      builder: (context, t, child) {
        return Material(
          borderOnForeground: false,
          color: Color.lerp(Colors.transparent, targetColor, t),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            label: dismissLabel,
            onDismiss: dismissLabel != null ? _dismiss : null,
            child: InkWell(
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: _dismiss,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurBackground ? 3.0 * t : 0,
                  sigmaY: blurBackground ? 3.0 * t : 0,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}
