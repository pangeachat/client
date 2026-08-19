import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

/// The preset replies offered when turning a call down.
///
/// Fixed and short by design. The value of a quick reply is that it takes one
/// tap while a phone is ringing; a longer list, or a free-text field, costs more
/// attention than simply declining and typing afterwards.
///
/// Translated, because the person being called reads them — they are not
/// analytics strings.
List<String> callQuickReplies(L10n l10n) => [
  l10n.callReplyCantTalk,
  l10n.callReplyCallRightBack,
  l10n.callReplyOnMyWay,
  l10n.callReplyCallLater,
];

/// The preset replies, shown in place of the call's action row.
class CallQuickReplyList extends StatelessWidget {
  /// Called with the chosen message. The caller declines the call and sends it.
  final void Function(String message) onPick;

  /// Returns to the answer and decline buttons, for someone who opened this by
  /// mistake while their phone is ringing.
  final VoidCallback onBack;

  const CallQuickReplyList({
    required this.onPick,
    required this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Semantics rather than the IconButton's tooltip: a tooltip overlay
            // greys the card on the CanvasKit web renderer, and the label a
            // screen reader needs does not have to come from one.
            Semantics(
              label: l10n.back,
              button: true,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.callQuickReplyTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final reply in callQuickReplies(l10n))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              // No clipBehavior. A clipped Material greys its whole area on the
              // CanvasKit web renderer when a child repaints, which a hover does.
              // The ripple is kept inside the rounded corners by the InkWell's
              // own borderRadius instead, which bounds the splash without a clip
              // layer to turn grey.
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPick(reply),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(reply, style: theme.textTheme.bodyMedium),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.send,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
