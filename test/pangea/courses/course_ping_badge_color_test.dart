import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Coverage for #8481: the course-ping bell was pinned to the Open/joinable
/// green on every surface, so on a Waiting (purple) activity card it read as a
/// foreign chip. Its fill now follows the badged surface's state hue, and the
/// course plan's card hands it the very state that colours the card.
void main() {
  setUp(() {
    // The card's image widget reads Environment.cmsApi before deciding whether
    // to fetch, so dotenv has to be loaded even though no image is wanted.
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the tree isn't
    // built until localizations finish loading.
    await tester.pumpAndSettle();
  }

  Color badgeFill(WidgetTester tester) => tester
      .widget<Material>(
        find.descendant(
          of: find.byType(CoursePingBadge),
          matching: find.byType(Material),
        ),
      )
      .color!;

  group('CoursePingBadge fill', () {
    for (final state in ActivityPinState.values) {
      testWidgets('is the ${state.name} hue on a ${state.name} surface', (
        tester,
      ) async {
        await pump(tester, Center(child: CoursePingBadge(pinState: state)));
        expect(badgeFill(tester), state.color);
      });
    }

    testWidgets('falls back to the joinable green with no state', (
      tester,
    ) async {
      await pump(tester, const Center(child: CoursePingBadge()));
      expect(badgeFill(tester), ActivityPinState.joinable.color);
    });
  });

  group('ObjectiveSection ping bell', () {
    const activityId = 'a-1';

    ActivityPlanModel plan() => ActivityPlanModel(
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
      title: 'Buy Tickets at the Theater',
      learningObjective: '',
      instructions: '',
      vocab: const [],
      activityId: activityId,
      // A host outside AppConfig's image allowlist, so the card renders its
      // no-image fallback instead of reaching for the network.
      imageURL: 'https://images.test.invalid/$activityId.png',
    );

    Widget section({required ActivityPinState? state, bool complete = false}) =>
        SizedBox(
          width: 400.0,
          child: ObjectiveSection(
            group: QuestObjectiveGroup(
              objective: LearningObjective(
                id: 'lo-1',
                objective: 'Can buy a ticket.',
              ),
              activities: [QuestActivity(activityId: activityId, plan: plan())],
            ),
            onTap: (_) {},
            userStarsByActivity: (_) => 0,
            hasCompletedActivity: (_) => complete,
            liveStateByActivity: (_) => (
              state: state,
              openSessions: state == ActivityPinState.joinable ? 1 : 0,
              participants: const <String>[],
              openSlots: state == ActivityPinState.ongoingPending ? 1 : 0,
            ),
            availableParticipants: 10,
            progress: null,
            pingedActivityId: activityId,
            spacing: 0.0,
            cardWidth: 160.0,
            cardHeight: 220.0,
          ),
        );

    /// The state the card colours itself with — what the bell has to match.
    ActivityPinState? cardState(WidgetTester tester) => tester
        .widget<ActivitySuggestionCard>(find.byType(ActivitySuggestionCard))
        .pinState;

    testWidgets("takes the Waiting card's purple, not the joinable green", (
      tester,
    ) async {
      await pump(tester, section(state: ActivityPinState.ongoingPending));
      expect(cardState(tester), ActivityPinState.ongoingPending);
      expect(badgeFill(tester), ActivityPinState.ongoingPending.color);
      expect(badgeFill(tester), isNot(ActivityPinState.joinable.color));
    });

    testWidgets("takes the Ongoing card's purple", (tester) async {
      await pump(tester, section(state: ActivityPinState.ongoingActive));
      expect(cardState(tester), ActivityPinState.ongoingActive);
      expect(badgeFill(tester), ActivityPinState.ongoingActive.color);
    });

    testWidgets('stays green on an Open card, which is green already', (
      tester,
    ) async {
      await pump(tester, section(state: ActivityPinState.joinable));
      expect(cardState(tester), ActivityPinState.joinable);
      expect(badgeFill(tester), ActivityPinState.joinable.color);
    });

    testWidgets('falls back to green on a card with no state fill', (
      tester,
    ) async {
      await pump(tester, section(state: null));
      expect(cardState(tester), isNull);
      expect(badgeFill(tester), ActivityPinState.joinable.color);
    });

    testWidgets('follows a completed card, which drops its state fill', (
      tester,
    ) async {
      await pump(
        tester,
        section(state: ActivityPinState.ongoingPending, complete: true),
      );
      expect(cardState(tester), isNull);
      expect(badgeFill(tester), ActivityPinState.joinable.color);
    });
  });
}
