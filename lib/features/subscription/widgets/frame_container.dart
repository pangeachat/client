import 'package:flutter/material.dart';

class FrameContainer extends StatelessWidget {
  final Widget child;
  final String title;

  final Color frameColor;
  final Color backgroundColor;
  final Color foregroundColor;

  final double borderWidth;
  final double borderRadius;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry titlePadding;

  const FrameContainer({
    super.key,
    required this.title,
    required this.child,
    required this.frameColor,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderWidth = 3,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(24),
    this.titlePadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: frameColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: EdgeInsets.all(borderWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - borderWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: frameColor,
              padding: titlePadding,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: foregroundColor,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: padding,
              decoration: BoxDecoration(color: backgroundColor),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
