import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_circle.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_progress_circles.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// The three Mission-header states of the full course plan (#8874): the
/// current Mission wears a "Current mission" label and the primary accent
/// (#9559), a complete Mission shows the gold star it earned and mutes its
/// text, and every other Mission stays plain. The class location wears its
/// own label beside it. Pinned because the state used to be a single colour
/// swap nobody could see.
void main() {
  setUp(() {
    dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test.invalid'});
  });

  const objectiveText = 'Can ask for directions.';
  const upNextLabel = 'Current mission';
  const classLabel = 'Class location';

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
    bool isClassLocation = false,
    MissionProgress? progress,
    bool collapsed = false,
    VoidCallback? onToggleCollapsed,
    MissionPacing? pacing,
  }) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: ObjectiveSection(
        index: 1,
        missionCount: 1,
        group: QuestObjectiveGroup(
          objective: LearningObjective(id: 'lo-1', objective: objectiveText),
          activities: [QuestActivity(activityId: 'a-0', plan: plan())],
          pacing: pacing,
        ),
        onTap: (_) {},
        xpByActivity: (_) => 0,
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
        isClassLocation: isClassLocation,
      ),
    ),
  );

  /// A column-mode (wide) or phone (narrow) viewport; the header lays out
  /// differently in each, and the label has to survive both.
  Future<void> pumpAt(
    WidgetTester tester,
    double width, {
    required bool isUpNext,
    bool isClassLocation = false,
    MissionProgress? progress,
    MissionPacing? pacing,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrap(
        isUpNext: isUpNext,
        isClassLocation: isClassLocation,
        progress: progress,
        pacing: pacing,
      ),
    );
    await tester.pumpAndSettle();
  }

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.textContaining(objectiveText))).colorScheme;

  // Contains, not equals: the statement carries its labels after its text.
  Color? colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.textContaining(text)).style?.color;

  /// The Mission's circle in the header (#9559): its number, or its star
  /// once complete.
  ObjectiveCircleState headerCircle(WidgetTester tester) =>
      tester.widget<ObjectiveCircle>(find.byType(ObjectiveCircle)).item.state;

  group('Mission header states', () {
    testWidgets('the Up-next Mission says so in words and wears the accent', (
      tester,
    ) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: true,
        progress: const MissionProgress(xp: 0, threshold: 300),
      );

      expect(find.text(upNextLabel), findsOneWidget);
      expect(colorOf(tester, objectiveText), scheme(tester).primary);
      // The current Mission's circle, not yet its star.
      expect(headerCircle(tester), ObjectiveCircleState.current);
    });

    testWidgets('the label survives the narrow (phone) header layout', (
      tester,
    ) async {
      await pumpAt(
        tester,
        400,
        isUpNext: true,
        progress: const MissionProgress(xp: 0, threshold: 300),
      );

      expect(find.text(upNextLabel), findsOneWidget);
    });

    testWidgets('the class location sits beside the current Mission\'s '
        'label', (tester) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: true,
        isClassLocation: true,
        progress: const MissionProgress(xp: 0, threshold: 300),
      );

      expect(find.text(upNextLabel), findsOneWidget);
      expect(find.text(classLabel), findsOneWidget);
    });

    testWidgets('a complete Mission earns its gold star and mutes its text', (
      tester,
    ) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: false,
        progress: const MissionProgress(xp: 300, threshold: 300),
      );

      expect(headerCircle(tester), ObjectiveCircleState.complete);
      expect(colorOf(tester, objectiveText), scheme(tester).onSurfaceVariant);
      expect(find.text(upNextLabel), findsNothing);
    });

    testWidgets('a later Mission stays plain', (tester) async {
      await pumpAt(
        tester,
        1200,
        isUpNext: false,
        progress: const MissionProgress(xp: 100, threshold: 300),
      );

      expect(find.text(upNextLabel), findsNothing);
      expect(headerCircle(tester), ObjectiveCircleState.later);
      // Plain bodyMedium — no accent, no muting.
      expect(
        colorOf(tester, objectiveText),
        Theme.of(
          tester.element(find.textContaining(objectiveText)),
        ).textTheme.bodyMedium?.color,
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

      await tester.tap(find.textContaining(objectiveText));
      await tester.pumpAndSettle();

      expect(toggles, 1);
      expect(find.text('Old Town Directions'), findsOneWidget);
    });

    testWidgets('a collapsed Mission shows its header but not its activities', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(isUpNext: false, collapsed: true));
      await tester.pumpAndSettle();

      expect(find.textContaining(objectiveText), findsOneWidget);
      expect(find.text('Old Town Directions'), findsNothing);
    });
  });

  // The course's own note and soft due date (content-studio): the date as a
  // chip in the header, the note under the title, in the course's time zone,
  // and nothing changes after the date. The chip's text shares a line with its
  // icon, so it is found by containment.
  group('Mission note and due date', () {
    final year = DateTime.now().year;
    // 21:00 UTC on Oct 20 is 5:00 PM in New York (EDT) and 6:00 AM on Oct 21
    // in Tokyo — two zones that cannot both match the device's.
    final dueAt = DateTime.utc(year, 10, 20, 21);
    const dueLabel = 'Due Oct 20, 5:00 PM';

    Future<void> pumpPacing(
      WidgetTester tester,
      MissionPacing pacing, {
      bool collapsed = false,
    }) async {
      await tester.pumpWidget(
        wrap(isUpNext: false, pacing: pacing, collapsed: collapsed),
      );
      await tester.pumpAndSettle();
    }

    /// The tappable Mission header: the nearest ink around the statement.
    Finder header() => find
        .ancestor(
          of: find.textContaining(objectiveText),
          matching: find.byType(InkWell),
        )
        .first;

    testWidgets('shows the note and the due date in the course zone', (
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
      expect(find.textContaining(dueLabel), findsOneWidget);
    });

    // The date sits under the title, not beside it, so the can-do statement
    // keeps the header's full width in both layouts.
    for (final width in [1200.0, 400.0]) {
      testWidgets('the due date sits under the title at width $width', (
        tester,
      ) async {
        await pumpAt(
          tester,
          width,
          isUpNext: true,
          progress: const MissionProgress(xp: 0, threshold: 4),
          pacing: MissionPacing(dueAt: dueAt, timeZone: 'America/New_York'),
        );
        final due = find.textContaining(dueLabel);
        expect(due, findsOneWidget);
        expect(find.descendant(of: header(), matching: due), findsNothing);
        expect(
          tester.getTopLeft(due).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.textContaining(objectiveText)).dy,
          ),
        );
      });
    }

    testWidgets('a folded Mission keeps its due date and hides its note', (
      tester,
    ) async {
      await pumpPacing(
        tester,
        MissionPacing(
          note: 'Lesson 6',
          dueAt: dueAt,
          timeZone: 'America/New_York',
        ),
        collapsed: true,
      );
      expect(find.textContaining(dueLabel), findsOneWidget);
      expect(find.text('Lesson 6'), findsNothing);
    });

    testWidgets('a long note is clamped behind Show more', (tester) async {
      await pumpAt(
        tester,
        400,
        isUpNext: false,
        pacing: MissionPacing(note: List.filled(20, 'Lesson six.').join(' ')),
      );
      expect(find.text('Show more'), findsOneWidget);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a different course zone shows a different wall time', (
      tester,
    ) async {
      await pumpPacing(
        tester,
        MissionPacing(dueAt: dueAt, timeZone: 'Asia/Tokyo'),
      );
      expect(find.textContaining('Due Oct 21, 6:00 AM'), findsOneWidget);
    });

    testWidgets('no course zone shows the device local time', (tester) async {
      await pumpPacing(tester, MissionPacing(dueAt: dueAt));
      final local = dueAt.toLocal();
      expect(
        find.textContaining(
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
      expect(find.textContaining('Due Jan 2, 4:00 PM'), findsOneWidget);
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
            index: 1,
            missionCount: 1,
            group: QuestObjectiveGroup(
              objective: const LearningObjective(id: 'lo-1', objective: 'x'),
              activities: activities,
            ),
            onTap: (_) {},
            xpByActivity: (_) => 0,
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
