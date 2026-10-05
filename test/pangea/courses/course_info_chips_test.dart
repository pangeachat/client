import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client, Event, Membership, Room;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — the chips only want a client to resolve the course
/// room's activity pin off.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  // ignore: must_call_super
  void initState() {}

  @override
  Client get client => _client;
}

/// #8949 — the course info chips count **activities**, not Missions: a Mission
/// carries anywhere from 1 to 6 of them, so its count said little about how
/// much content a course holds.
///
/// The count has to be the same set the course panel lists, or the tile
/// promises content the course doesn't show (#7976): activity-less Missions
/// are dropped, and a joined course's per-Mission activity pin narrows it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spaceId = '!course:fakeServer.notExisting';
  const questId = 'quest-1';

  late Client client;

  ActivityPlanModel plan(String id) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: '',
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
  );

  QuestObjectiveGroup group(String id, List<String> activityIds) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: 'obj-$id'),
        activities: [
          for (final a in activityIds)
            QuestActivity(activityId: a, plan: plan(a)),
        ],
      );

  QuestOutline outline(List<QuestObjectiveGroup> groups) => QuestOutline(
    quest: QuestPlan(
      id: questId,
      name: 'Español 101',
      description: '',
      targetLanguage: 'es',
      targetCefr: 'A1',
      sequence: const [],
    ),
    groups: groups,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();
    // Localizations are deferred-loaded, so a subtree built before the locale
    // resolves pumps empty. Preload the one locale this file renders in.
    await lookupL10n(const Locale('en'));

    client = await getTestClient();
    // The language chip resolves the learner's own languages through the
    // controller; an unset profile just leaves it untinted.
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(QuestRepo.resetOutlineCacheForTest);

  tearDown(() {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.resetOutlineCacheForTest();
    client.rooms.clear();
  });

  /// A joined course space pinning [pins] (Mission id → allowed activity ids).
  void seedCourseRoom(Map<String, List<String>>? pins) {
    final space = Room(
      id: spaceId,
      client: client,
      membership: Membership.join,
    );
    if (pins != null) {
      space.setState(
        Event(
          type: PangeaEventTypes.teacherMode,
          content: {'enabled': true, 'pinned_activities_by_objective': pins},
          stateKey: '',
          senderId: '@test:fakeServer.notExisting',
          eventId: '\$teacher-mode',
          originServerTs: DateTime.utc(2026, 1, 1),
          room: space,
        ),
      );
    }
    client.rooms.add(space);
  }

  Future<void> pumpChips(
    WidgetTester tester,
    QuestOutline value, {
    String? courseRoomId,
  }) async {
    QuestRepo.debugBuildOutline = (_, {String? courseRoomId}) async =>
        Result.value(value);

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrixState(client),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: CourseInfoChips(
              questId,
              courseRoomId: courseRoomId,
              fontSize: 12.0,
              iconSize: 12.0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('counts every activity across the Missions, not the Missions', (
    tester,
  ) async {
    await pumpChips(
      tester,
      outline([
        group('lo-1', ['a', 'b', 'c']),
        group('lo-2', ['d', 'e']),
      ]),
    );

    expect(find.text('5 activities'), findsOneWidget);
    expect(find.textContaining('module'), findsNothing);
  });

  testWidgets('an activity-less Mission adds nothing — the panel hides it '
      '(#7976)', (tester) async {
    await pumpChips(
      tester,
      outline([
        group('lo-1', ['a', 'b']),
        group('lo-2', const []),
      ]),
    );

    expect(find.text('2 activities'), findsOneWidget);
  });

  testWidgets('a single activity reads in the singular', (tester) async {
    await pumpChips(
      tester,
      outline([
        group('lo-1', ['a']),
      ]),
    );

    expect(find.text('1 activity'), findsOneWidget);
  });

  testWidgets("the course's activity pin narrows the count", (tester) async {
    seedCourseRoom({
      'lo-1': ['a', 'b'],
    });
    await pumpChips(
      tester,
      outline([
        group('lo-1', ['a', 'b', 'c']),
        group('lo-2', ['d', 'e']),
      ]),
      courseRoomId: spaceId,
    );

    // lo-1 pinned to two of its three, lo-2 unpinned and so unrestricted — a
    // count that matches neither the Mission count (2) nor the unpinned
    // activity count (5).
    expect(find.text('4 activities'), findsOneWidget);
  });

  testWidgets('a preview with no course room counts what the quest holds', (
    tester,
  ) async {
    await pumpChips(
      tester,
      outline([
        group('lo-1', ['a', 'b', 'c']),
      ]),
    );

    expect(find.text('3 activities'), findsOneWidget);
  });
}
