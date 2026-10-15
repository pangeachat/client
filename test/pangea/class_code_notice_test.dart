import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/class_code_dialog.dart';
import 'package:fluffychat/routes/home/class_code_notice.dart';
import 'package:fluffychat/routes/home/login_or_signup_view.dart';

/// #9277: a signed-out visitor who opened a class link is told the code was
/// kept (signup-and-login.instructions.md § Arriving with a class code) — a
/// dialog on arrival at the landing, a card on the signup and login pages —
/// and nothing here uses the code up.
void main() {
  const code = 'k7m2qa9';

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('class_code_notice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('class_storage');
  });

  tearDown(SpaceCodeRepo.clearDestination);

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: home,
  );

  testWidgets('the dialog names the code, and Got it! closes it', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ClassCodeDialog(code: code),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Join your course'), findsOneWidget);
    expect(find.text(code), findsOneWidget);

    await tester.tap(find.text('Got it!'));
    await tester.pumpAndSettle();
    expect(find.byType(ClassCodeDialog), findsNothing);
  });

  testWidgets('the notice names the saved code', (tester) async {
    await tester.pumpWidget(
      app(const Scaffold(body: ClassCodeNotice(code: code))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Course code $code saved'), findsOneWidget);
  });

  group('the landing screen', () {
    // The test font draws every glyph a full em wide, so the landing's
    // button labels overflow at their real size; halve the text to fit.
    Future<void> pumpLanding(WidgetTester tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: const LoginOrSignupView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    // The carousel autoplays on a timer, so tear the screen down before the
    // test ends rather than leave the timer pending.
    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('opens the dialog when a class link is pending, and '
        'dismissing it keeps the code', (tester) async {
      await tester.runAsync(
        () => SpaceCodeRepo.setDestination(PRoutes.joinWithCode(code)),
      );
      await pumpLanding(tester);
      expect(find.byType(ClassCodeDialog), findsOneWidget);

      await tester.tap(find.text('Got it!'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(ClassCodeDialog), findsNothing);
      expect(SpaceCodeRepo.pendingJoinCode, code);
      await unmount(tester);
    });

    testWidgets('opens nothing when no class code is pending', (tester) async {
      await tester.runAsync(
        () => SpaceCodeRepo.setDestination('/?right=settings'),
      );
      await pumpLanding(tester);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.byType(ClassCodeDialog), findsNothing);
      await unmount(tester);
    });
  });
}
