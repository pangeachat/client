import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import '../../widgets/matrix.dart';

class TransparentBackdrop extends StatelessWidget {
  final Color? backgroundColor;
  final VoidCallback? onDismiss;
  final bool blurBackground;

  final bool animateBackground;
  final Duration backgroundAnimationDuration;

  /// True when the overlay this backdrop belongs to ignores pointers (an
  /// `IgnorePointer` sits above it). Its Dismiss control can then never fire,
  /// so its semantics node must be transparent to native pointer hit-testing
  /// too: on web the engine gives every button-role node `pointer-events: all`
  /// whether or not it still carries a tap action, and a full-screen node with
  /// that style swallows the mouse events the DOM platform views beneath it
  /// need — an activity session's YouTube `<iframe>` went dead behind the
  /// pointer-ignored suggestion card and star animations this way (#8903).
  final bool ignoresPointer;

  const TransparentBackdrop({
    super.key,
    this.onDismiss,
    this.backgroundColor,
    this.blurBackground = false,
    this.animateBackground = false,
    this.backgroundAnimationDuration = const Duration(milliseconds: 200),
    this.ignoresPointer = false,
  });

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
            label: L10n.of(context).dismiss,
            button: true,
            hitTestBehavior: ignoresPointer
                ? SemanticsHitTestBehavior.transparent
                : SemanticsHitTestBehavior.defer,
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
          ),
        );
      },
    );
  }
}
