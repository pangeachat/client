import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/invitation_notice.dart';
import 'package:fluffychat/features/student_invitations/lti_link_page.dart';
import 'package:fluffychat/features/student_invitations/managed_consent.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// The three confirmation screens (SPEC §4 Student): the invite link's
/// sign-up/sign-in card, the in-app pending prompt, and the Canvas link
/// step. Each shows the mandatory checkbox with the module's full
/// disclosure text under it, and none confirms while it is unticked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('consent_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
    await lookupL10n(const Locale('en'));
  });

  const inv = 'Q2xhc3NJbnZpdGUtMDAx_-';
  const disclosure =
      "While you're in {course}, your teacher can limit who you can chat "
      "with. Your teacher can't read your private messages.";
  String shown(String course) => disclosure.replaceAll('{course}', course);

  late List<http.Request> sent;

  StudentInvitationApi api() => StudentInvitationApi(
    httpClient: MockClient((request) async {
      sent.add(request);
      final path = request.url.path;
      if (path.endsWith('/managed_disclosure')) {
        return http.Response(
          jsonEncode({'version': 2, 'text': disclosure}),
          200,
        );
      }
      if (path.endsWith('/student_invitations/hint')) {
        return http.Response(
          jsonEncode({
            'course_name': 'Spanish 101',
            'masked_email_hint': 'a***@school.edu',
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    }),
    homeserver: Uri.parse('https://matrix.example.org'),
  );

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  void expectDisclosureUnderCheckbox(WidgetTester tester, String course) {
    final checkbox = find.byKey(ManagedConsentPanel.checkboxKey);
    final text = find.text(shown(course));
    expect(checkbox, findsOneWidget);
    expect(text, findsOneWidget, reason: 'the full text, course filled in');
    expect(
      tester.getTopLeft(text).dy,
      greaterThan(tester.getTopLeft(checkbox).dy),
      reason: 'the disclosure sits under the checkbox',
    );
  }

  setUp(() async {
    sent = [];
    await SpaceCodeRepo.clearPendingInvitation();
    await SpaceCodeRepo.clearPendingLtiTicket();
  });

  group('full disclosure text shown under the checkbox on all three '
      'confirmation screens', () {
    testWidgets('1. invite link: the sign-up/sign-in card', (tester) async {
      const pending = PendingInvitation(inv);
      await SpaceCodeRepo.setPendingInvitation(pending);
      await tester.pumpWidget(
        host(InvitationNotice(pending: pending, api: api())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Spanish 101'), findsWidgets);
      expect(find.textContaining('a***@school.edu'), findsOneWidget);
      expectDisclosureUnderCheckbox(tester, 'Spanish 101');

      // Ticking is remembered across the sign-in for the post-login confirm.
      await tester.tap(find.byKey(ManagedConsentPanel.checkboxKey));
      await tester.pumpAndSettle();
      expect(SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion, 2);
      await tester.tap(find.byKey(ManagedConsentPanel.checkboxKey));
      await tester.pumpAndSettle();
      expect(SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion, isNull);
      expect(
        sent.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'nothing is confirmed before sign-in',
      );
    });

    testWidgets('2. in-app prompt: Confirm stays off until ticked', (
      tester,
    ) async {
      int? result = -1;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result = await ManagedConsentDialog.show(
                context,
                const ConsentRequest(courseName: 'Spanish 101'),
                api: api(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expectDisclosureUnderCheckbox(tester, 'Spanish 101');
      final confirm = find.byKey(ManagedConsentDialog.confirmKey);
      expect(tester.widget<AdaptiveDialogAction>(confirm).onPressed, isNull);

      await tester.tap(find.byKey(ManagedConsentPanel.checkboxKey));
      await tester.pumpAndSettle();
      expect(tester.widget<AdaptiveDialogAction>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result, 2, reason: 'the shown disclosure version is returned');
    });

    testWidgets('2b. in-app prompt: "Not now" returns no consent', (
      tester,
    ) async {
      int? result = -1;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result = await ManagedConsentDialog.show(
                context,
                const ConsentRequest(courseName: 'Spanish 101'),
                api: api(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ManagedConsentPanel.checkboxKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ManagedConsentDialog.notNowKey));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('3. Canvas link step: Continue stays off until ticked', (
      tester,
    ) async {
      await SpaceCodeRepo.setPendingLtiTicket(
        const PendingLtiTicket('dGlja2V0', courseName: 'Spanish 101'),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: LtiLinkPage(api: api()),
        ),
      );
      await tester.pumpAndSettle();

      expectDisclosureUnderCheckbox(tester, 'Spanish 101');
      final cont = find.byKey(LtiLinkPage.continueKey);
      expect(tester.widget<ElevatedButton>(cont).onPressed, isNull);
      await tester.tap(find.byKey(ManagedConsentPanel.checkboxKey));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(cont).onPressed, isNotNull);
      expect(sent.where((r) => r.url.path.endsWith('/lti/link')), isEmpty);
    });
  });

  testWidgets('the checkbox cannot be ticked before the disclosure loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ManagedConsentPanel(
          courseName: 'Spanish 101',
          disclosure: null,
          checked: false,
          onChanged: (_) {},
        ),
      ),
    );
    // Localizations load first; the spinner under the box never settles.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final box = tester.widget<CheckboxListTile>(
      find.byKey(ManagedConsentPanel.checkboxKey),
    );
    expect(box.onChanged, isNull);
  });
}
