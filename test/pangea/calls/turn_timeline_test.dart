import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  // Unique per call by default -- most of the tests below build several
  // turns from one sender, and a shared literal here would make every one of
  // those fixtures violate the very uniqueness `CallTurn.identityKey` exists
  // to promise, for a reason that has nothing to do with what any of them
  // test.
  var nextIdentity = 0;

  CallTurn turn({
    String senderId = '@a:server',
    String name = 'Alice',
    bool isMe = false,
    Duration at = Duration.zero,
    TurnTime time = TurnTime.exact,
    String text = 'hello',
    int? audioStartMs,
  }) => CallTurn(
    senderId: senderId,
    name: name,
    isMe: isMe,
    at: at,
    time: time,
    text: text,
    audioStartMs: audioStartMs,
    identityKey: 'turn-${nextIdentity++}',
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
        identityKey: 'turn-${nextIdentity++}',
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

  // Karaoke: highlight + auto-scroll + tap-to-seek (spec section 4). Every
  // test below drives TurnTimeline with plain ValueNotifier fakes, never a
  // real CallPlaybackController -- this widget's contract is with the
  // ValueListenable/callback SHAPE, not with the controller that will
  // eventually supply them (that wiring is a separate agent's work).
  group('karaoke', () {
    BoxDecoration decorationOf(WidgetTester tester, String text) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(text),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    Future<void> pumpKaraoke(
      WidgetTester tester,
      List<CallTurn> turns, {
      ValueListenable<int?>? activeIndex,
      ValueListenable<bool>? isPlaying,
      void Function(int)? onSeekTurn,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: TurnTimeline(
              turns: turns,
              activeIndex: activeIndex,
              isPlaying: isPlaying,
              onSeekTurn: onSeekTurn,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// A bounded, scrollable host -- TurnTimeline is a non-scrolling Column
    /// meant to live inside a caller's own scrollable
    /// (`transcript_view.dart` today), so exercising `ensureVisible` and a
    /// manual scroll both need a real ancestor `Scrollable` with a real
    /// viewport smaller than the content.
    Future<ScrollController> pumpKaraokeScrollable(
      WidgetTester tester,
      List<CallTurn> turns, {
      required ValueListenable<int?> activeIndex,
      required ValueListenable<bool> isPlaying,
      void Function(int)? onSeekTurn,
    }) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: SingleChildScrollView(
                controller: scrollController,
                child: TurnTimeline(
                  turns: turns,
                  activeIndex: activeIndex,
                  isPlaying: isPlaying,
                  onSeekTurn: onSeekTurn,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return scrollController;
    }

    List<CallTurn> manyTurns() => [
      for (var i = 0; i < 20; i++)
        turn(
          senderId: i.isEven ? '@a:server' : '@b:server',
          name: i.isEven ? 'Alice' : 'Bob',
          text: 'turn number $i',
          at: Duration(seconds: i * 5),
          audioStartMs: i * 5000,
        ),
    ];

    testWidgets(
      'with every karaoke param left null, a turn draws no accent border and '
      'offers no seek affordance -- the hard invariant this feature must '
      'never break',
      (tester) async {
        await pump(tester, [
          turn(
            senderId: '@me:server',
            isMe: true,
            text: 'my words',
            at: const Duration(seconds: 7),
          ),
        ]);

        expect(
          decorationOf(tester, 'my words').border,
          isNull,
          reason: 'activeIndex is null -- nothing is ever active',
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false),
          ),
          findsNothing,
          reason: 'onSeekTurn is null -- no seek target exists at all',
        );
        expect(
          find.byWidgetPredicate((w) => w is Padding && w.key is GlobalKey),
          findsNothing,
          reason:
              'no GlobalKey machinery is attached at all while activeIndex '
              'is null -- not merely unused',
        );
      },
    );

    testWidgets(
      'the active turn shows the accent bar and a tint; the highlight moves '
      'when activeIndex changes',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(0);
        addTearDown(activeIndex.dispose);

        await pumpKaraoke(tester, [
          turn(text: 'first', at: Duration.zero),
          turn(
            senderId: '@b:server',
            name: 'Bob',
            text: 'second',
            at: const Duration(seconds: 5),
          ),
        ], activeIndex: activeIndex);

        final scheme = Theme.of(tester.element(find.text('first'))).colorScheme;

        expect(
          (decorationOf(tester, 'first').border! as BorderDirectional)
              .start
              .color,
          scheme.primary,
          reason: 'turn 0 is active',
        );
        expect(
          decorationOf(tester, 'second').border,
          isNull,
          reason: 'turn 1 is not active',
        );
        expect(
          decorationOf(tester, 'second').color,
          scheme.surfaceContainerHigh,
          reason: 'an inactive peer turn keeps its exact base fill',
        );
        expect(
          decorationOf(tester, 'first').color,
          isNot(scheme.surfaceContainerHigh),
          reason: 'the active turn is tinted away from its base fill',
        );

        activeIndex.value = 1;
        await tester.pump();

        expect(
          decorationOf(tester, 'first').border,
          isNull,
          reason: 'no longer active',
        );
        expect(
          (decorationOf(tester, 'second').border! as BorderDirectional)
              .start
              .color,
          scheme.primary,
          reason: 'the highlight followed activeIndex',
        );
      },
    );

    testWidgets(
      'auto-scroll brings an off-screen active turn into view while playing',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        expect(scrollController.offset, 0);
        final startY = tester.getTopLeft(find.text('turn number 18')).dy;
        expect(
          startY < 0 || startY >= 300,
          isTrue,
          reason: 'turn 18 starts off-screen in a 300px viewport',
        );

        activeIndex.value = 18;
        await tester.pumpAndSettle();

        expect(
          scrollController.offset,
          greaterThan(0),
          reason: 'ensureVisible moved the parent scrollable while playing',
        );
        final endY = tester.getTopLeft(find.text('turn number 18')).dy;
        expect(endY >= 0 && endY < 300, isTrue);

        // A SECOND consecutive auto-scroll must ALSO fire -- guards the
        // exact self-suspend risk `_autoScrollInFlight` exists to prevent:
        // a naive listener on the ancestor position would see this widget's
        // OWN first `ensureVisible` call move `pixels` and misread that as
        // "the reader scrolled", permanently suspending every auto-scroll
        // after the first one, silently.
        // Mutation: drop the `if (_autoScrollInFlight) return;` guard in
        // `_onAncestorScrollChanged` -> the assertion below goes RED.
        final offsetAfterFirst = scrollController.offset;
        activeIndex.value = 0;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          lessThan(offsetAfterFirst),
          reason:
              'a second auto-scroll (back to the top) must also fire -- the '
              'first one must not have self-suspended it',
        );
      },
    );

    testWidgets(
      // Mutation: remove the
      // `if (notificationGeneration != _activeIndexNotificationGeneration)
      // return;` supersede check in `_onActiveIndexChanged`'s deferred
      // callback -> the assertion below goes RED (the view scrolls to a
      // turn that is no longer active by the time the callback runs).
      //
      // Deliberately an `i -> null` transition, not `i -> j`: a SECOND
      // `_autoScrollTo` call would itself dispose the first one's scroll
      // regardless of this check (each call supersedes the last), so an
      // `i -> j` sequence cannot tell the fix apart from its absence -- only
      // `i -> null` leaves nothing else to cancel the stale callback. This
      // test does NOT cover the OTHER reason the check is generation-based
      // rather than value-based (an `i -> j -> i` sequence, where a plain
      // value compare lets the FIRST `i`'s callback through a second,
      // redundant time) -- that case does not corrupt anything a scroll
      // assertion here could observe (both the real and the reverted
      // mechanism land on the same final target), so it is covered by
      // reasoning and the production doc comment, not a dedicated test;
      // see `_onActiveIndexChanged`'s own comment for the full argument.
      'a superseded activeIndex notification does not auto-scroll once a '
      'later one has already cleared it',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        // Both changes land in the SAME tick, before the first's deferred
        // `addPostFrameCallback` has had a chance to run. The second
        // (`null`) is itself a no-op for scheduling purposes (`_onActive
        // IndexChanged` returns early on a null `newIndex`), so nothing
        // else exists to dispose the first's now-stale scroll request.
        activeIndex.value = 18;
        activeIndex.value = null;
        await tester.pumpAndSettle();

        expect(
          scrollController.offset,
          0,
          reason:
              'activeIndex is null by the time the deferred callback for the '
              'earlier value (18) runs -- it must not scroll anywhere',
        );
      },
    );

    testWidgets(
      // Mutation: in `_autoScrollTo`, replace the final
      // `_autoScrollInFlight = _observedPosition?.isScrollingNotifier.value
      // ?? false;` read with an unconditional `_autoScrollInFlight = true;`
      // (reintroducing a stale-completion-style bug: the flag would stay
      // true even after everything has genuinely gone idle) -- the
      // assertion below stays green either way here, since it checks the
      // OPPOSITE failure mode (a real scroll wrongly cleared mid-flight);
      // see the dedicated no-op test below for the mutation that targets
      // the direct-read mechanism specifically. This test's own value is
      // pinning that a full 300ms supersede-and-settle cycle behaves
      // correctly at all.
      'a second auto-scroll superseding a still-in-flight first one does '
      'not get misread as a manual scroll once it settles',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        // Start a (non-reduced-motion, 300ms) scroll to 18, then supersede
        // it with one to 5 WHILE it is still animating -- `beginActivity`
        // disposes the first `DrivenScrollActivity` mid-flight, completing
        // ITS future (a STALE completion the live scroll must not be
        // affected by).
        activeIndex.value = 18;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        activeIndex.value = 5;
        await tester.pump();

        // Let the superseding scroll run all the way to completion, with no
        // user interaction at all in between.
        await tester.pumpAndSettle();

        // If the superseded scroll's stale completion cleared the flag
        // while the live one was still ticking, the live one's OWN later
        // ticks would have been misread as a manual scroll, suspending
        // auto-scroll. Prove that did not happen: a further index change,
        // still playing, must still auto-scroll.
        final offsetAfterSettling = scrollController.offset;
        activeIndex.value = 10;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          isNot(offsetAfterSettling),
          reason:
              'a THIRD auto-scroll must still fire -- the second one '
              "settling must not have self-suspended it via the first one's "
              'stale completion',
        );
      },
    );

    testWidgets(
      // Mutation: replace `_autoScrollTo`'s final
      // `_autoScrollInFlight = _observedPosition?.isScrollingNotifier.value
      // ?? false;` with per-call generation bookkeeping again (a counter
      // bumped every call, cleared only by the LATEST call's own
      // `.whenComplete`) -> this goes RED, because the SECOND (no-op) call
      // is trivially "the latest" and its own (immediately-resolved)
      // future would clear the flag regardless of the FIRST call's
      // activity continuing to run underneath -- exactly the bug that
      // reasoning was found to have.
      'a no-op auto-scroll call (its target already visible against a '
      'still-running earlier one) does not stop that earlier one from '
      'being tracked',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        // Start a real (300ms) scroll to a far turn, then -- almost
        // immediately, while it has barely moved -- point at a turn that
        // is STILL fully visible given how little the first scroll has
        // progressed. `ensureVisible` for that second call finds nothing
        // to do: it touches no activity at all, so `isScrollingNotifier`
        // never changes because of it, and the first scroll's own
        // activity keeps running, untouched, underneath.
        activeIndex.value = 18;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        activeIndex.value = 1;
        await tester.pump();

        // Let the ORIGINAL (still-running) scroll finish on its own.
        await tester.pumpAndSettle();
        final offsetAfterSettling = scrollController.offset;
        expect(offsetAfterSettling, greaterThan(0));

        // A further auto-scroll must still fire -- if the no-op call had
        // wrongly cleared `_autoScrollInFlight` while the ORIGINAL scroll
        // was still driving, that scroll's own later ticks would have
        // been misread as manual, suspending auto-scroll before this
        // point.
        activeIndex.value = 10;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          isNot(offsetAfterSettling),
          reason:
              'a later auto-scroll must still fire -- the no-op call for '
              "turn 1 must not have cleared the flag while turn 18's "
              'scroll was still the one actually running',
        );
      },
    );

    testWidgets(
      // Mutation: in `_syncScrollObserver`, drop the
      // `_autoScrollInFlight = false;` reset on an observed-position swap
      // -> the assertion below goes RED (the manual drag after karaoke
      // re-enables gets ignored, since the flag is still stuck `true` from
      // before karaoke was disabled).
      'toggling karaoke off and back on mid-scroll does not leave '
      '_autoScrollInFlight stuck true forever',
      (tester) async {
        final firstActiveIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(firstActiveIndex.dispose);
        addTearDown(isPlaying.dispose);

        final turns = manyTurns();
        final scrollController = await pumpKaraokeScrollable(
          tester,
          turns,
          activeIndex: firstActiveIndex,
          isPlaying: isPlaying,
        );

        // Start a real (300ms) scroll, then -- while it is still mid-
        // flight -- disable karaoke entirely (a null `activeIndex`, not
        // merely a notified value), which detaches from this scrollable's
        // position before that in-flight scroll's own eventual idle
        // transition would have cleared the flag.
        firstActiveIndex.value = 18;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        Widget buildWith(ValueListenable<int?>? activeIndex) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: SingleChildScrollView(
                controller: scrollController,
                child: TurnTimeline(
                  turns: turns,
                  activeIndex: activeIndex,
                  isPlaying: isPlaying,
                ),
              ),
            ),
          ),
        );

        await tester.pumpWidget(buildWith(null));
        await tester.pumpAndSettle();

        // Re-enable karaoke with a FRESH activeIndex, sitting on null (no
        // turn active yet) -- re-attaching to the very same underlying
        // scrollable.
        final secondActiveIndex = ValueNotifier<int?>(null);
        addTearDown(secondActiveIndex.dispose);
        await tester.pumpWidget(buildWith(secondActiveIndex));
        await tester.pumpAndSettle();

        // The original scroll (toward turn 18) kept running on the real
        // underlying position throughout -- detaching this widget's OWN
        // listeners never stops it -- so `pumpAndSettle` above already let
        // it settle at turn 18's position, near the bottom of the list.
        final offsetBeforeDrag = scrollController.offset;
        expect(offsetBeforeDrag, greaterThan(0));

        // A manual drag BACK toward the top now must be seen as a manual
        // scroll -- proven via a further activeIndex change, still
        // playing, which must NOT auto-scroll if suspend correctly
        // engaged. Dragged upward (a positive offset, decreasing
        // `scrollController.offset`) specifically so the drag itself
        // produces an unambiguous, checked position change, rather than
        // one that could be a no-op if it happened to push further against
        // an already-maxed-out extent.
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, 200),
        );
        await tester.pumpAndSettle();
        final offsetAfterDrag = scrollController.offset;
        expect(
          offsetAfterDrag,
          lessThan(offsetBeforeDrag),
          reason:
              'the drag itself must have moved the view -- otherwise '
              'the assertion below would not mean anything',
        );

        secondActiveIndex.value = 5;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          offsetAfterDrag,
          reason:
              'the manual drag must have suspended auto-scroll -- it would '
              'not have if _autoScrollInFlight was still stuck true from '
              'before karaoke was toggled off',
        );
      },
    );

    testWidgets(
      // Mutation: remove the `_onAncestorScrollingChanged` listener (and
      // its attach/detach in `_syncScrollObserver`/`dispose`) -> the
      // assertion below goes RED, because `ScrollPosition.pointerScroll`
      // disposes the in-flight `DrivenScrollActivity` and moves `pixels` in
      // ONE synchronous call, before a Future's `.whenComplete` (always
      // microtask-deferred) gets a turn to clear `_autoScrollInFlight`
      // itself.
      'a single mouse-wheel tick that interrupts an in-flight auto-scroll '
      'still suspends it',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        // Start a real (300ms, non-reduced-motion) auto-scroll and
        // interrupt it PARTWAY with a single wheel tick -- a genuine
        // `PointerScrollEvent`, not a drag (`ScrollPosition.pointerScroll`,
        // not `.applyUserOffset`), since it is specifically that method's
        // synchronous dispose-then-move sequence this fix targets.
        activeIndex.value = 18;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(const Offset(200, 150));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
        await tester.pumpAndSettle();
        final offsetAfterWheel = scrollController.offset;

        // Playback moves on. If the wheel tick failed to suspend, this
        // would auto-scroll further; it must not.
        activeIndex.value = 5;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          offsetAfterWheel,
          reason:
              'a single interrupting wheel tick must suspend auto-scroll '
              'just like a drag does',
        );
      },
    );

    testWidgets(
      // Mutation: drop the `widget.isPlaying?.value ?? false` gate in
      // `_onActiveIndexChanged` -> this goes RED (the view would move).
      'auto-scroll never fires while not playing, even though the highlight '
      'still moves',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(false);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        activeIndex.value = 18;
        await tester.pumpAndSettle();

        expect(
          scrollController.offset,
          0,
          reason: 'not playing -- the highlight moves but the view must not',
        );
        final scheme = Theme.of(
          tester.element(find.text('turn number 0')),
        ).colorScheme;
        expect(
          (decorationOf(tester, 'turn number 18').border! as BorderDirectional)
              .start
              .color,
          scheme.primary,
          reason:
              'isPlaying gates auto-scroll ONLY -- the highlight is independent',
        );
      },
    );

    testWidgets(
      // Mutation: drop the `_autoScrollSuspended` check in `_autoScrollTo`
      // -> the "must not be overridden" assertion below goes RED.
      'a manual scroll suspends auto-scroll until the next seek tap resumes '
      'it',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);
        final seeks = <int>[];

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
          onSeekTurn: seeks.add,
        );

        // The reader takes the wheel.
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
        final offsetAfterDrag = scrollController.offset;
        expect(offsetAfterDrag, greaterThan(0));

        // Playback keeps moving. Auto-scroll must not fight the reader.
        activeIndex.value = 19;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          offsetAfterDrag,
          reason: 'suspended: a manual scroll must not be overridden',
        );

        // A seek tap resumes auto-follow. `ensureVisible` here is the TEST
        // reaching its tap target -- a separate action from the auto-scroll
        // under test, and (like the widget's own auto-scroll) a driven
        // scroll that must not itself re-trip the suspend flag.
        await tester.ensureVisible(find.text('0:00'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('0:00'));
        await tester.pump();
        expect(seeks, [0]);

        activeIndex.value = 10;
        await tester.pumpAndSettle();
        final pos = tester.getTopLeft(find.text('turn number 10')).dy;
        expect(
          pos >= 0 && pos < 300,
          isTrue,
          reason: 'resumed: the next activeIndex change auto-scrolls again',
        );
      },
    );

    testWidgets(
      // Mutation: wire the whole bubble (not just the time) to onSeekTurn ->
      // the "never a seek target" assertion below goes RED.
      "tapping a turn's time seeks; tapping its transcript text does not",
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        addTearDown(activeIndex.dispose);
        final seeks = <int>[];

        await pumpKaraoke(
          tester,
          [
            turn(
              text: 'first',
              at: const Duration(seconds: 3),
              audioStartMs: 3000,
            ),
            turn(
              senderId: '@b:server',
              name: 'Bob',
              text: 'second reply',
              at: const Duration(seconds: 9),
              audioStartMs: 9000,
            ),
          ],
          activeIndex: activeIndex,
          onSeekTurn: seeks.add,
        );

        // Structural, not a simulated tap: SelectableText claims a tap on
        // its own glyphs via its own internal gesture handling regardless of
        // what any ancestor GestureDetector does, so tapping the rendered
        // text and checking `seeks` would stay vacuously empty even if the
        // whole bubble really were wired to seek. What actually proves the
        // text is never a seek target is that nothing ties it to one in the
        // tree at all.
        //
        // Pinned first, separately: the ancestor check below is vacuously
        // true if the text itself never rendered at all.
        expect(find.text('second reply'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('second reply'),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason: 'the transcript text must not sit inside any seek tap target',
        );

        await tester.tap(find.text('0:09'));
        await tester.pump();
        expect(seeks, [1], reason: "the second turn's time seeks to index 1");
      },
    );

    testWidgets(
      'a turn with no audioStartMs offers no seek affordance even though '
      'karaoke is otherwise on',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        addTearDown(activeIndex.dispose);

        await pumpKaraoke(
          tester,
          [turn(text: 'first', at: const Duration(seconds: 3))],
          activeIndex: activeIndex,
          onSeekTurn: (_) {},
        );

        // The stamp itself must still be there, plainly -- this is not "no
        // seek affordance because nothing was printed at all", and not "a
        // pointer-tappable stamp with no button semantics" either (a real
        // affordance that merely forgot the a11y wiring would ALSO make the
        // check below pass).
        expect(find.text('0:03'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('0:03'),
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      // Mutation: announce `stamp` (the printed label) instead of the
      // audioStart-derived one -> both assertions below go RED.
      'the seek label announces the recording-relative start, not the '
      'printed label',
      (tester) async {
        // Printed "by 0:07" (6001ms rounds UP), but the audio actually
        // starts at 0:03 -- the two must differ for this test to mean
        // anything (spec section 4's own worked example).
        final approximateTurn = CallTurn(
          senderId: '@a:server',
          name: 'Alice',
          isMe: false,
          at: const Duration(milliseconds: 6001),
          time: TurnTime.atOrBefore,
          text: 'hola',
          audioStartMs: 3000,
          identityKey: 'seek-label-turn',
        );
        final activeIndex = ValueNotifier<int?>(null);
        addTearDown(activeIndex.dispose);

        await pumpKaraoke(
          tester,
          [approximateTurn],
          activeIndex: activeIndex,
          onSeekTurn: (_) {},
        );

        expect(find.text('by 0:07'), findsOneWidget);

        final semantics = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false),
          ),
        );
        expect(semantics.properties.label, contains('0:03'));
        expect(semantics.properties.label, isNot(contains('0:07')));
      },
    );

    testWidgets(
      // Mutation: ignore disableAnimations and always animate for 300ms ->
      // `earlyOffset` would sit well short of `finalOffset` and the equality
      // assertion below goes RED.
      'reduced motion jumps to the active turn instead of animating there',
      (tester) async {
        final dispatcher = tester.binding.platformDispatcher;
        dispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        activeIndex.value = 18;
        await tester.pump(const Duration(milliseconds: 16));
        final earlyOffset = scrollController.offset;
        await tester.pumpAndSettle();
        final finalOffset = scrollController.offset;

        expect(finalOffset, greaterThan(0), reason: 'a scroll did happen');
        expect(
          earlyOffset,
          finalOffset,
          reason:
              'Duration.zero means the jump is already done after one short '
              'tick, not still animating toward it 284ms later',
        );
      },
    );

    testWidgets(
      // Mutation: in `_onAncestorScrollChanged`, drop `_startingAutoScroll`
      // from the guard (back to `if (_autoScrollInFlight) return;` alone)
      // -> the assertion below goes RED. Under reduced motion,
      // `Scrollable.ensureVisible` calls `ScrollPosition.ensureVisible`,
      // which for `Duration.zero` calls `jumpTo` directly (never
      // `animateTo`) -- `jumpTo` disposes whatever was running and moves
      // `pixels` SYNCHRONOUSLY, all before `_autoScrollTo` ever reaches its
      // own closing `isScrollingNotifier` read. On the very first call,
      // `_autoScrollInFlight` is still false at that point, so the jump's
      // own `forcePixels` would reach `_onAncestorScrollChanged` with
      // NEITHER guard field yet true -- misreading its own jump as a
      // manual scroll and suspending itself before a SECOND auto-scroll
      // ever gets a chance to run.
      'reduced motion does not suspend auto-scroll on its own very first '
      'jump',
      (tester) async {
        final dispatcher = tester.binding.platformDispatcher;
        dispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

        final activeIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(activeIndex.dispose);
        addTearDown(isPlaying.dispose);

        final scrollController = await pumpKaraokeScrollable(
          tester,
          manyTurns(),
          activeIndex: activeIndex,
          isPlaying: isPlaying,
        );

        // The FIRST auto-scroll in this widget's whole lifetime -- the
        // exact case where `_autoScrollInFlight` is still at its initial
        // `false` throughout the jump.
        activeIndex.value = 18;
        await tester.pumpAndSettle();
        final offsetAfterFirst = scrollController.offset;
        expect(offsetAfterFirst, greaterThan(0));

        // A SECOND auto-scroll, with no user interaction at all in
        // between, must also fire.
        activeIndex.value = 3;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          isNot(offsetAfterFirst),
          reason:
              'a second reduced-motion auto-scroll must still fire -- the '
              "first one's own jump must not have suspended it",
        );
      },
    );

    testWidgets(
      "a turn's GlobalKey survives a rebuild that shifts its index, because "
      'it is keyed by identity, not position',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(null);
        addTearDown(activeIndex.dispose);
        final stable = turn(
          text: 'stable turn',
          at: const Duration(seconds: 10),
        );

        GlobalKey keyOf(String text) =>
            tester
                    .widget<Padding>(
                      find
                          .ancestor(
                            of: find.text(text),
                            matching: find.byWidgetPredicate(
                              (w) => w is Padding && w.key is GlobalKey,
                            ),
                          )
                          .first,
                    )
                    .key!
                as GlobalKey;

        await pumpKaraoke(tester, [stable], activeIndex: activeIndex);
        final before = keyOf('stable turn');

        // A DIFFERENT `CallTurn` object, not `stable` itself, but built
        // with `stable`'s own `identityKey` -- this is the case that
        // actually distinguishes "keyed by `identityKey`" from "keyed by
        // `CallTurn` object identity" (reusing the literal same object,
        // as an earlier version of this test did, cannot tell the two
        // apart: it would pass either way). Also arrives AHEAD of it in
        // call-time order (e.g. late recording data recomputing windows
        // re-sorts the list), so 'stable turn' shifts from index 0 to
        // index 1 too.
        final stableAgain = CallTurn(
          senderId: stable.senderId,
          name: stable.name,
          isMe: stable.isMe,
          at: stable.at,
          time: stable.time,
          text: stable.text,
          identityKey: stable.identityKey,
        );
        expect(
          identical(stable, stableAgain),
          isFalse,
          reason: 'the fixture itself must be a genuinely different object',
        );
        await pumpKaraoke(tester, [
          turn(
            senderId: '@z:server',
            name: 'Zack',
            text: 'new earlier turn',
            at: const Duration(seconds: 1),
          ),
          stableAgain,
        ], activeIndex: activeIndex);

        final after = keyOf('stable turn');
        expect(
          identical(before, after),
          isTrue,
          reason:
              'the same identityKey must keep the same GlobalKey object even '
              'when it is a different CallTurn object at a different index',
        );
      },
    );

    testWidgets(
      // Mutation: drop `onTap: seek` from the outer `Semantics` (leaving
      // only the descendant `GestureDetector`'s own auto-generated action)
      // -> this goes RED, because `excludeSemantics: true` drops that
      // descendant's node -- action included -- along with it.
      'the seek Semantics node carries a working tap action, not merely a '
      'label an assistive technology could not act on',
      (tester) async {
        // Disposed explicitly at the end of this test body, NOT via
        // `addTearDown`: `WidgetTester`'s own end-of-test verification (that
        // no `SemanticsHandle` is left open) runs before a `testWidgets`
        // body's `addTearDown` callbacks get their turn, so registering the
        // dispose there fails the test on a handle this body already
        // finished with.
        final handle = tester.ensureSemantics();

        final activeIndex = ValueNotifier<int?>(null);
        addTearDown(activeIndex.dispose);

        await pumpKaraoke(
          tester,
          [
            turn(
              text: 'first',
              at: const Duration(seconds: 3),
              audioStartMs: 3000,
            ),
          ],
          activeIndex: activeIndex,
          onSeekTurn: (_) {},
        );

        // Scoped to THIS turn's own seek label specifically, not "any
        // tappable semantics node anywhere" -- an unrelated tappable node
        // elsewhere in the tree (a button in the app chrome, say) would
        // satisfy a bare `find.semantics.byAction(SemanticsAction.tap)` and
        // prove nothing about this feature.
        expect(
          find.semantics.byPredicate(
            (node) =>
                node.label == 'Play 0:03' &&
                node.getSemanticsData().hasAction(SemanticsAction.tap),
          ),
          findsOneWidget,
          reason:
              'the seek node\'s own label must carry a working tap action, '
              'not merely announce a button an assistive technology cannot '
              'activate',
        );

        handle.dispose();
      },
    );

    testWidgets(
      // Mutation: in `didUpdateWidget`, replace the `_onActiveIndexChanged()` /
      // `_onIsPlayingChanged()` calls with direct `_lastActiveIndex = ...`/
      // `_lastIsPlaying = ...` assignments (silently adopting the swapped
      // listenable's value as the new baseline) -> the auto-scroll
      // assertion below goes RED. The highlight assertion does NOT: `build`
      // reads `widget.activeIndex?.value` directly regardless of this
      // mutation, so the swapped-in turn highlights correctly either way --
      // only the auto-scroll SIDE EFFECT depends on the swap being treated
      // as a real change.
      'swapping the activeIndex/isPlaying listenables for new objects still '
      'active/playing is treated as a real change, not a silent new '
      'baseline',
      (tester) async {
        final firstActiveIndex = ValueNotifier<int?>(null);
        final firstIsPlaying = ValueNotifier<bool>(false);
        addTearDown(firstActiveIndex.dispose);
        addTearDown(firstIsPlaying.dispose);

        final turns = manyTurns();
        final scrollController = await pumpKaraokeScrollable(
          tester,
          turns,
          activeIndex: firstActiveIndex,
          isPlaying: firstIsPlaying,
        );
        expect(scrollController.offset, 0);

        // A brand-new controller (a fresh ValueNotifier pair, as a real
        // `CallPlaybackController` swap would hand this widget) already
        // sitting on turn 18, already playing -- e.g. the merged recording
        // was replaced mid-dialog. Nothing here is a NOTIFICATION on the
        // old objects; it is a wholesale replacement.
        final secondActiveIndex = ValueNotifier<int?>(18);
        final secondIsPlaying = ValueNotifier<bool>(true);
        addTearDown(secondActiveIndex.dispose);
        addTearDown(secondIsPlaying.dispose);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: TurnTimeline(
                    turns: turns,
                    activeIndex: secondActiveIndex,
                    isPlaying: secondIsPlaying,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scheme = Theme.of(
          tester.element(find.text('turn number 0')),
        ).colorScheme;
        expect(
          (decorationOf(tester, 'turn number 18').border! as BorderDirectional)
              .start
              .color,
          scheme.primary,
          reason: 'the swapped-in active turn must actually highlight',
        );
        expect(
          scrollController.offset,
          greaterThan(0),
          reason:
              'an already-active, already-playing swapped-in controller must '
              'still auto-scroll to what it says is active, not be silently '
              'adopted as the new resting baseline',
        );
      },
    );

    testWidgets(
      // Mutation: in `didUpdateWidget`'s `isPlaying` branch specifically,
      // replace `_onIsPlayingChanged()` with a direct
      // `_lastIsPlaying = widget.isPlaying?.value ?? false;` assignment ->
      // the assertion below goes RED. The test above swaps BOTH listenables
      // at once, so it cannot tell this branch's fix apart from
      // `_onActiveIndexChanged`'s deferred callback simply re-reading
      // `isPlaying` fresh regardless (which it does) -- this isolates the
      // `isPlaying` swap alone: `activeIndex` is the SAME object throughout,
      // so only the `isPlaying` branch can be responsible for anything that
      // follows.
      'swapping ONLY the isPlaying listenable for one already true resumes '
      'auto-scroll on the next activeIndex change',
      (tester) async {
        final activeIndex = ValueNotifier<int?>(0);
        final firstIsPlaying = ValueNotifier<bool>(false);
        addTearDown(activeIndex.dispose);
        addTearDown(firstIsPlaying.dispose);

        final turns = manyTurns();
        final scrollController = await pumpKaraokeScrollable(
          tester,
          turns,
          activeIndex: activeIndex,
          isPlaying: firstIsPlaying,
        );

        // A manual scroll suspends auto-scroll (independent of isPlaying).
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
        final offsetAfterDrag = scrollController.offset;
        expect(offsetAfterDrag, greaterThan(0));

        // Swap ONLY isPlaying, to a NEW object already sitting on true.
        // `activeIndex`'s own object never changes across this pump, so
        // `_onActiveIndexChanged`'s swap-path plays no part in anything
        // that follows.
        final secondIsPlaying = ValueNotifier<bool>(true);
        addTearDown(secondIsPlaying.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: TurnTimeline(
                    turns: turns,
                    activeIndex: activeIndex,
                    isPlaying: secondIsPlaying,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Suspension must now be cleared -- proven via an ACTUAL
        // `activeIndex` change on the SAME, never-swapped object, which
        // auto-scrolls only if the isPlaying swap actually resumed it.
        activeIndex.value = 15;
        await tester.pumpAndSettle();
        expect(
          scrollController.offset,
          isNot(offsetAfterDrag),
          reason:
              'swapping in an already-playing isPlaying object must resume '
              "auto-scroll, exactly as a false->true notification on the "
              'SAME object would',
        );
      },
    );

    testWidgets(
      // Mutation: in `_onActiveIndexChanged`, bump
      // `_activeIndexNotificationGeneration` unconditionally at the TOP of
      // the method (before the `changed` check), instead of only after it
      // -> the assertion below goes RED. A same-value swap would then
      // invalidate an earlier, still-relevant pending callback for no
      // reason.
      'a listenable swap that lands on the SAME value as an already-pending '
      'notification does not cancel that notification\'s auto-scroll',
      (tester) async {
        final firstActiveIndex = ValueNotifier<int?>(null);
        final isPlaying = ValueNotifier<bool>(true);
        addTearDown(firstActiveIndex.dispose);
        addTearDown(isPlaying.dispose);

        final turns = manyTurns();
        final scrollController = await pumpKaraokeScrollable(
          tester,
          turns,
          activeIndex: firstActiveIndex,
          isPlaying: isPlaying,
        );

        // A real change schedules a deferred auto-scroll to 18.
        firstActiveIndex.value = 18;

        // BEFORE that callback's frame, the listenable is replaced by a
        // DIFFERENT object already sitting on the SAME value (18) -- e.g. a
        // fresh `CallPlaybackController` constructed moments after the
        // first one resolved the same active turn. This is not a genuine
        // change from the reader's perspective and must not cancel the
        // still-relevant pending scroll.
        final secondActiveIndex = ValueNotifier<int?>(18);
        addTearDown(secondActiveIndex.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: TurnTimeline(
                    turns: turns,
                    activeIndex: secondActiveIndex,
                    isPlaying: isPlaying,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          scrollController.offset,
          greaterThan(0),
          reason:
              'the pending scroll to 18, scheduled before the no-op swap, '
              'must still happen',
        );
      },
    );
  });
}
