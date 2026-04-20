import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_tooltip_widget.dart';

class TutorialTooltipContainerWidget extends StatelessWidget {
  final double width;
  final double height;
  final double padding;
  final String text;

  final VoidCallback onNext;
  final VoidCallback onPrevious;

  final bool showNext;
  final bool showPrevious;

  final int currentStep;
  final int totalSteps;

  const TutorialTooltipContainerWidget({
    super.key,
    required this.width,
    required this.height,
    required this.text,
    this.padding = 8.0,
    required this.onNext,
    required this.onPrevious,
    this.showNext = true,
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
              child: SizedBox(
                width: width,
                height: height,
                child: TutorialTooltipWidget(
                  text: text,
                  currentStep: currentStep,
                  totalSteps: totalSteps,
                ),
              ),
            ),
            if (showNext)
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
          ],
        ),
      ),
    );
  }
}
