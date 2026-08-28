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
    TurnTime time = TurnTime.exact,
    String text = 'hello',
  }) => CallTurn(
    senderId: senderId,
    name: name,
    isMe: isMe,
    at: at,
    time: time,
    text: text,
  );

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

  testWidgets('a pause in one speaker gives the next stretch its own time', (
    tester,
  ) async {
    // A real call rendered three stretches from one speaker at 0:04, 0:17 and
    // 0:19 as a single turn stamped 0:04. Only the opening turn of a run draws
    // a header, and the header is the only thing that prints a time, so the
    // two later stretches silently inherited a moment fifteen seconds before
    // they happened.
    await pump(tester, [
      turn(text: 'first', at: const Duration(seconds: 4)),
      turn(text: 'much later', at: const Duration(seconds: 17)),
    ]);

    expect(find.text('0:04'), findsOneWidget);
    expect(
      find.text('0:17'),
      findsOneWidget,
      reason: 'the later stretch must state when it actually happened',
    );
  });

  testWidgets('an unbroken stretch stays one turn', (tester) async {
    // The other side of the same rule: grouping still has to happen, or every
    // segment of one sentence draws its own name and avatar.
    await pump(tester, [
      turn(text: 'first', at: const Duration(seconds: 4)),
      turn(text: 'right after', at: const Duration(milliseconds: 4300)),
    ]);

    expect(find.byType(Avatar), findsOneWidget);
    expect(find.text('0:04'), findsOneWidget);
  });

  testWidgets('your own avatar is yours, not the initial of "You"', (
    tester,
  ) async {
    // The header prints "You" for your own turns, and that label was being
    // handed to the Avatar as the name. The fallback takes the initial of the
    // name it is given, so every user saw a circle with a "Y" in it.
    await pump(tester, [
      turn(senderId: '@a:server', name: 'Alice', text: 'theirs'),
      turn(senderId: '@me:server', name: 'Satvik', isMe: true, text: 'mine'),
    ]);

    // Only the other speaker draws a face, on their side, as the chat does:
    // you know who you are, and your own name is not repeated over your own
    // words either.
    final avatars = find.byType(Avatar);
    expect(avatars, findsOneWidget, reason: 'the peer, and only the peer');
    expect(
      tester.widget<Avatar>(avatars).name,
      'Alice',
      reason: 'the avatar needs the person, not the word a header prints',
    );
    expect(find.text('Satvik'), findsNothing);
  });

  testWidgets('an avatar picture is used when the speaker has one', (
    tester,
  ) async {
    await pump(tester, [
      CallTurn(
        senderId: '@a:server',
        name: 'Alice',
        isMe: false,
        at: Duration.zero,
        text: 'hello',
        avatarUrl: Uri.parse('mxc://server/abc'),
      ),
    ]);

    final avatar = tester.widget<Avatar>(find.byType(Avatar));
    expect(avatar.mxContent, Uri.parse('mxc://server/abc'));
  });

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

      // The continuation turn draws no avatar of its own, but the gutter is
      // still reserved, so its bubble lands at the exact x-coordinate the
      // header turn's did -- that alignment IS the indent, and without it the
      // second bubble would slide left under the avatar.
      expect(continuationLeft, headerLeft);
      expect(
        headerLeft,
        greaterThan(0),
        reason: 'the peer\'s side leaves room for the avatar',
      );
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

  testWidgets('a bound is printed as a bound, not as a moment', (tester) async {
    await pump(tester, [
      turn(
        text: 'si',
        at: const Duration(seconds: 45),
        time: TurnTime.atOrBefore,
      ),
    ]);

    expect(find.text('by 0:45'), findsOneWidget);
    expect(
      find.text('0:45'),
      findsNothing,
      reason: 'a bare stamp would read as the moment it was said',
    );
  });

  testWidgets('a bound rounds UP, so it is never earlier than the bound', (
    tester,
  ) async {
    // Every other stamp in this app truncates, which is right for a moment and
    // wrong for a ceiling: a turn known to have been said by 45.999s printed
    // as "by 0:45" names a moment it may well have been said after, and the
    // whole value of the label is that a reader may rely on it.
    await pump(tester, [
      turn(
        text: 'si',
        at: const Duration(milliseconds: 45999),
        time: TurnTime.atOrBefore,
      ),
    ]);

    expect(find.text('by 0:46'), findsOneWidget);
  });

  testWidgets('a turn whose device never vouched for its times shows none', (
    tester,
  ) async {
    // The words and the speaker still draw. Only the number we cannot stand
    // behind is left off.
    await pump(tester, [
      turn(
        text: 'hola',
        at: const Duration(seconds: 8),
        time: TurnTime.unstated,
      ),
    ]);

    expect(find.text('hola'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('0:08'), findsNothing);
    expect(find.textContaining('by'), findsNothing);
  });

  testWidgets('a turn never inherits a header of a different kind', (
    tester,
  ) async {
    // Same speaker, same instant, different claims. Only the opening turn of a
    // run draws a header and the header is the only thing that says what is
    // known, so grouping these would file an exact turn under a bound -- or a
    // bound under an exact stamp -- and hand it a claim that does not describe
    // it.
    await pump(tester, [
      turn(
        text: 'bounded',
        at: const Duration(seconds: 45),
        time: TurnTime.atOrBefore,
      ),
      turn(text: 'exact', at: const Duration(seconds: 45)),
    ]);

    expect(find.text('by 0:45'), findsOneWidget);
    expect(find.text('0:45'), findsOneWidget);
    expect(
      find.byType(Avatar),
      findsNWidgets(2),
      reason: 'a change of kind opens a turn, exactly as a speaker change does',
    );
  });

  testWidgets('two turns of the SAME kind at one instant still group', (
    tester,
  ) async {
    // The other side of that rule. Every segment of one chunk whose timings
    // were refused shares a moment AND a kind, and they are meant to read as
    // one block belonging to that chunk.
    await pump(tester, [
      turn(
        text: 'first',
        at: const Duration(seconds: 45),
        time: TurnTime.atOrBefore,
      ),
      turn(
        text: 'second',
        at: const Duration(seconds: 45),
        time: TurnTime.atOrBefore,
      ),
    ]);

    expect(find.byType(Avatar), findsOneWidget);
    expect(find.text('by 0:45'), findsOneWidget);
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

    // Both sides are bubbles now, as in the chat. What separates them is the
    // FILL and the SIDE, not the presence of a bubble at all.
    expect(mine, findsOneWidget);
    expect(theirs, findsOneWidget);

    final mineColor =
        (tester.widget<Container>(mine).decoration! as BoxDecoration).color;
    final theirsColor =
        (tester.widget<Container>(theirs).decoration! as BoxDecoration).color;
    expect(mineColor, isNot(theirsColor));

    // And the sides really are opposite: your words sit right of theirs.
    final myLeft = tester.getTopLeft(find.text('my words')).dx;
    final theirLeft = tester.getTopLeft(find.text('their words')).dx;
    expect(
      myLeft,
      greaterThan(theirLeft),
      reason: 'your turn is right-aligned, the peer\'s is left',
    );
    // Opaque on both sides now. The old layout tinted only your own turn at
    // alpha 20 because the peer's had no bubble to distinguish it from; with
    // two sides and two fills, a wash is no longer what carries the meaning.
    expect(mineColor!.a, 1.0);
    expect(theirsColor!.a, 1.0);
  });

  testWidgets('your own turn is never labelled with a name', (tester) async {
    // A chat does not write your name over your own messages and neither does
    // this. What the test still guards is the older defect underneath: the
    // caller supplies a name for every turn, and for your own turns that name
    // must never reach the screen -- not as "Alice", and not as the localised
    // "You" standing in for it either, now that the side carries the meaning.
    await pump(tester, [
      turn(senderId: '@me:server', name: 'Alice', isMe: true, text: 'hi'),
    ]);

    expect(find.text('Alice'), findsNothing);
    expect(find.text('You'), findsNothing);
    expect(find.text('hi'), findsOneWidget, reason: 'the words still render');
  });

  testWidgets('the other speaker IS named, once per opening turn', (
    tester,
  ) async {
    // The other half of the same rule: their name is the only way to know
    // whose words these are, so it appears -- once, on the turn that opens
    // their run, never repeated down a continuation.
    await pump(tester, [
      turn(senderId: '@a:server', name: 'Alice', text: 'first'),
      turn(
        senderId: '@a:server',
        name: 'Alice',
        text: 'second',
        at: const Duration(milliseconds: 200),
      ),
    ]);

    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets(
    'turns render in call-time order, regardless of the order the caller supplies them in',
    (tester) async {
      // Handed in reverse: third, first, second. Nothing about the wiring
      // that builds this list is trusted to have sorted it -- the widget
      // sorts by CallTurn.at itself, so a caller cannot get this wrong.
      await pump(tester, [
        turn(
          senderId: '@c:server',
          at: const Duration(seconds: 30),
          text: 'third spoken',
        ),
        turn(senderId: '@a:server', text: 'first spoken'),
        turn(
          senderId: '@b:server',
          at: const Duration(seconds: 15),
          text: 'second spoken',
        ),
      ]);

      final firstY = tester.getTopLeft(find.text('first spoken')).dy;
      final secondY = tester.getTopLeft(find.text('second spoken')).dy;
      final thirdY = tester.getTopLeft(find.text('third spoken')).dy;

      expect(firstY, lessThan(secondY));
      expect(secondY, lessThan(thirdY));
    },
  );

  testWidgets(
    'turns that share one instant keep the order they were given, not some '
    "other order the sort happens to land on",
    (tester) async {
      // The backend's own arithmetic can stamp several chunks split from one
      // oversized audio batch with the same position. Equal `at` is a real
      // case, not a malformed one, and the only fact this widget can use to
      // order them correctly is the order it was handed -- which is the
      // order they were spoken.
      const at = Duration(seconds: 5);
      await pump(tester, [
        turn(senderId: '@a:server', at: at, text: 'spoken first of the tie'),
        turn(senderId: '@b:server', at: at, text: 'spoken second of the tie'),
        turn(senderId: '@c:server', at: at, text: 'spoken third of the tie'),
      ]);

      final firstY = tester.getTopLeft(find.text('spoken first of the tie')).dy;
      final secondY = tester
          .getTopLeft(find.text('spoken second of the tie'))
          .dy;
      final thirdY = tester.getTopLeft(find.text('spoken third of the tie')).dy;

      expect(firstY, lessThan(secondY));
      expect(secondY, lessThan(thirdY));
    },
  );

  testWidgets(
    'sizes to its content inside an unbounded scrollable, so what follows it '
    'still renders',
    (tester) async {
      // The real arrangement, not a bounded stand-in: CallTranscriptView
      // places this widget inside a ListView, alongside the absent/silent/
      // unreadable notes that belong below the conversation. A ListView
      // hands each child UNBOUNDED height on purpose, so it can measure the
      // child's own natural size. Every other test in this file pumps
      // TurnTimeline straight into a bounded Scaffold body, where a Column
      // defaulting to MainAxisSize.max is harmless and invisible -- this is
      // the one arrangement that can actually see the defect, because the
      // defect only exists in composition: a Column that tries to fill
      // unbounded height reports back something Flutter treats as
      // effectively infinite, and a ListView lays out lazily, so anything
      // placed after it in the list is pushed past that and never built.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                TurnTimeline(
                  turns: [
                    turn(text: 'first spoken'),
                    turn(
                      senderId: '@b:server',
                      name: 'Bob',
                      at: const Duration(seconds: 5),
                      text: 'second spoken',
                    ),
                  ],
                ),
                const Text('trailing marker'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Found at all -- a widget past an infinitely-tall sibling in a lazy
      // ListView is never built, so this is the assertion that would
      // otherwise fail with "0 widgets found", not a wrong-position error.
      expect(find.text('trailing marker'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('trailing marker')).dy,
        greaterThan(tester.getTopLeft(find.text('second spoken')).dy),
      );
    },
  );
}
