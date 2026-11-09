import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_session_start_page.dart';
import 'package:fluffychat/routes/chat/activity_sessions/confirmed_role_session_controller.dart';

/// #9532 — a session link opens the start page on a session the learner
/// already has a role in. Once every seat is filled, the waiting room gives
/// way to a single Continue into the chat (activity-start-page.instructions.md,
/// "The CTA row").
class _StartedSessionController extends ConfirmedRoleSessionController {
  var continued = false;

  @override
  bool get sessionStarted => true;

  @override
  void continueToChat() => continued = true;

  // Never mounted, so it has no context to localize with; the compact row
  // this test pumps doesn't show the description anyway.
  @override
  String get descriptionText => '';
}

void main() {
  testWidgets('a started session offers only Continue, which opens the chat', (
    tester,
  ) async {
    final session = _StartedSessionController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ActivitySessionButtons(
            controller: ActivitySessionStartState(),
            sessionController: session,
            compact: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = L10n.of(tester.element(find.byType(ActivitySessionButtons)));
    expect(find.text(l10n.continueText), findsOneWidget);
    expect(find.text(l10n.pingParticipants), findsNothing);
    expect(find.text(l10n.inviteFriends), findsNothing);
    expect(find.text(l10n.playWithBot), findsNothing);

    await tester.tap(find.text(l10n.continueText));
    expect(session.continued, isTrue);
  });
}
