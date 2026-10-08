import 'package:flutter/material.dart';

import 'package:fluffychat/features/network_filter/filtered_network_controller.dart';
import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The banner for a network that blocks the chat server or the Pangea API,
/// on every page including sign-in. See filtered-network.instructions.md,
/// "What the user sees".
///
/// Mounted above the router's Navigator, like [IncomingCallBanner], and bound
/// by the same two rules: nothing here may need an Overlay (so no Tooltip),
/// and no Material may carry elevation or a clip, which the CanvasKit web
/// renderer repaints as a grey box on hover.
class FilteredNetworkBanner extends StatefulWidget {
  final Widget? child;

  const FilteredNetworkBanner({required this.child, super.key});

  @override
  State<FilteredNetworkBanner> createState() => _FilteredNetworkBannerState();
}

class _FilteredNetworkBannerState extends State<FilteredNetworkBanner> {
  /// What was blocked when the user dismissed the banner. It comes back when
  /// another host is blocked.
  Set<NetworkHostCategory> _dismissedFor = const {};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onErrorContainer;
    final blockedNotifier = FilteredNetworkController.instance.blocked;
    return ListenableBuilder(
      listenable: Listenable.merge([
        blockedNotifier,
        FilteredNetworkDialog.isShowing,
      ]),
      child: widget.child,
      builder: (context, child) {
        final blocked = blockedNotifier.value;
        final stopping = blocked.where((category) => category.stopsApp).toSet();
        // A block that cleared and came back is news again.
        if (stopping.isEmpty) _dismissedFor = const {};
        final show =
            stopping.isNotEmpty &&
            !_dismissedFor.containsAll(stopping) &&
            !FilteredNetworkDialog.isShowing.value;
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (show)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: Material(
                        color: theme.colorScheme.errorContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off_outlined, color: ink),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.filteredNetworkBlockedTitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ink,
                                  ),
                                ),
                              ),
                              Semantics(
                                button: true,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: FilteredNetworkDialog.show,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      l10n.filteredNetworkWhatCanIDo,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(color: ink),
                                    ),
                                  ),
                                ),
                              ),
                              Semantics(
                                button: true,
                                label: l10n.close,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () =>
                                      setState(() => _dismissedFor = blocked),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.close,
                                      size: 20,
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
