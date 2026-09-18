import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Keyboard and screen-reader contract for the activity row (#9154): the row
/// is one Tab stop with the arrow keys moving between its cards
/// (accessibility.instructions.md, "One Tab stop per list"), Enter opens the
/// focused card, and each card announces as one focusable button named by its
/// activity. A course preview's cards open nothing, so they are not stops.
void main() {
  setUp(() {
    // The card's image widget reads Environment.cmsApi before deciding whether
    // to fetch, so dotenv has to be loaded even with no real image in play.
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  ActivityPlanModel plan(String id, String title) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: title,
    learningObjective: 'Can introduce self.',
    instructions: '',
    vocab: const [],
    activityId: id,
    // A host outside AppConfig's image allowlist, so the card renders its
    // no-image fallback instead of reaching for the network.
    imageURL: 'https://images.test.invalid/$id.png',
  );

  final activities = [
    QuestActivity(activityId: 'a', plan: plan('a', 'Alpha')),
    QuestActivity(activityId: 'b', plan: plan('b', 'Beta')),
    QuestActivity(activityId: 'c', plan: plan('c', 'Gamma')),
  ];

  late FocusNode before;
  late FocusNode after;
  late List<String> opened;

  setUp(() {
    before = FocusNode(debugLabel: 'before');
    after = FocusNode(debugLabel: 'after');
    opened = [];
  });
  tearDown(() {
    before.dispose();
    after.dispose();
  });

  // A control either side of the row, so leaving it is observable.
  Widget wrap({bool interactive = true}) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 900.0,
        child: Column(
          children: [
            TextButton(
              focusNode: before,
              onPressed: () {},
              child: const Text('See all'),
            ),
            ActivityCarousel(
              activities: activities,
              onTap: (a) => opened.add(a.activityId),
              userStarsByActivity: (_) => 0,
              hasCompletedActivity: (_) => false,
              liveStateByActivity: (_) => (
                state: null,
                openSessions: 0,
                participants: const <String>[],
                openSlots: 0,
              ),
              availableParticipants: 10,
              spacing: 0.0,
              cardWidth: 160.0,
              cardHeight: 220.0,
              interactive: interactive,
            ),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('Next section'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  testWidgets('the row is one Tab stop, arrows move inside it, Enter opens', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    before.requestFocus();
    await tester.pump();

    // Tab enters the row on its first card.
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['a']);

    // Right moves to the next card; Left comes back.
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['a', 'b']);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['a', 'b', 'a']);

    // Tab leaves the row in one press, past the cards not yet visited.
    await press(tester, LogicalKeyboardKey.tab);
    expect(after.hasPrimaryFocus, isTrue);

    // Shift+Tab returns to the card last focused, not the first or last.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await press(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, ['a', 'b', 'a', 'a']);
  });

  testWidgets(
    'a card announces as one focusable button named by its activity',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      for (final title in ['Alpha', 'Beta', 'Gamma']) {
        final nodes = tester.semantics
            .simulatedAccessibilityTraversal()
            .where((n) => n.getSemanticsData().label.contains(title))
            .toList();
        expect(nodes, hasLength(1), reason: '$title is one node');
        final data = nodes.single.getSemanticsData();
        expect(nodes.single.flagsCollection.isButton, isTrue, reason: title);
        expect(
          data.hasAction(SemanticsAction.focus),
          isTrue,
          reason: '$title takes keyboard focus',
        );
        expect(
          data.hasAction(SemanticsAction.tap),
          isTrue,
          reason: '$title opens from a screen reader',
        );
      }
      handle.dispose();
    },
  );

  testWidgets('a preview row is not a Tab stop', (tester) async {
    await tester.pumpWidget(wrap(interactive: false));
    await tester.pumpAndSettle();
    before.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.tab);
    expect(after.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(opened, isEmpty);
  });
}
