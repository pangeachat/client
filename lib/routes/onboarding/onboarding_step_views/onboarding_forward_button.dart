import 'package:flutter/material.dart';

/// The single forward CTA at the bottom of an onboarding step.
///
/// Filled with the darker `primary` colour — matching the activity start
/// page's primary CTA — so it can't be confused with the lighter
/// `primaryContainer` selection options above it (#8639).
class OnboardingForwardButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool loading;

  const OnboardingForwardButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        minimumSize: const Size.fromHeight(48),
      ),
      child: SizedBox(
        height: 24,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: double.infinity,
                    child: LinearProgressIndicator(
                      color: theme.colorScheme.onPrimary,
                      backgroundColor: theme.colorScheme.onPrimary.withValues(
                        alpha: 0.24,
                      ),
                    ),
                  )
                : Text(
                    label,
                    key: const ValueKey('text'),
                    textAlign: TextAlign.center,
                  ),
          ),
        ),
      ),
    );
  }
}
