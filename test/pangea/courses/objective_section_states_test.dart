import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The three Mission-header states of the full course plan (#8874): the
/// Up-next Mission wears an "Up next" label and the primary accent, a
/// satisfied Mission trades its star for a check and mutes its text, and every
/// other Mission stays plain. Pinned because the state used to be a single
/// colour swap nobody could see.
void main() {
  setUp(() {
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  const objectiveText = 'Can ask for directions.';
  const upNextLabel = 'Up next';

  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: 2,
    ),
    title: 'Old Town Directions',
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: 'a-0',
    imageURL: 'https://images.test.invalid/a-0.png',
  );

  Widget wrap({required bool isUpNext, MissionProgress? progress}) =>
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ObjectiveSection(
            group: QuestObjectiveGroup(
              objective: LearningObjective(
                id: 'lo-1',
                objective: objectiveText,
              ),
              activities: [QuestActivity(activityId: 'a-0', plan: plan())],
            ),
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
            progress: progress,
            collapsible: true,
            isUpNext: isUpNext,
          ),
        ),
      );

  /// A column-mode (wide) or phone (narrow) viewport; the header lays out
  /// differently in each, and the label has to survive both.
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    required bool isUpNext,
    MissionProgress? progress,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(isUpNext: isUpNext, progress: progress));
    await tester.pumpAndSettle();
  }

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.text(objectiveText))).colorScheme;

  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  /// The star-or-check glyph in the header, found beside the fraction so the
  /// activity card's own star row can't satisfy the lookup.
  Finder headerIcon(WidgetTester tester, String fraction, IconData icon) =>
      find.descendant(
        of: find.ancestor(of: find.text(fraction), matching: find.byType(Row)),
        matching: find.byIcon(icon),
      );

  group('Mission header states', () {
    testWidgets('the Up-next Mission says so in words and wears the accent', (
      tester,
    ) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: true,
        progress: const MissionProgress(stars: 0, threshold: 4),
      );

      expect(find.text(upNextLabel), findsOneWidget);
      expect(colorOf(tester, objectiveText), scheme(tester).primary);
      expect(headerIcon(tester, '0/4', Icons.star), findsOneWidget);
    });

    testWidgets('the label survives the narrow (phone) header layout', (
      tester,
    ) async {
      await pumpAt(
        tester,
        400,
        isUpNext: true,
        progress: const MissionProgress(stars: 0, threshold: 4),
      );

      expect(find.text(upNextLabel), findsOneWidget);
    });

    testWidgets('a satisfied Mission trades its star for a check and mutes '
        'its text', (tester) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: false,
        progress: const MissionProgress(stars: 4, threshold: 4),
      );

      expect(headerIcon(tester, '4/4', Icons.check_circle), findsOneWidget);
      expect(headerIcon(tester, '4/4', Icons.star), findsNothing);
      expect(
        tester
            .widget<Icon>(headerIcon(tester, '4/4', Icons.check_circle))
            .color,
        Theme.of(tester.element(find.text(objectiveText))).pangea.success,
      );
      expect(colorOf(tester, objectiveText), scheme(tester).onSurfaceVariant);
      expect(colorOf(tester, '4/4'), scheme(tester).onSurfaceVariant);
      expect(find.text(upNextLabel), findsNothing);
    });

    testWidgets('a satisfied Mission that is also Up next keeps the label and '
        'the check', (tester) async {
      // Every Mission satisfied → the resolver anchors on the weakest one.
      await pumpAt(
        tester,
        1200,
        isUpNext: true,
        progress: const MissionProgress(stars: 4, threshold: 4),
      );

      expect(find.text(upNextLabel), findsOneWidget);
      expect(headerIcon(tester, '4/4', Icons.check_circle), findsOneWidget);
      expect(colorOf(tester, objectiveText), scheme(tester).primary);
    });

    testWidgets('a later Mission stays plain', (tester) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: false,
        progress: const MissionProgress(stars: 1, threshold: 4),
      );

      expect(find.text(upNextLabel), findsNothing);
      expect(headerIcon(tester, '1/4', Icons.star), findsOneWidget);
      // Plain bodyMedium — no accent, no muting.
      expect(
        colorOf(tester, objectiveText),
        Theme.of(
          tester.element(find.text(objectiveText)),
        ).textTheme.bodyMedium?.color,
      );
      // The star's fill is what carries the fraction, so it wears the readable
      // gold, not the decorative one (#8983).
      expect(
        tester.widget<Icon>(headerIcon(tester, '1/4', Icons.star)).color,
        Theme.of(tester.element(find.text(objectiveText))).pangea.goldGraphic,
      );
    });
  });
}
