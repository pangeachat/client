import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/animated_progress_bar.dart';

/// The onboarding page's header: the Back button and the progress bar, sized
/// like the Material 3 app bar it replaces. Deliberately not an `AppBar`: an
/// app bar is a semantics container of its own, which a screen reader has to
/// enter separately. Here both controls are direct children of the step
/// group, one step up from the center content
/// (accessibility.instructions.md § Focus after an in-place content swap).
class OnboardingHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool hasPrevStep;
  final double progress;
  final int step;
  final int totalSteps;
  final VoidCallback onBack;

  const OnboardingHeader({
    super.key,
    required this.hasPrevStep,
    required this.progress,
    required this.step,
    required this.totalSteps,
    required this.onBack,
  });

  static const double height = 64.0;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: height,
        child: Center(
          child: ConstrainedBox(
            // Fixed at the widest step's width (840, the language grid)
            constraints: const BoxConstraints(maxWidth: 840.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  // A new Back button per step: the control a screen reader
                  // pressed then leaves the tree like any other, so it cannot
                  // keep a stale view of the step from the button it sat on.
                  hasPrevStep
                      ? BackButton(key: ValueKey(step), onPressed: onBack)
                      : const SizedBox(width: 40.0),
                  Expanded(
                    child: Semantics(
                      container: true,
                      label: L10n.of(
                        context,
                      ).onboardingStepOfTotal(step, totalSteps),
                      child: AnimatedProgressBar(
                        height: 25.0,
                        widthPercent: progress,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
