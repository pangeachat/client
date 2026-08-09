import 'dart:ui';

import 'package:flutter/material.dart';

class DialogWrapper extends StatelessWidget {
  final Color backgroundColor;
  final double borderRadius;
  final BorderSide side;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final double maxHeight;
  final Widget child;

  const DialogWrapper({
    super.key,
    required this.backgroundColor,
    this.borderRadius = 20.0,
    this.side = BorderSide.none,
    this.padding = const EdgeInsets.all(12.0),
    this.maxWidth = 400.0,
    this.maxHeight = double.infinity,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Dialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: side,
        ),
        child: Container(
          padding: padding,
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: child,
        ),
      ),
    );
  }
}
