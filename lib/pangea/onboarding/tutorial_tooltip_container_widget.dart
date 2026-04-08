import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

class TutorialTooltipContainerWidget extends StatelessWidget {
  final double width;
  final double height;
  final double padding;
  final Widget child;

  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool showPrevious;

  final int currentStep;
  final int totalSteps;

  const TutorialTooltipContainerWidget({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.padding = 8.0,
    required this.onNext,
    required this.onPrevious,
    this.showPrevious = false,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      elevation: 4,
      child: SizedBox(
        width: width + padding * 2,
        height: height + padding,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, height: height, child: child),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(56, 24),
                  foregroundColor: theme.colorScheme.onPrimary,
                  backgroundColor: theme.colorScheme.primary,
                ),
                child: Text(
                  L10n.of(context).next,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
            if (showPrevious)
              Positioned(
                bottom: 0,
                left: 0,
                child: ElevatedButton(
                  onPressed: onPrevious,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(56, 24),
                    foregroundColor: theme.colorScheme.onSecondary,
                    backgroundColor: theme.colorScheme.secondary,
                  ),
                  child: Text(
                    L10n.of(context).previous,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondary,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Text(
                    "$currentStep / $totalSteps",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.surface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
