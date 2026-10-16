import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';

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

  /// The app's router, which this banner sits above: the practice offer opens
  /// practice through it and hides while practice is open. Without one there
  /// is no offer.
  final GoRouter? router;

  const ConnectionBanner({required this.child, this.router, super.key});

  /// Whether this device can run an offline vocab session. Replaced in tests.
  @visibleForTesting
  static Future<bool> Function() canPracticeOffline =
      AnalyticsPracticeSessionRepo.canStartOffline;

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

  /// Whether this device can run an offline vocab session. Checked when the
  /// app loses Pangea rather than on every build, because the check reads the
  /// learner's whole vocab.
  bool _canPracticeOffline = false;
  bool _checkingPracticeOffline = false;

  @override
  void initState() {
    super.initState();
    ConnectionStatusController.instance.reachability.addListener(
      _checkPracticeOffline,
    );
    _checkPracticeOffline();
  }

  @override
  void dispose() {
    ConnectionStatusController.instance.reachability.removeListener(
      _checkPracticeOffline,
    );
    super.dispose();
  }

  void _checkPracticeOffline() {
    if (!ConnectionStatusController.instance.cannotReachPangea) {
      _canPracticeOffline = false;
      return;
    }
    if (widget.router == null) return;
    if (_canPracticeOffline || _checkingPracticeOffline) return;
    _checkingPracticeOffline = true;
    ConnectionBanner.canPracticeOffline()
        .then((canPractice) {
          if (canPractice && mounted) {
            setState(() => _canPracticeOffline = true);
          }
        })
        .whenComplete(() => _checkingPracticeOffline = false);
  }

  /// The practice offer's tap, or null when the banner makes no offer. See
  /// connection-status.instructions.md, "What the user sees".
  VoidCallback? _practiceOffer(VoidCallback dismiss) {
    final router = widget.router;
    if (router == null || !_canPracticeOffline) return null;
    final holder = PracticeSessionHolder.instance;
    if (holder.hasUnfinishedSession) return null;
    if (practiceIsOpen(router.routeInformationProvider.value.uri)) return null;

    return () {
      // The banner floats over the top of the page and would cover the
      // practice header.
      dismiss();
      // A finished session still held would reopen on its completion view.
      holder.end();
      router.go(
        WorkspaceNav.openPractice(
          router.routeInformationProvider.value.uri,
          ConstructTypeEnum.vocab,
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final blockedNotifier = FilteredNetworkController.instance.blocked;
    final statusNotifier = ConnectionStatusController.instance.status;
    return ListenableBuilder(
      listenable: Listenable.merge([
        blockedNotifier,
        statusNotifier,
        FilteredNetworkDialog.isShowing,
        PracticeSessionHolder.instance,
        ?widget.router?.routeInformationProvider,
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
      void dismiss() => setState(() => _filteredDismissedFor = blocked);
      return _BannerCard(
        icon: Icons.wifi_off_outlined,
        text: l10n.filteredNetworkBlockedTitle,
        actionLabel: l10n.filteredNetworkWhatCanIDo,
        onAction: FilteredNetworkDialog.show,
        onPractice: _practiceOffer(dismiss),
        onClose: dismiss,
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
        void dismiss() => setState(() => _connectionDismissedFor = status);
        return _BannerCard(
          icon: offline ? Icons.wifi_off_outlined : Icons.cloud_off_outlined,
          text: offline ? l10n.connectionOffline : l10n.connectionUnreachable,
          onPractice: _practiceOffer(dismiss),
          onClose: dismiss,
        );
    }
  }
}

class _BannerCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Starts offline vocab practice, on a row of its own under the message.
  final VoidCallback? onPractice;
  final VoidCallback? onClose;

  /// A good-news banner, in the calmer colours.
  final bool positive;

  const _BannerCard({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.onPractice,
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
    final onPractice = this.onPractice;
    final onClose = this.onClose;
    final message = Row(
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
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: positive ? colors.primaryContainer : colors.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, onClose == null ? 16 : 8, 8),
          child: onPractice == null
              ? message
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    message,
                    Semantics(
                      container: true,
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onPractice,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: [
                              Icon(
                                Symbols.fitness_center,
                                size: 18,
                                color: ink,
                              ),
                              Flexible(
                                child: Text(
                                  l10n.connectionPracticeVocab,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
