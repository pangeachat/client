import 'package:flutter/widgets.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';

/// Headless shell resident that opens a pending DM invite
/// (DmInviteController.consumePending, #8436). Mounted by the workspace
/// shell, so it exists exactly when the user is logged in with the world map
/// up — the guard has already run — and it tries on the three occasions an
/// invite can become actionable:
///
/// - **mount** — a boot or post-login landing (the ferried logged-out click);
/// - **[uri] change** — any workspace navigation, which is how an invite that
///   deferred behind a pending join code or activity gets its turn once that
///   flow lands;
/// - **DmInviteController.pendingSignal** — the invite redirect just cached an
///   in-session link tap, which lands on a location that may not remount or
///   even change anything (the chat list already open on mobile).
///
/// Every trigger funnels into the same guarded consume, so overlapping
/// triggers are harmless. Renders nothing.
class DmInviteFerryConsumer extends StatefulWidget {
  final Uri uri;
  const DmInviteFerryConsumer({super.key, required this.uri});

  @override
  State<DmInviteFerryConsumer> createState() => _DmInviteFerryConsumerState();
}

class _DmInviteFerryConsumerState extends State<DmInviteFerryConsumer> {
  @override
  void initState() {
    super.initState();
    DmInviteController.pendingSignal.addListener(_tryConsume);
    _tryConsume();
  }

  @override
  void didUpdateWidget(covariant DmInviteFerryConsumer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _tryConsume();
  }

  @override
  void dispose() {
    DmInviteController.pendingSignal.removeListener(_tryConsume);
    super.dispose();
  }

  /// Post-frame, so a consume woken by a navigation or the signal runs against
  /// a built shell (the loading dialog needs its navigator). A post-frame
  /// callback only runs inside a frame, and the signal can arrive on an idle
  /// app — the redirect landed on the very location already showing (the chat
  /// list was open when the link was tapped), so nothing rebuilt and no frame
  /// was coming — hence the explicit frame request.
  void _tryConsume() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DmInviteController.consumePending(context);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
