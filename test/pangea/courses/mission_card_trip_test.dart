import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_card.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_play_button.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../audio_players_stub.dart';

/// The Mission card on a course that is a trip (pangeachat/.github#780):
/// its city with Focus, and a city not yet open saying so where Play would
/// pulse.
void main() {
  setUpAll(AudioPlayersStub.install);
  tearDownAll(AudioPlayersStub.uninstall);

  ActivityPlanModel plan(String id) => ActivityPlanModel(
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
    title: id,
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
  );

  final group = QuestObjectiveGroup(
    objective: const LearningObjective(id: 'lo-1', objective: 'Can greet.'),
    activities: [QuestActivity(activityId: 'a1', plan: plan('a1'))],
    pacing: const MissionPacing(
      city: MissionCity(name: 'Oaxaca', latE6: 17082700, lngE6: -96670000),
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onFocus,
    bool closed = false,
    String? opensLine,
    VoidCallback? onEnterEarly,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MissionCard(
              group: group,
              index: 3,
              progress: const MissionProgress(xp: 0, threshold: 1000),
              breakdown: const MissionXpBreakdown(),
              onPlay: () {},
              onPractice: () {},
              playLabel: 'Next activity',
              onFocus: onFocus,
              closed: closed,
              opensLine: opensLine,
              onEnterEarly: onEnterEarly,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Mission\'s city, and Focus brings the map there', (
    tester,
  ) async {
    var focused = 0;
    await pump(tester, onFocus: () => focused++);
    expect(find.textContaining('Oaxaca'), findsOneWidget);
    await tester.tap(find.byTooltip("Focus on this Mission's activities"));
    expect(focused, 1);
  });

  testWidgets('without Focus the city still shows', (tester) async {
    await pump(tester);
    expect(find.textContaining('Oaxaca'), findsOneWidget);
    expect(find.byTooltip("Focus on this Mission's activities"), findsNothing);
  });

  testWidgets('a city not yet open says so and when, and Play is disabled', (
    tester,
  ) async {
    await pump(tester, closed: true, opensLine: 'Opens after Mission 2');
    expect(
      find.textContaining('Not yet open · Opens after Mission 2'),
      findsOneWidget,
    );
    final play = tester.widget<MissionPlayButton>(
      find.byType(MissionPlayButton),
    );
    expect(play.onPressed, isNull);
    expect(find.text('Enter early'), findsNothing);
  });

  testWidgets('with entering early on, the card offers the way in', (
    tester,
  ) async {
    var entered = 0;
    await pump(
      tester,
      closed: true,
      opensLine: 'Opens Nov 9',
      onEnterEarly: () => entered++,
    );
    await tester.tap(find.text('Enter early'));
    expect(entered, 1);
  });
}
