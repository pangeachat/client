import 'package:flutter/material.dart';

import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/media_unavailable_note.dart';

/// A short note that the network blocks one feature — a video, an image, the
/// map — so the rest of the screen keeps working. See
/// connection-status.instructions.md, "What the user sees".
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
    return ValueListenableBuilder<Set<NetworkHostCategory>>(
      valueListenable: FilteredNetworkController.instance.blocked,
      child: child,
      builder: (context, blocked, child) {
        if (!blocked.contains(category)) {
          return child ?? const SizedBox.shrink();
        }
        return MediaUnavailableNote(
          icon: Icons.wifi_off_outlined,
          message: switch (category) {
            NetworkHostCategory.video => l10n.filteredNetworkVideoBlocked,
            NetworkHostCategory.images => l10n.filteredNetworkImagesBlocked,
            NetworkHostCategory.map => l10n.filteredNetworkMapBlocked,
            _ => l10n.filteredNetworkBlockedTitle,
          },
          actionLabel: l10n.filteredNetworkWhatCanIDo,
          onAction: FilteredNetworkDialog.show,
          fill: child != null,
        );
      },
    );
  }
}
