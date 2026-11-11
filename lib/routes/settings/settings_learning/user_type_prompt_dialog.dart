import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

/// Asks for the self-identified role with onboarding's own question. Pops
/// the role picked, or null when skipped.
class UserTypePromptDialog extends StatelessWidget {
  const UserTypePromptDialog({super.key});

  /// Onboarding's order.
  static const List<UserType> _options = [UserType.teacher, UserType.student];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Centered so the column's stretch doesn't override its width.
              const Center(
                child: ExcludeSemantics(
                  child: BotFace(width: 100, expression: BotExpression.idle),
                ),
              ),
              Text(
                l10n.userTypeTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final type in _options)
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(type),
                  icon: Icon(type.icon),
                  label: Text(type.title(l10n)),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.skipForNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
