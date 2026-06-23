import 'dart:math';

import 'package:flutter/material.dart';

class OverlayContainer extends StatelessWidget {
  final Widget cardToShow;
  final Color? borderColor;
  final double maxHeight;
  final double maxWidth;
  final bool isScrollable;
  final double padding;

  const OverlayContainer({
    super.key,
    required this.cardToShow,
    this.borderColor,
    required this.maxHeight,
    required this.maxWidth,
    this.isScrollable = true,
    this.padding = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [cardToShow],
    );

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          width: 2,
          color: borderColor ?? Theme.of(context).colorScheme.primary,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(25)),
      ),
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        minHeight: min(100, maxHeight),
        minWidth: min(100, maxWidth),
      ),
      child: isScrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}
