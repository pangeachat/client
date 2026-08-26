import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';
import 'package:fluffychat/widgets/avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment, which reads GetStorage and dotenv
    // -- neither stood up by the widget-test harness on its own, so a bare
    // Avatar throws before it ever gets to the "is this a bot" question this
    // widget never asks. Same fixture as incoming_call_banner_test.dart.
    final tempDir = await Directory.systemTemp.createTemp('turn_timeline');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
  });

  CallTurn turn({
    String senderId = '@a:server',
    String name = 'Alice',
    bool isMe = false,
    Duration at = Duration.zero,
    String text = 'hello',
  }) =>
      CallTurn(senderId: senderId, name: name, isMe: isMe, at: at, text: text);

  Future<void> pump(WidgetTester tester, List<CallTurn> turns) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: TurnTimeline(turns: turns)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty transcript renders nothing, and does not throw', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(Avatar), findsNothing);
  });

  testWidgets('an avatar draws once per speaker change, not once per turn', (
    tester,
  ) async {
    await pump(tester, [
      turn(senderId: '@a:server', text: 'first from a'),
      turn(senderId: '@a:server', text: 'second from a'),
      turn(senderId: '@a:server', text: 'third from a'),
      turn(senderId: '@b:server', name: 'Bob', text: 'a reply from b'),
    ]);

    // Three consecutive turns from @a share one header; @b's turn opens a
    // second. Four turns, two speaker changes, two avatars -- never four.
    expect(find.byType(Avatar), findsNWidgets(2));
  });

  testWidgets(
    'consecutive turns from one speaker indent under the header, not the avatar',
    (tester) async {
      await pump(tester, [
        turn(senderId: '@a:server', text: 'header turn'),
        turn(senderId: '@a:server', text: 'continuation turn'),
      ]);

      final headerLeft = tester.getTopLeft(find.text('header turn')).dx;
      final continuationLeft = tester
          .getTopLeft(find.text('continuation turn'))
          .dx;

      // The continuation turn draws no avatar of its own, but the space is
      // reserved, so its text lands at the exact x-coordinate the header
      // turn's text did -- that alignment IS the indent.
      expect(continuationLeft, headerLeft);
      expect(headerLeft, greaterThan(0));
    },
  );

  testWidgets('a time renders as m:ss, not seconds or a duration string', (
    tester,
  ) async {
    await pump(tester, [
      turn(at: const Duration(seconds: 8), text: 'short call'),
      turn(
        senderId: '@b:server',
        name: 'Bob',
        at: const Duration(minutes: 1, seconds: 2),
        text: 'later reply',
      ),
    ]);

    expect(find.text('0:08'), findsOneWidget);
    expect(find.text('1:02'), findsOneWidget);
  });

  testWidgets('own turns are tinted; the other speaker\'s are not', (
    tester,
  ) async {
    await pump(tester, [
      turn(senderId: '@me:server', isMe: true, text: 'my words'),
      turn(senderId: '@a:server', name: 'Alice', text: 'their words'),
    ]);

    final mine = find.ancestor(
      of: find.text('my words'),
      matching: find.byType(Container),
    );
    final theirs = find.ancestor(
      of: find.text('their words'),
      matching: find.byType(Container),
    );

    expect(mine, findsOneWidget);
    expect(theirs, findsNothing);

    final decoration = tester.widget<Container>(mine).decoration;
    expect(decoration, isA<BoxDecoration>());
    final color = (decoration as BoxDecoration).color!;
    // withAlpha(20): fully opaque would be a filled chip, and this app
    // reserves that weight of colour for gold -- achievement, not a record.
    expect(color.a, closeTo(20 / 255, 0.01));
  });

  testWidgets('"You" comes from L10n, never the caller-supplied name', (
    tester,
  ) async {
    await pump(tester, [
      turn(senderId: '@me:server', name: 'Alice', isMe: true, text: 'hi'),
    ]);

    expect(find.text('You'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });
}
