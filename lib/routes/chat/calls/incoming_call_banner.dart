import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix show Room;

import 'package:fluffychat/l10n/l10n.dart';
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
  StreamSubscription<matrix.Room>? _calls;
  matrix.Room? _ringing;

  @override
  void initState() {
    super.initState();
    // Deferred: Matrix.of needs a context that has been mounted, and the call
    // service is per-account and resolved from it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _listen() {
    if (!mounted) return;
    _calls = Matrix.of(context).callService.incomingCalls.listen((room) {
      if (!mounted) return;
      // One at a time. A second call arriving while the first is ringing keeps
      // the first on screen rather than swapping under the learner's finger as
      // they reach to answer.
      if (_ringing != null) return;
      setState(() => _ringing = room);
    });
  }

  @override
  void dispose() {
    _calls?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (mounted) setState(() => _ringing = null);
  }

  Future<void> _answer(matrix.Room room) async {
    _dismiss();
    await CallPage.show(context, room, video: false);
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
              room: ringing,
              onAnswer: () => _answer(ringing),
              onDecline: _dismiss,
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final matrix.Room room;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const _Banner({
    required this.room,
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
            const Icon(Icons.call),
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
