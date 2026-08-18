import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix show Logs, Room, User;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_page.dart';
import 'package:fluffychat/routes/chat/calls/call_quick_replies.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Announces a call arriving for this account, wherever the learner happens to
/// be in the app.
///
/// Wraps the app rather than living on the chat screen: a call is worth
/// interrupting whatever someone is doing, and a learner reading a different
/// conversation would otherwise never know they were being called.
class IncomingCallBanner extends StatefulWidget {
  /// Nullable because the router supplies it, and it is null before the first
  /// route resolves.
  final Widget? child;

  const IncomingCallBanner({required this.child, super.key});

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner> {
  StreamSubscription<IncomingCallNotification>? _rings;
  Timer? _stillRinging;
  IncomingCallNotification? _ringing;
  String? _listeningTo;

  /// Notification event ids the learner has turned down.
  ///
  /// Keyed by the notification event, which is unique per call — so a decline
  /// holds for exactly the call it declined, and the next call from the same
  /// person (a different notification) rings normally.
  final Set<String> _declined = {};

  @override
  void initState() {
    super.initState();
    // Deferred: Matrix.of needs a mounted context, and the call service is
    // per-account and resolved from it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The active account can change under this widget. Without re-subscribing,
    // the banner would keep listening to the account active when it mounted and
    // never ring for the one the learner switched to.
    _listen();
  }

  void _listen() {
    if (!mounted) return;
    final matrixState = Matrix.of(context);
    final account = matrixState.client.clientName;
    if (account == _listeningTo) return;

    _rings?.cancel();
    _listeningTo = account;
    // A prompt belonging to the account we just left is not this one's.
    if (_ringing != null) setState(() => _ringing = null);

    _rings = matrixState.callService.incomingRings.listen((ring) {
      if (!mounted) return;
      // One at a time, and never one already turned down.
      if (_ringing != null || _declined.contains(ring.event.eventId)) return;
      setState(() => _ringing = ring);
      _watchForGiveUp(ring);
    });
  }

  /// Dismisses the prompt when the ring lifetime lapses.
  ///
  /// The notification carries how long it rings; after that the call is taken as
  /// unanswered and the prompt goes. Read from the notification, so nothing here
  /// touches the call machinery for a call this device has not joined.
  void _watchForGiveUp(IncomingCallNotification ring) {
    _stillRinging?.cancel();
    final remaining = ring.expiresAt.difference(DateTime.now());
    _stillRinging = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted && _ringing?.event.eventId == ring.event.eventId) _dismiss();
    });
  }

  @override
  void dispose() {
    _rings?.cancel();
    _stillRinging?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _stillRinging?.cancel();
    _stillRinging = null;
    if (mounted) setState(() => _ringing = null);
  }

  /// Turns the call down and tells the caller, so their phone stops ringing.
  void _decline(IncomingCallNotification ring) {
    _declined.add(ring.event.eventId);
    unawaited(
      Matrix.of(context).callService.decline(
        ring.event.room,
        notificationEventId: ring.event.eventId,
      ),
    );
    _dismiss();
  }

  /// Turns the call down and says why, in the conversation itself.
  ///
  /// The decline still goes out first: the caller's phone should stop ringing
  /// whether or not the message sends, and the message is the courtesy on top
  /// rather than the mechanism.
  void _declineWith(IncomingCallNotification ring, String message) {
    final room = ring.event.room;
    _decline(ring);
    unawaited(
      room.sendTextEvent(message).catchError((Object e, StackTrace s) {
        // The call is already declined and the prompt already gone. A message
        // that will not send must not resurrect either.
        matrix.Logs().w('Could not send the quick reply', e, s);
        return null;
      }),
    );
  }

  Future<void> _answer(IncomingCallNotification ring) async {
    _dismiss();
    if (!mounted) return;
    // Deliberately NOT gated on the caller still being visible in Matrix room
    // state. That read lags a join by seconds, so it was routinely empty at the
    // moment someone tapped answer — and answering did nothing at all. The SFU
    // is the rendezvous point: join it, and let presence decide from there
    // whether anyone is actually on the other end.
    await CallPage.show(
      context,
      ring.event.room,
      video: ring.isVideo,
      // Anchors this side's speaking analytics: the answering device does not
      // write the call to the timeline, the caller does.
      notificationEventId: ring.event.eventId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _ringing;
    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (ringing != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topCenter,
              // A call card is not a page banner. Constrained and centred so it
              // reads as a card on a tablet or a desktop window instead of a
              // strip pinned across the whole width.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _CallCard(
                  key: ValueKey(ringing.event.eventId),
                  ring: ringing,
                  onAnswer: () => _answer(ringing),
                  onDecline: () => _decline(ringing),
                  onQuickReply: (message) => _declineWith(ringing, message),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card itself: who is calling, and what can be done about it.
class _CallCard extends StatefulWidget {
  final IncomingCallNotification ring;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final void Function(String message) onQuickReply;

  const _CallCard({
    required this.ring,
    required this.onAnswer,
    required this.onDecline,
    required this.onQuickReply,
    super.key,
  });

  @override
  State<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<_CallCard>
    with SingleTickerProviderStateMixin {
  /// Whether the preset replies have taken over the card's action row.
  ///
  /// Shown in place rather than as a sheet on top: the card is already an
  /// overlay, and stacking a second one over it puts the learner two dismissals
  /// away from a ringing phone.
  bool _choosingReply = false;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  matrix.Room get _room => widget.ring.event.room;

  /// The caller, not the room. In a direct message the two usually agree, but a
  /// room named after something else would otherwise show the wrong name on the
  /// one screen where who is calling is the entire question.
  matrix.User get _caller =>
      _room.unsafeGetUserFromMemoryOrFallback(widget.ring.event.senderId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final caller = _caller;

    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween(
        begin: const Offset(0, -0.25),
        end: Offset.zero,
      ).animate(curve),
      child: FadeTransition(
        opacity: curve,
        child: Material(
          elevation: 12,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identity(theme, l10n, caller),
                const SizedBox(height: 14),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _choosingReply
                      ? CallQuickReplyList(
                          onPick: widget.onQuickReply,
                          onBack: () => setState(() => _choosingReply = false),
                        )
                      : _actions(theme, l10n),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme, L10n l10n, matrix.User caller) => Row(
    children: [
      Avatar(
        mxContent: caller.avatarUrl,
        name: caller.calcDisplayname(),
        size: 52,
        showPresence: false,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caller.calcDisplayname(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            // The full Matrix id, so two people with the same display name are
            // still distinguishable at the moment of answering.
            Text(
              caller.id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.ring.isVideo ? Icons.videocam : Icons.call,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.ring.isVideo
                      ? l10n.callIncomingVideo
                      : l10n.callIncomingVoice,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _actions(ThemeData theme, L10n l10n) => Row(
    children: [
      Expanded(
        child: TextButton.icon(
          onPressed: () => setState(() => _choosingReply = true),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(l10n.callQuickReply, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _CircleAction(
        icon: Icons.call_end,
        tooltip: l10n.callDecline,
        background: theme.colorScheme.error,
        foreground: theme.colorScheme.onError,
        onPressed: widget.onDecline,
      ),
      const SizedBox(width: 10),
      _CircleAction(
        icon: widget.ring.isVideo ? Icons.videocam : Icons.call,
        tooltip: l10n.callAnswer,
        // Answer is the affirmative action and green is what every calling
        // product uses for it; the scheme's primary is not reliably distinct
        // from the decline colour across this app's themes.
        background: const Color(0xFF2E7D32),
        foreground: Colors.white,
        onPressed: widget.onAnswer,
      ),
    ],
  );
}

/// A round call action, sized to be an easy target on a phone.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: foreground, size: 22),
          ),
        ),
      ),
    ),
  );
}
