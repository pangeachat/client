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
                token: PanelToken(
                  PanelTypesEnum.session,
                  RoomTokenParam.parse('!x'),
                ),
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
}
