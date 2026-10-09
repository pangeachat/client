import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';

/// The single forward CTA at the bottom of an onboarding step.
///
/// Filled with the `primary` colour — matching the activity start page's
/// primary CTA — so it can't be confused with the tonal `secondaryContainer`
/// selection options above it (#8639).
///
/// [error] is the failure of the last press, shown above the button so the
/// person knows to press it again. Steps that show their failures elsewhere
/// leave it null.
class OnboardingForwardButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool loading;
  final Object? error;

  const OnboardingForwardButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = this.error;
    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          ErrorIndicator(
            message: error.toLocalizedString(context),
            error: error,
          ),
        ElevatedButton(
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
                          backgroundColor: theme.colorScheme.onPrimary
                              .withValues(alpha: 0.24),
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
        ),
      ],
    );
  }
}
