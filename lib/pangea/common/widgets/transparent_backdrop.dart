import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../widgets/matrix.dart';

class TransparentBackdrop extends StatelessWidget {
  final Color? backgroundColor;
  final VoidCallback? onDismiss;
  final bool blurBackground;

  /// New
  final bool animateBackground;
  final Duration backgroundAnimationDuration;

  const TransparentBackdrop({
    super.key,
    this.onDismiss,
    this.backgroundColor,
    this.blurBackground = false,
    this.animateBackground = false,
    this.backgroundAnimationDuration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final Color targetColor =
        backgroundColor?.withAlpha((0.8 * 255).round()) ?? Colors.transparent;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: animateBackground ? 0.0 : 1.0,
        end: 1.0,
      ),
      duration: animateBackground ? backgroundAnimationDuration : Duration.zero,
      builder: (context, t, child) {
        return Material(
          borderOnForeground: false,
          color: Color.lerp(
            Colors.transparent,
            targetColor,
            t,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            onTap: () {
              onDismiss?.call();
              MatrixState.pAnyState.closeOverlay();
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurBackground ? 3.0 * t : 0,
                sigmaY: blurBackground ? 3.0 * t : 0,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}
