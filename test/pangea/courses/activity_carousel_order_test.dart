import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The row's contract after #8741 pulled it out of [ObjectiveSection]: it draws
/// the activities it is handed, in the order it is handed them, and nothing
/// else. A Mission's row supplies its own party-size order; the course page's
/// Suggested Activities row supplies the Priority matrix's order — neither can
/// work if the row re-sorts, and the course page must show no Mission text.
void main() {
  setUp(() {
    // The card's image widget reads Environment.cmsApi before deciding whether
    // to fetch, so dotenv has to be loaded even with no real image in play.
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  ActivityPlanModel plan(String id, String title, int participants) =>
      ActivityPlanModel(
        req: ActivityPlanRequest(
          topic: '',
          mode: '',
          objective: '',
          media: MediaEnum.nan,
          cefrLevel: LanguageLevelTypeEnum.a2,
          languageOfInstructions: 'en',
          targetLanguage: 'es',
          numberOfParticipants: participants,
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

  Widget wrap(List<QuestActivity> activities) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 900.0,
        child: ActivityCarousel(
          activities: activities,
          onTap: (_) {},
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
        ),
      ),
    ),
  );

  testWidgets('draws the activities in the order given, without re-sorting on '
      'party size', (tester) async {
    // Party sizes descending: the Mission row's own sort would flip these, so a
    // row that still sorts internally fails here.
    final activities = [
      QuestActivity(activityId: 'a', plan: plan('a', 'Alpha', 4)),
      QuestActivity(activityId: 'b', plan: plan('b', 'Beta', 3)),
      QuestActivity(activityId: 'c', plan: plan('c', 'Gamma', 2)),
    ];

    await tester.pumpWidget(wrap(activities));
    await tester.pumpAndSettle();

    double x(String title) => tester.getTopLeft(find.text(title)).dx;
    expect(x('Alpha'), lessThan(x('Beta')));
    expect(x('Beta'), lessThan(x('Gamma')));
  });

  testWidgets('renders no Mission statement of its own', (tester) async {
    await tester.pumpWidget(
      wrap([QuestActivity(activityId: 'a', plan: plan('a', 'Alpha', 2))]),
    );
    await tester.pumpAndSettle();

    // Sanity: the row really did render, so the assertion below means
    // something.
    expect(find.text('Alpha'), findsOneWidget);

    // The plan carries a can-do statement; the row must not surface it — that
    // is the Mission header's job on the full course plan (#8741).
    expect(find.text('Can introduce self.'), findsNothing);
  });
}
