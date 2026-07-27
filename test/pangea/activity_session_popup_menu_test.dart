import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_popup_menu.dart';
import 'get_test_client.dart';

/// The activity-session "More" (⋮) menu is shared between a live session and a
/// completed one (finished for everyone). A live session offers Invite / Leave /
/// Download; a completed session only offers Download — Invite and Leave no
/// longer apply once the session is over.
///
/// Download itself is web/desktop only for now (`kIsWeb`), so it never renders
/// in the VM test host; these tests pin the Invite/Leave visibility, which is
/// the behaviour the `isCompleted` flag controls.
void main() {
  late Client client;
  late Room room;
  late L10n l10n;

  setUp(() async {
    client = await getTestClient();
    room = Room(id: '!session:fakeServer.notExisting', client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    required bool isCompleted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10n.of(context);
            return Scaffold(
              body: ActivitySessionPopupMenu(
                room,
                onLeave: () {},
                isCompleted: isCompleted,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ActivitySessionPopupMenu));
    await tester.pumpAndSettle();
  }

  testWidgets('live session menu offers Invite and Leave', (tester) async {
    await pumpMenu(tester, isCompleted: false);
    expect(find.text(l10n.invite), findsOneWidget);
    expect(find.text(l10n.leave), findsOneWidget);
  });

  testWidgets('completed session menu hides Invite and Leave', (tester) async {
    await pumpMenu(tester, isCompleted: true);
    expect(find.text(l10n.invite), findsNothing);
    expect(find.text(l10n.leave), findsNothing);
  });
}
