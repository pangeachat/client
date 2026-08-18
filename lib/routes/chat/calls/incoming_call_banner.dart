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
  Timer? _stillRinging;
  matrix.Room? _ringing;
  String? _listeningTo;

  /// Rooms whose current call the learner has turned down.
  ///
  /// Held while that call is still live and dropped the moment it ends, so the
  /// repeated discoveries that arrive while a caller waits are ignored and a
  /// caller who hangs up and tries again gets through immediately.
  ///
  /// Observed rather than timed: nothing in a membership distinguishes one call
  /// from the next, but "the caller is no longer there" is plain to see.
  final Set<String> _declined = {};
  Timer? _watchDeclined;

  /// How long a call rings before it is taken as unanswered.
  ///
  /// A caller who closes their app without leaving cleanly stops renewing their
  /// membership, but that takes longer to lapse than anyone will sit looking at
  /// a prompt.
  static const _ringFor = Duration(seconds: 60);

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
    // the banner would keep listening to the account that was active when it
    // mounted and never ring for the one the learner switched to.
    _listen();
  }

  void _listen() {
    if (!mounted) return;
    final matrixState = Matrix.of(context);
    final account = matrixState.client.clientName;
    if (account == _listeningTo) return;

    _calls?.cancel();
    _listeningTo = account;
    // A prompt belonging to the account we just left is not this one's.
    if (_ringing != null) setState(() => _ringing = null);

    final calls = matrixState.callService;
    // Arms discovery. Without it an account that had never placed a call could
    // never receive one — nothing would be watching for a membership to appear.
    unawaited(calls.listenForCalls());
    _calls = calls.incomingCalls.listen((room) {
      if (!mounted) return;
      // One at a time. A second call arriving while the first is ringing keeps
      // the first on screen rather than swapping under the learner's finger as
      // they reach to answer.
      if (_ringing != null) return;
      if (_declined.contains(room.id)) return;
      setState(() => _ringing = room);
      _watchForGiveUp(room);
    });
  }

  /// Dismisses the prompt when the caller stops calling.
  ///
  /// The call membership is the truth here: it goes when they hang up, and it
  /// lapses when their app dies. Polling it is what keeps a prompt from
  /// outliving the call — and from letting a learner answer into an empty room.
  void _watchForGiveUp(matrix.Room room) {
    _stillRinging?.cancel();
    final until = DateTime.now().add(_ringFor);
    _stillRinging = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      final calls = Matrix.of(context).callService;
      if (calls.isRinging(room) && DateTime.now().isBefore(until)) return;
      timer.cancel();
      _dismiss();
    });
  }

  @override
  void dispose() {
    _calls?.cancel();
    _stillRinging?.cancel();
    _watchDeclined?.cancel();
    super.dispose();
  }

  /// Turns the prompt down and remembers it, so the same call does not ask
  /// again while the caller is still waiting.
  void _decline() {
    final room = _ringing;
    if (room != null) {
      _declined.add(room.id);
      _watchDeclinedCalls();
    }
    _dismiss();
  }

  /// Forgets a decline once that call has actually ended.
  ///
  /// Without this the learner would be unreachable from that conversation until
  /// some arbitrary window lapsed — a caller who hung up and rang straight back
  /// would not get through, which is exactly when someone rings back.
  void _watchDeclinedCalls() {
    _watchDeclined?.cancel();
    _watchDeclined = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _declined.isEmpty) {
        timer.cancel();
        return;
      }
      final calls = Matrix.of(context).callService;
      _declined.removeWhere((roomId) => !calls.isRingingIn(roomId));
      if (_declined.isEmpty) timer.cancel();
    });
  }

  void _dismiss() {
    _stillRinging?.cancel();
    _stillRinging = null;
    if (mounted) setState(() => _ringing = null);
  }

  Future<void> _answer(matrix.Room room) async {
    // Answering clears any earlier decline: the learner has plainly changed
    // their mind, and a lingering one would suppress the next call for nothing.
    _declined.remove(room.id);
    // Checked at the moment of answering, not when the prompt appeared. A
    // caller can give up between the two, and joining then would open a call of
    // one and write it to the room as though it happened.
    final live = Matrix.of(context).callService.isRinging(room);
    _dismiss();
    if (!live || !mounted) return;
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
              onDecline: _decline,
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
