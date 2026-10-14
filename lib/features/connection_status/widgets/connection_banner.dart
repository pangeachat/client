import 'package:flutter/material.dart';

import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The one banner slot at the top of the app, on every page including
/// sign-in: the filtered-network banner when this network blocks the chat
/// server or the Pangea API, otherwise the connection banner when the
/// connection is lost. See connection-status.instructions.md, "What the user
/// sees".
///
/// Mounted above the router's Navigator, like [IncomingCallBanner], and bound
/// by the same two rules: nothing here may need an Overlay (so no Tooltip),
/// and no Material may carry elevation or a clip, which the CanvasKit web
/// renderer repaints as a grey box on hover.
class ConnectionBanner extends StatefulWidget {
  final Widget? child;

  const ConnectionBanner({required this.child, super.key});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  /// What was blocked when the user dismissed the filtered-network banner.
  /// It comes back when another host is blocked.
  Set<NetworkHostCategory> _filteredDismissedFor = const {};

  /// The lost-connection state the user dismissed. The banner comes back
  /// when the state changes.
  ConnectionStatus? _connectionDismissedFor;

  @override
  Widget build(BuildContext context) {
    final blockedNotifier = FilteredNetworkController.instance.blocked;
    final statusNotifier = ConnectionStatusController.instance.status;
    return ListenableBuilder(
      listenable: Listenable.merge([
        blockedNotifier,
        statusNotifier,
        FilteredNetworkDialog.isShowing,
      ]),
      child: widget.child,
      builder: (context, child) {
        final card = _card(
          context,
          blockedNotifier.value,
          statusNotifier.value,
        );
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (card != null)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: card,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The banner to show, or null for none. The filtered-network banner wins,
  /// because the user can act on it.
  Widget? _card(
    BuildContext context,
    Set<NetworkHostCategory> blocked,
    ConnectionStatus status,
  ) {
    final l10n = L10n.of(context);
    final stopping = blocked.where((category) => category.stopsApp).toSet();
    // A block that cleared and came back is news again.
    if (stopping.isEmpty) _filteredDismissedFor = const {};
    if (stopping.isNotEmpty) {
      if (FilteredNetworkDialog.isShowing.value ||
          _filteredDismissedFor.containsAll(stopping)) {
        return null;
      }
      return _BannerCard(
        icon: Icons.wifi_off_outlined,
        text: l10n.filteredNetworkBlockedTitle,
        actionLabel: l10n.filteredNetworkWhatCanIDo,
        onAction: FilteredNetworkDialog.show,
        onClose: () => setState(() => _filteredDismissedFor = blocked),
      );
    }

    // A blocked chat server is the filtered-network banner's to show, even
    // after the user dismissed it.
    if (blocked.contains(NetworkHostCategory.chatServer)) return null;

    if (!status.isLost) _connectionDismissedFor = null;
    switch (status) {
      case ConnectionStatus.connected:
        return null;
      case ConnectionStatus.backOnline:
        return _BannerCard(
          icon: Icons.wifi,
          text: l10n.connectionBackOnline,
          positive: true,
        );
      case ConnectionStatus.offline:
      case ConnectionStatus.unreachable:
        if (_connectionDismissedFor == status) return null;
        final offline = status == ConnectionStatus.offline;
        return _BannerCard(
          icon: offline ? Icons.wifi_off_outlined : Icons.cloud_off_outlined,
          text: offline ? l10n.connectionOffline : l10n.connectionUnreachable,
          onClose: () => setState(() => _connectionDismissedFor = status),
        );
    }
  }
}

class _BannerCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  /// A good-news banner, in the calmer colours.
  final bool positive;

  const _BannerCard({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.onClose,
    this.positive = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ink = positive ? colors.onPrimaryContainer : colors.onErrorContainer;
    final actionLabel = this.actionLabel;
    final onClose = this.onClose;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: positive ? colors.primaryContainer : colors.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, onClose == null ? 16 : 8, 8),
          child: Row(
            children: [
              Icon(icon, color: ink),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(color: ink),
                  ),
                ),
              ),
              if (actionLabel != null)
                // Each button is its own node: with one button, the live
                // region would otherwise merge the whole banner into it.
                Semantics(
                  container: true,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onAction,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        actionLabel,
                        style: theme.textTheme.labelLarge?.copyWith(color: ink),
                      ),
                    ),
                  ),
                ),
              if (onClose != null)
                Semantics(
                  container: true,
                  button: true,
                  label: l10n.close,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close, size: 20, color: ink),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
