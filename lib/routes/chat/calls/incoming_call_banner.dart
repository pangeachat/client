import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix show Room;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_page.dart';
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
  /// unanswered and the prompt goes. A caller who hangs up sooner is covered by
  /// the check at answer time — the prompt may linger to the lifetime, but
  /// answering a call the caller has left does not join one. Read from the
  /// notification, so nothing here touches the call machinery for a call this
  /// device has not joined.
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

  Future<void> _answer(IncomingCallNotification ring) async {
    // A caller can give up between the prompt appearing and the tap. Joining a
    // call the caller has left would open a call of one and write it to the
    // room, so the caller's presence is checked at the moment of answering.
    final calls = Matrix.of(context).callService;
    final callerThere = calls.otherUserInCall(ring.event.room);
    _dismiss();
    if (!callerThere || !mounted) return;
    // Whether this rings is derived inside ActiveCall from whether the call
    // already exists — it does, so this joins without ringing.
    await CallPage.show(context, ring.event.room, video: ring.isVideo);
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _ringing;
    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (ringing != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: _Banner(
              room: ringing.event.room,
              video: ringing.isVideo,
              onAnswer: () => _answer(ringing),
              onDecline: () => _decline(ringing),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final matrix.Room room;
  final bool video;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const _Banner({
    required this.room,
    required this.video,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(video ? Icons.videocam : Icons.call),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    room.getLocalizedDisplayname(),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(l10n.callIncoming, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            TextButton(onPressed: onDecline, child: Text(l10n.callDecline)),
            const SizedBox(width: 4),
            FilledButton(onPressed: onAnswer, child: Text(l10n.callAnswer)),
          ],
        ),
      ),
    );
  }
}
