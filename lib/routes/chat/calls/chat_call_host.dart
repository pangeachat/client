import 'package:flutter/material.dart';

import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Hosts the active call INSIDE the chat it belongs to.
///
/// Mounted in every chat view's body stack; renders nothing unless the app's
/// one active call is for THIS room. Expanded, the call panel fills the chat
/// pane; minimized, a slim tile docks at the top and the conversation stays
/// usable underneath.
///
/// While this host is showing the call it registers itself as the call's
/// presenter, which is what keeps the GLOBAL floating tile away — the two can
/// never show at once, and the call is always visible somewhere.
class ChatCallHost extends StatefulWidget {
  final String roomId;

  const ChatCallHost({required this.roomId, super.key});

  @override
  State<ChatCallHost> createState() => _ChatCallHostState();
}

class _ChatCallHostState extends State<ChatCallHost> {
  ValueNotifier<CallSession?>? _sessions;
  CallSession? _attachedTo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = Matrix.of(context).activeCall;
    if (identical(sessions, _sessions)) return;
    _sessions?.removeListener(_onSessionChanged);
    _sessions = sessions..addListener(_onSessionChanged);
    _onSessionChanged();
  }

  /// The session this host should present: the app's active call, when it is
  /// for this host's room.
  CallSession? get _mine {
    final session = _sessions?.value;
    if (session == null || session.isOver) return null;
    return session.room.id == widget.roomId ? session : null;
  }

  void _onSessionChanged() {
    final mine = _mine;
    // Presence is registered from the fact of PRESENTING, not from being
    // mounted: a chat that is open but not the call's room presents nothing.
    if (mine != null && !identical(_attachedTo, mine)) {
      _attachedTo?.detachPresenter();
      _attachedTo = mine..attachPresenter();
    } else if (mine == null && _attachedTo != null) {
      _attachedTo?.detachPresenter();
      _attachedTo = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ChatCallHost old) {
    super.didUpdateWidget(old);
    // The framework can REUSE this State for a different room — same widget
    // type, same position in the tree, new roomId — and nothing else would
    // re-evaluate whose call this host presents. Without this, the old call
    // kept a presenter registered while this host rendered nothing, and the
    // global tile stood down too: a live call with no UI anywhere.
    if (old.roomId != widget.roomId) _onSessionChanged();
  }

  @override
  void dispose() {
    _sessions?.removeListener(_onSessionChanged);
    _attachedTo?.detachPresenter();
    _attachedTo = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _mine;
    if (session == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.isOver) return const SizedBox.shrink();
        // In fullscreen the GLOBAL host paints the panel over the whole app;
        // painting it here too would stack two copies.
        if (session.fullscreen) return const SizedBox.shrink();
        if (session.minimized) {
          // Docked at the top of the pane; the chat stays interactive below.
          return Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: SafeArea(
              child: CallMiniTile(session: session, onOpen: session.expand),
            ),
          );
        }
        return Positioned.fill(child: CallPanel(session: session));
      },
    );
  }
}
