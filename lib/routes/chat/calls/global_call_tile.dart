import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/routes/chat/calls/call_panel.dart';
import 'package:fluffychat/routes/chat/calls/call_session.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Keeps a live call visible when its chat is not.
///
/// The in-chat host presents the call while the call's room is open; the
/// moment the user navigates anywhere else, this floats a slim tile over the
/// app so the call is never out of reach. Tapping it goes back to the call's
/// room, where the in-chat host takes over again — the two hand off through
/// the session's presenter count, so exactly one of them shows at a time.
class GlobalCallTile extends StatelessWidget {
  /// Nullable for the same reason the banner's is: the router supplies it, and
  /// it is null before the first route resolves.
  final Widget? child;

  const GlobalCallTile({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    return ValueListenableBuilder(
      valueListenable: matrix.activeCall,
      builder: (context, session, _) {
        final content = child ?? const SizedBox.shrink();
        if (session == null) return content;
        return Stack(
          children: [
            content,
            ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                // The summary is the one part of "over" that still shows.
                if (session.isOver && !session.showingSummary) {
                  return const SizedBox.shrink();
                }
                // Fullscreen covers the whole app from HERE, wherever the user
                // is — the in-chat host stands down while it is on.
                if (session.fullscreen) {
                  return Positioned.fill(child: CallPanel(session: session));
                }
                if (session.hasPresenter) {
                  return const SizedBox.shrink();
                }
                final wide = FluffyThemes.isColumnMode(context);
                return Positioned(
                  top: 8,
                  // On a wide window, sit over the content area rather than
                  // the navigation column; on a phone, span the width.
                  left: wide ? FluffyThemes.columnWidth : 8,
                  right: 8,
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: CallMiniTile(
                          session: session,
                          onOpen: () => _openCall(context, session),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Back to the call, expanded. Navigation uses the app's router directly
  /// because this widget lives above it.
  ///
  /// A call on a NON-ACTIVE account has no chat to go back to: `ChatPage`
  /// resolves its room through the ACTIVE client, so this route would land on
  /// RoomUnavailablePanel with a live call playing behind it. That call goes
  /// fullscreen instead — the full panel, over the whole app, without touching
  /// the route. This tile only renders while the session is NOT fullscreen
  /// (the fullscreen branch returns above it), so the toggle here is always
  /// off-to-on.
  void _openCall(BuildContext context, CallSession session) {
    session.expand();
    if (!identical(session.room.client, Matrix.of(context).client)) {
      session.toggleFullscreen();
      return;
    }
    final router = FluffyChatApp.router;
    final uri = router.routeInformationProvider.value.uri;
    router.go(WorkspaceNav.openRoomById(uri, session.room.id));
  }
}
