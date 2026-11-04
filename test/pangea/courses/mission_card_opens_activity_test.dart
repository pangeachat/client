import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:async/async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../activity_session_fixtures.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';
import 'course_missions_fixtures.dart';

/// Skips `initMatrix()` — the list only wants a routed, localized subtree with
/// a client on it.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

/// #9632 — an activity opened from the course card carries its Mission in the
/// URL (`?mission=`) and the card's mark on its token, so the session started
/// from it closes back to the card on that Mission (quests.instructions.md,
/// "The Mission on show").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spaceId = '!course:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;
  late GoRouter router;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('mission_card_open');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
        // A discussion room is one the bot created.
        'BOT_NAME': testDiscussionBotId,
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    client = await getTestClient();
    MatrixState.pangeaController = FakePangeaController(client: client);
  });

  tearDown(() async {
    await client.dispose();
  });

  ActivityPlanModel plan(String id) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 1,
    ),
    title: id,
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
    roles: const {},
  );

  LearningObjective lo(String id) => LearningObjective(id: id, objective: id);

  /// A joined two-Mission course: lo-1 → a1, lo-2 → b1. [discussionB1]
  /// makes b1 a discussion.
  Room stubCourse({bool discussionB1 = false}) {
    QuestRepo.resetOutlineCacheForTest();
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async => Result.value(
      QuestOutline(
        quest: QuestPlan(
          id: 'quest-1',
          name: '',
          description: '',
          targetLanguage: 'es',
          sequence: [
            QuestObjectiveStep(objective: lo('lo-1'), wasMinted: false),
            QuestObjectiveStep(objective: lo('lo-2'), wasMinted: false),
          ],
        ),
        groups: [
          QuestObjectiveGroup(
            objective: lo('lo-1'),
            activities: [QuestActivity(activityId: 'a1', plan: plan('a1'))],
          ),
          QuestObjectiveGroup(
            objective: lo('lo-2'),
            activities: [
              QuestActivity(
                activityId: 'b1',
                plan: discussionB1
                    ? discussionActivityPlan(activityId: 'b1')
                    : plan('b1'),
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(() {
      QuestRepo.debugBuildOutline = null;
      QuestRepo.resetOutlineCacheForTest();
      QuestObjectivesLoader(client: client)
        ..progression.value = ProgressionResolution.empty
        ..dispose();
    });
    final room = Room(id: spaceId, client: client, membership: Membership.join);
    client.rooms.add(room);
    putState(room, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
    putPowerLevels(room);
    putState(
      room,
      PangeaEventTypes.coursePlan,
      CoursePlanEvent(uuid: 'quest-1', l2: 'es').toJson(),
    );
    return room;
  }

  /// The course card's list at [location], the way the course page mounts it:
  /// the Mission card for [missionId] when [missionCard], else the full plan.
  Future<void> pumpList(
    WidgetTester tester, {
    required String location,
    required bool missionCard,
    String? missionId,
    bool discussionB1 = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final room = stubCourse(discussionB1: discussionB1);
    final loader = QuestObjectivesLoader(client: client);
    addTearDown(loader.dispose);
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SizedBox(
              width: 600,
              child: CourseObjectivesList(
                room: room,
                suggestedOnly: missionCard,
                missionId: missionId,
                shrinkWrap: missionCard,
                objectivesProvider: loader,
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          // Reduced motion stills Play's pulse, which would otherwise keep a
          // frame scheduled forever.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => loader.loadOutline('quest-1', courseRoomId: room.id),
    );
    // Progress never resolves here, so its shimmer never settles: pump past
    // the localizations' load and the outline's arrival instead.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<Uri> tapActivity(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ActivitySuggestionCard),
        matching: find.text(title),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return router.routerDelegate.currentConfiguration.uri;
  }

  final course = 'c=${Uri.encodeComponent(spaceId)}&left=course';

  testWidgets('with no Mission picked, the activity\'s own Mission rides the '
      'URL', (tester) async {
    await pumpList(tester, location: '/?$course', missionCard: true);

    final uri = await tapActivity(tester, 'a1');
    expect(activityInfoFor(uri)?.activityId, 'a1');
    expect(activityInfoFor(uri)?.fromCourseCard, isTrue);
    expect(activityInfoFor(uri)?.fromCoursePlan, isFalse);
    expect(selectedMissionIdFor(uri), 'lo-1');
    expect(activeSpaceIdFor(uri), spaceId);
  });

  testWidgets('a picked Mission stays in the URL', (tester) async {
    await pumpList(
      tester,
      location: '/?$course&mission=lo-2',
      missionCard: true,
      missionId: 'lo-2',
    );

    final uri = await tapActivity(tester, 'b1');
    expect(activityInfoFor(uri)?.activityId, 'b1');
    expect(activityInfoFor(uri)?.fromCourseCard, isTrue);
    expect(selectedMissionIdFor(uri), 'lo-2');
  });

  testWidgets('from the full course plan, the URL takes the Mission the '
      'activity is listed under', (tester) async {
    await pumpList(
      tester,
      location: '/?$course&mission=lo-1',
      missionCard: false,
    );

    final uri = await tapActivity(tester, 'b1');
    expect(activityInfoFor(uri)?.activityId, 'b1');
    expect(activityInfoFor(uri)?.fromCourseCard, isTrue);
    expect(activityInfoFor(uri)?.fromCoursePlan, isTrue);
    expect(selectedMissionIdFor(uri), 'lo-2');
  });

  testWidgets('a discussion the learner has joined opens its room, with its '
      'Mission in the URL', (tester) async {
    final discussion = discussionRoom(
      client,
      activityId: 'b1',
      seats: [discussionSeat(client.userID!)],
    );
    client.rooms.add(discussion);
    await pumpList(
      tester,
      location: '/?$course&mission=lo-2',
      missionCard: true,
      missionId: 'lo-2',
      discussionB1: true,
    );

    final uri = await tapActivity(tester, 'The Market');
    expect(activeRoomIdFromPanels(uri), discussion.id);
    expect(activityInfoFor(uri), isNull);
    expect(selectedMissionIdFor(uri), 'lo-2');
    expect(activeSpaceIdFor(uri), spaceId);
  });
}
