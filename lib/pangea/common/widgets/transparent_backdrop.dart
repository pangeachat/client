import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../widgets/matrix.dart';

class TransparentBackdrop extends StatelessWidget {
  final Color? backgroundColor;
  final VoidCallback? onDismiss;
  final bool blurBackground;

  const TransparentBackdrop({
    super.key,
    this.onDismiss,
    this.backgroundColor,
    this.blurBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderOnForeground: false,
      color:
          backgroundColor?.withAlpha((0.8 * 255).round()) ?? Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: () {
          if (onDismiss != null) {
            onDismiss!();
          }
          MatrixState.pAnyState.closeOverlay();
        },
        child: BackdropFilter(
          filter: blurBackground
              ? ImageFilter.blur(
                  sigmaX: 3.0,
                  sigmaY: 3.0,
                )
              : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Container(
            height: double.infinity,
            width: double.infinity,
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
