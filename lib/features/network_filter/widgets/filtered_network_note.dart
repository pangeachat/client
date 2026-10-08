import 'package:flutter/material.dart';

import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// A short note that the network blocks one feature — a video, an image, the
/// map — so the rest of the screen keeps working. See
/// filtered-network.instructions.md, "What the user sees".
///
/// While [category] is blocked the note takes [child]'s place, filling its
/// space; with no [child] it stands alone. Otherwise it shows [child], or
/// nothing.
class FilteredNetworkNote extends StatelessWidget {
  final NetworkHostCategory category;
  final Widget? child;

  const FilteredNetworkNote({required this.category, this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<Set<NetworkHostCategory>>(
      valueListenable: FilteredNetworkController.instance.blocked,
      child: child,
      builder: (context, blocked, child) {
        if (!blocked.contains(category)) {
          return child ?? const SizedBox.shrink();
        }
        final note = Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            // Wraps rather than overflowing in a small image cell.
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Icon(
                  Icons.wifi_off_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Text(switch (category) {
                  NetworkHostCategory.video => l10n.filteredNetworkVideoBlocked,
                  NetworkHostCategory.images =>
                    l10n.filteredNetworkImagesBlocked,
                  NetworkHostCategory.map => l10n.filteredNetworkMapBlocked,
                  _ => l10n.filteredNetworkBlockedTitle,
                }),
                TextButton(
                  onPressed: FilteredNetworkDialog.show,
                  child: Text(l10n.filteredNetworkWhatCanIDo),
                ),
              ],
            ),
          ),
        );
        if (child == null) return note;
        return ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(child: note),
        );
      },
    );
  }
}
