import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/quest_activity_card.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_activity_card.dart';
import 'package:fluffychat/routes/world/world_map_card_dismiss_button.dart';
import 'package:fluffychat/routes/world/world_map_pin_budget.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';
import 'package:fluffychat/widgets/completed_stamp.dart';

/// A large map pin drawn as the activity's own card: the plan's card once it
/// loads, its title until then; a played card wears the completed stamp with
/// its XP on the photo; and it is pointer-only, leaving keyboard access to
/// the pin semantics layer's single roving stop.
void main() {
  // The card's photo reads the CMS origin out of the environment.
  setUpAll(() => dotenv.testLoad(mergeWith: {}));

  const card = QuestActivityCard(
    activityId: 'a1',
    title: 'Ordering at a café',
    l2: 'es',
    coordinates: [0, 0],
    learningObjectiveRefs: [],
  );

  final plan = ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'food',
      mode: 'Roleplay',
      objective: 'order a coffee',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: 'Un café, por favor',
    learningObjective: 'order a coffee',
    instructions: 'i',
    vocab: const [],
    activityId: 'a1',
    roles: const {},
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    ActivityPlanModel? plan,
    bool played = false,
    int xpEarned = 0,
    VoidCallback? onTap,
    VoidCallback? onClose,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: WorldMapActivityCard(
              card: card,
              state: ActivityPinState.available,
              plan: plan,
              participants: const [],
              openSlots: 0,
              played: played,
              xpEarned: xpEarned,
              onTap: onTap ?? () {},
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
    // The photo's placeholder animates, so the card never settles.
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a loaded plan draws the plan\'s activity card', (tester) async {
    await pumpCard(tester, plan: plan);

    expect(find.byType(ActivitySuggestionCard), findsOneWidget);
    expect(find.text('Un café, por favor'), findsOneWidget);

    // Let the photo's failed load run out its retry timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('before the plan loads it draws the card title alone', (
    tester,
  ) async {
    await pumpCard(tester);

    expect(find.byType(ActivitySuggestionCard), findsNothing);
    expect(find.text('Ordering at a café'), findsOneWidget);
  });

  testWidgets('a played card wears the stamp with its XP', (tester) async {
    await pumpCard(tester, plan: plan, played: true, xpEarned: 2330);
    expect(find.byType(CompletedStamp), findsOneWidget);
    expect(find.text('2,330 XP'), findsOneWidget);

    await pumpCard(tester, plan: plan);
    // The stamp fades out rather than vanishing.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CompletedStamp), findsNothing);

    // Let the photo's failed load run out its retry timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('the marker box holds the card', (tester) async {
    await pumpCard(tester);
    final drawn = tester.getSize(find.byType(WorldMapActivityCard));
    expect(PinSize.mapCardBox.width, greaterThanOrEqualTo(drawn.width));
    expect(PinSize.mapCardBox.height, greaterThanOrEqualTo(drawn.height));
  });

  testWidgets('tapping the card opens it; the X dismisses without opening', (
    tester,
  ) async {
    var taps = 0;
    var closes = 0;
    await pumpCard(tester, onTap: () => taps++, onClose: () => closes++);

    await tester.tap(find.text('Ordering at a café'));
    expect((taps, closes), (1, 0));

    await tester.tap(find.byType(WorldMapCardDismissButton));
    expect((taps, closes), (1, 1));
  });

  testWidgets('no X without an onClose', (tester) async {
    await pumpCard(tester);
    expect(find.byType(WorldMapCardDismissButton), findsNothing);
  });

  testWidgets('the card and its X take no Tab stop', (tester) async {
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              WorldMapActivityCard(
                card: card,
                state: ActivityPinState.available,
                plan: plan,
                participants: const [],
                openSlots: 0,
                played: false,
                onTap: () {},
                onClose: () {},
              ),
              Focus(
                focusNode: outside,
                child: const SizedBox.square(dimension: 8),
              ),
            ],
          ),
        ),
      ),
    );
    // The photo's placeholder animates, so the card never settles.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(outside.hasPrimaryFocus, isTrue, reason: 'Tab skips the card');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      outside.hasPrimaryFocus,
      isTrue,
      reason: 'the only stop on the page is the one past the card',
    );
  });
}
