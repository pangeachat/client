import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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

  Widget wrap({
    required bool isUpNext,
    MissionProgress? progress,
    bool collapsed = false,
    VoidCallback? onToggleCollapsed,
    MissionPacing? pacing,
  }) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: ObjectiveSection(
        group: QuestObjectiveGroup(
          objective: LearningObjective(id: 'lo-1', objective: objectiveText),
          activities: [QuestActivity(activityId: 'a-0', plan: plan())],
          pacing: pacing,
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
        collapsed: collapsed,
        onToggleCollapsed: onToggleCollapsed ?? () {},
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

  // The section holds no collapse state of its own: the course plan's list
  // builds lazily and disposes sections scrolled out of view, so a local flag
  // would reopen on scroll-back (#9248). The parent owns it; the section only
  // renders it and reports taps.
  group('Mission collapse', () {
    testWidgets('a header tap reports the toggle without folding on its own', (
      tester,
    ) async {
      var toggles = 0;
      await tester.pumpWidget(
        wrap(isUpNext: false, onToggleCollapsed: () => toggles++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(objectiveText));
      await tester.pumpAndSettle();

      expect(toggles, 1);
      expect(find.text('Old Town Directions'), findsOneWidget);
    });

    testWidgets('a collapsed Mission shows its header but not its activities', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(isUpNext: false, collapsed: true));
      await tester.pumpAndSettle();

      expect(find.text(objectiveText), findsOneWidget);
      expect(find.text('Old Town Directions'), findsNothing);
    });
  });

  // The course's own note and soft due date (content-studio): under the
  // title, in the course's time zone, and nothing changes after the date.
  group('Mission note and due date', () {
    final year = DateTime.now().year;
    // 21:00 UTC on Oct 20 is 5:00 PM in New York (EDT) and 6:00 AM on Oct 21
    // in Tokyo — two zones that cannot both match the device's.
    final dueAt = DateTime.utc(year, 10, 20, 21);

    Future<void> pumpPacing(WidgetTester tester, MissionPacing pacing) async {
      await tester.pumpWidget(wrap(isUpNext: false, pacing: pacing));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the note and the due line in the course zone', (
      tester,
    ) async {
      await pumpPacing(
        tester,
        MissionPacing(
          note: 'Lesson 6',
          dueAt: dueAt,
          timeZone: 'America/New_York',
        ),
      );
      expect(find.text('Lesson 6'), findsOneWidget);
      expect(find.text('Due Oct 20, 5:00 PM'), findsOneWidget);
    });

    testWidgets('a different course zone shows a different wall time', (
      tester,
    ) async {
      await pumpPacing(
        tester,
        MissionPacing(dueAt: dueAt, timeZone: 'Asia/Tokyo'),
      );
      expect(find.text('Due Oct 21, 6:00 AM'), findsOneWidget);
    });

    testWidgets('no course zone shows the device local time', (tester) async {
      await pumpPacing(tester, MissionPacing(dueAt: dueAt));
      final local = dueAt.toLocal();
      expect(
        find.text(
          'Due ${DateFormat.MMMd('en').format(local)}, '
          '${DateFormat('h:mm a', 'en').format(local)}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a past due date still shows and leaves the activities', (
      tester,
    ) async {
      await pumpPacing(
        tester,
        MissionPacing(
          dueAt: DateTime.utc(year, 1, 2, 21),
          timeZone: 'America/New_York',
        ),
      );
      expect(find.text('Due Jan 2, 4:00 PM'), findsOneWidget);
      expect(find.text('Old Town Directions'), findsOneWidget);
    });

    testWidgets('no pacing adds no lines', (tester) async {
      await tester.pumpWidget(wrap(isUpNext: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('Due '), findsNothing);
    });
  });

  // The group's activity list can be the shared outline cache's (a course
  // with no copy and no pins reads it as-is), so drawing it sorted must never
  // reorder it in place.
  testWidgets('drawing the section leaves the group\'s list in its order', (
    tester,
  ) async {
    ActivityPlanModel sized(String id, int people) => ActivityPlanModel(
      req: ActivityPlanRequest(
        topic: '',
        mode: '',
        objective: '',
        media: MediaEnum.nan,
        cefrLevel: LanguageLevelTypeEnum.a2,
        languageOfInstructions: 'en',
        targetLanguage: 'de',
        numberOfParticipants: people,
      ),
      title: id,
      learningObjective: '',
      instructions: '',
      vocab: const [],
      activityId: id,
      imageURL: 'https://images.test.invalid/$id.png',
    );
    final activities = [
      QuestActivity(activityId: 'big', plan: sized('big', 4)),
      QuestActivity(activityId: 'small', plan: sized('small', 2)),
    ];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ObjectiveSection(
            group: QuestObjectiveGroup(
              objective: const LearningObjective(id: 'lo-1', objective: 'x'),
              activities: activities,
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
            progress: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ObjectiveSection), findsOneWidget);
    expect(activities.map((a) => a.activityId), ['big', 'small']);
  });
}
