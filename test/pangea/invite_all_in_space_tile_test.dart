import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/invite_all_in_space_tile.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// #7784 — the invite-all row used to be a ListTile, whose trailing widget keeps
/// its intrinsic width and so rode over the leading avatar. A long translation
/// of "Invite all in this course" on a narrow screen overlapped the course
/// avatar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const germanLabel = 'Alle in diesem Kurs einladen';

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment → Environment.botName, which needs
    // GetStorage (path_provider-backed) and dotenv to be readable.
    final tempDir = await Directory.systemTemp.createTemp('invite_all_tile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(mergeWith: {'BOT_NAME': 'pangeabot'});
  });

  /// German throughout: `inviteAllInSpace` is long there, which is the
  /// condition that used to overlap the avatar. One locale per isolate — a
  /// second locale's delegates load asynchronously and leave the Localizations
  /// subtree empty for the frames a widget test pumps.
  Future<void> pumpTile(WidgetTester tester, {required double width}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: InviteAllInSpaceTile(
                avatar: null,
                displayname: 'Deutsch für Anfängerinnen und Anfänger',
                memberCount: 12,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A RenderFlex overflow fails the test on its own; this catches the ListTile
  /// failure mode, where the button was painted over the avatar with no
  /// overflow reported at all.
  void expectNoOverlap(WidgetTester tester) {
    final avatar = tester.getRect(find.byType(Avatar));
    final button = tester.getRect(find.byType(TextButton));
    expect(button.left, greaterThanOrEqualTo(avatar.right));
  }

  testWidgets('invite-all label clears the course avatar on a narrow screen', (
    tester,
  ) async {
    await pumpTile(tester, width: 320);

    expect(find.text(germanLabel), findsOneWidget);
    expectNoOverlap(tester);
  });

  testWidgets('invite-all label clears the course avatar on a wide screen', (
    tester,
  ) async {
    await pumpTile(tester, width: 800);
    expectNoOverlap(tester);
  });

  testWidgets(
    'a long label wraps instead of pushing past its share of the row',
    (tester) async {
      await pumpTile(tester, width: 800);
      final wideLabel = tester.getRect(find.text(germanLabel));

      await pumpTile(tester, width: 320);
      final narrowLabel = tester.getRect(find.text(germanLabel));

      expect(narrowLabel.width, lessThan(wideLabel.width));
      expect(narrowLabel.height, greaterThan(wideLabel.height));
    },
  );
}
