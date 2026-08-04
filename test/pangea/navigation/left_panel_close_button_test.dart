import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';

void main() {
  testWidgets(
    'closing a session reads the LIVE url, not a stale currentUri prop (#7268)',
    (tester) async {
      // The left panel does NOT rebuild when only the RIGHT column changes (so
      // the live chat is not torn down). So the close button can hold a
      // currentUri captured when the session opened (right=analytics:sessions)
      // while the live url has since moved to analytics:grammar. Closing must use
      // the live url, or closeLeft "restores" the stale open-time right tab.
      final staleUri = Uri.parse('/?left=session:!x&right=analytics:sessions');
      const liveLocation = '/?left=session:!x&right=analytics:grammar';

      final router = GoRouter(
        initialLocation: liveLocation,
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: LeftPanelCloseButton(
                token: SessionPanelToken(RoomTokenParam.parse('!x')),
                currentUri: staleUri, // STALE on purpose
                foldedOver: false,
                isColumnMode: true,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      final result = router.routerDelegate.currentConfiguration.uri;
      final panels = parseOpenPanels(result);

      // The session token is dropped...
      expect(
        panels.left.any((t) => t.type == PanelTypesEnum.session),
        isFalse,
        reason: 'the session token should be dropped on close',
      );
      // ...and the right column stays on the LIVE tab (grammar), NOT reverting to
      // the stale open-time tab (sessions). Pre-fix this was analytics:sessions.
      expect(
        panels.right.any(
          (t) =>
              t.type == PanelTypesEnum.analytics &&
              t.param?.build() == 'grammar',
        ),
        isTrue,
        reason:
            'close must preserve the live right column (analytics:grammar), not '
            'restore the stale open-time tab (analytics:sessions): got $result',
      );
    },
  );

  testWidgets(
    'a stale-token room close still drops the LIVE token for that room (#8142)',
    (tester) async {
      // A room panel's chat renders inside a room-keyed nested Navigator whose
      // route captures the close button built at open time. When the same room
      // reopens under a DIFFERENT token — `room:!x` from the chat list, then
      // `session:!x` from the Stars archive after the activity ends — the
      // reparented Navigator can surface a close button still holding the
      // departed `room` token. Dropping that token from the live URL is a
      // no-op: the back button did nothing. The close must resolve what to
      // drop by ROOM ID against the live URL instead.
      const liveLocation = '/?left=chats,session:!x&right=analytics:sessions';

      final router = GoRouter(
        initialLocation: liveLocation,
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: LeftPanelCloseButton(
                // STALE on purpose: the token the room was first opened under,
                // captured before the swap to `session:!x`.
                token: RoomPanelToken(RoomTokenParam.parse('!x')),
                currentUri: Uri.parse(liveLocation),
                foldedOver: false,
                isColumnMode: true,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      final result = router.routerDelegate.currentConfiguration.uri;
      final panels = parseOpenPanels(result);

      expect(
        panels.left.any((t) => t.type == PanelTypesEnum.session),
        isFalse,
        reason:
            'the close must drop the live session token for the room, even '
            'when the button captured the stale room token: got $result',
      );
      // Only the room's own token is dropped — the chat list beneath survives.
      expect(
        panels.left.any((t) => t.type == PanelTypesEnum.chats),
        isTrue,
        reason: 'closing the room panel must not close the chat list beneath',
      );
    },
  );
}
