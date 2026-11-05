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
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/objective_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_summary_unsubscribed_card.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_user_summaries_widget.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'courses/course_missions_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// What the end card reads off the activity chat controller: the summary to
/// show. The real controller recomputes it from room state; this one holds it.
class _FakeActivityChatController implements ActivityChatController {
  @override
  final ValueNotifier<ActivitySummaryView> summaryView = ValueNotifier(
    ActivitySummaryView(
      summary: ActivitySummaryResponseModel(
        participants: const [],
        summary: 'Well played.',
      ),
      isLoading: false,
      hasFailed: false,
      updateFailed: false,
      canRequest: false,
      loadingDeadline: null,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The two members of the chat the end card reads: its room and its activity
/// controller.
class _FakeChatController implements ChatController {
  _FakeChatController(this.room);

  @override
  final Room room;

  @override
  final ActivityChatController activityController =
      _FakeActivityChatController();

  // `State` mixes in Diagnosticable, whose toString takes a named argument
  // that noSuchMethod can't cover.
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeChatController';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// #9418 — a playtester couldn't tell whether a finished activity was saved.
/// Once the session is saved, the end card says so under "All Finished!", for
/// a learner with or without a subscription, and the line opens the Learning
/// Objectives page that lists the session: its Mission's page for a course
/// activity, else the page's own list (activity-session.instructions.md,
/// "Completion saves itself").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const activityId = 'a1';
  const courseId = '!course:fakeServer.notExisting';
  const savedLine = 'Activity saved to Learning Objectives';

  late Client client;
  late GoRouter router;

  setUpAll(() async {
    // `isActivityFinished` skips the bot's role, whose name comes from the env.
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    final tempDir = await Directory.systemTemp.createTemp('saved_notice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    // The gate's unlock button reads its click volume from app settings.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async => client = await getTestClient());

  tearDown(() async {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.resetOutlineCacheForTest();
    await client.dispose();
  });

  /// The learner's finished role, archived by the save when [saved].
  Event roleState(Room room, {required bool saved}) => Event(
    type: PangeaEventTypes.activityRole,
    content: ActivityRolesModel({
      'role1': ActivityRoleModel(
        id: 'role1',
        userId: userId,
        role: 'debater',
        finishedAt: DateTime.utc(2026, 1, 1, 13),
        archivedAt: saved ? DateTime.utc(2026, 1, 1, 14) : null,
      ),
    }).toJson(),
    senderId: userId,
    eventId: saved ? '\$saved' : '\$finished',
    originServerTs: DateTime.utc(2026, 1, 1, 13),
    stateKey: '',
    room: room,
  );

  /// A session of [activityId] finished for everyone, saved when [saved].
  Room finishedSession({required bool saved}) {
    final room = Room(
      id: '!session:fakeServer.notExisting',
      client: client,
      membership: Membership.join,
    );
    room.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {'type': '${PangeaRoomTypes.activitySession}:$activityId'},
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    room.setState(roleState(room, saved: saved));
    return room;
  }

  /// A joined course whose Mission lo-1 lists [activityId]. No language is
  /// recorded on it, so it counts in the learner's current one.
  void joinCourseListingActivity() {
    final plan = ActivityPlanModel(
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
      title: activityId,
      learningObjective: '',
      instructions: '',
      vocab: const [],
      activityId: activityId,
      roles: const {},
    );
    final mission = LearningObjective(id: 'lo-1', objective: 'Order a coffee');
    QuestRepo.debugBuildOutline = (id, {courseRoomId}) async => Result.value(
      QuestOutline(
        quest: QuestPlan(
          id: 'quest-1',
          name: '',
          description: '',
          targetLanguage: 'es',
          sequence: [QuestObjectiveStep(objective: mission, wasMinted: false)],
        ),
        groups: [
          QuestObjectiveGroup(
            objective: mission,
            activities: [QuestActivity(activityId: activityId, plan: plan)],
          ),
        ],
      ),
    );
    final course = Room(
      id: courseId,
      client: client,
      membership: Membership.join,
    );
    client.rooms.add(course);
    putState(course, EventTypes.RoomCreate, {'type': RoomCreationTypes.mSpace});
    putState(
      course,
      PangeaEventTypes.coursePlan,
      CoursePlanEvent(uuid: 'quest-1').toJson(),
    );
  }

  /// The end card as the chat's timeline shows it, with [location]'s panels
  /// open.
  Future<void> pumpEndCard(
    WidgetTester tester,
    Room room, {
    required bool subscribed,
    String location = '/',
  }) async {
    MatrixState.pangeaController = FakePangeaController(subscribed: subscribed);
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: ListView(
              children: [
                ActivityUserSummaries(controller: _FakeChatController(room)),
              ],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    // Not pumpAndSettle: the gate's shimmer never stops. Two frames see the
    // localizations in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Taps the saved line and returns where it went.
  Future<Uri> tapSavedLine(WidgetTester tester) async {
    await tester.tap(find.text(savedLine));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router.routerDelegate.currentConfiguration.uri;
  }

  testWidgets('the end card says the activity was saved once it is, and not '
      'before, at its foot under the feedback', (tester) async {
    final room = finishedSession(saved: false);
    await pumpEndCard(tester, room, subscribed: true);

    expect(find.text('All Finished!'), findsOneWidget);
    expect(find.text(savedLine), findsNothing);

    // The save archives the learner's role while the card is on screen.
    room.setState(roleState(room, saved: true));
    await tester.pump();

    expect(find.text(savedLine), findsOneWidget);
    final heading = tester.getRect(find.text('All Finished!'));
    final line = tester.getRect(find.text(savedLine));
    final summary = tester.getRect(find.text('Well played.'));
    expect(summary.top, greaterThanOrEqualTo(heading.bottom));
    expect(line.top, greaterThanOrEqualTo(summary.bottom));
  });

  testWidgets('an unsubscribed learner\'s end card says so too', (
    tester,
  ) async {
    final room = finishedSession(saved: false);
    await pumpEndCard(tester, room, subscribed: false);

    expect(find.byType(ActivitySummaryUnsubscribedCard), findsOneWidget);
    expect(find.text(savedLine), findsNothing);

    room.setState(roleState(room, saved: true));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ActivitySummaryUnsubscribedCard),
        matching: find.text(savedLine),
      ),
      findsOneWidget,
    );
  });

  testWidgets('for a course activity, the link opens its Mission\'s page, '
      'beside the Learning Objectives list even with another list open', (
    tester,
  ) async {
    joinCourseListingActivity();
    await pumpEndCard(
      tester,
      finishedSession(saved: true),
      subscribed: true,
      location: WorkspaceNav.openAnalytics(
        Uri.parse('/'),
        subpage: ProgressIndicatorEnum.wordsUsed,
      ),
    );

    final uri = await tapSavedLine(tester);

    expect(activeObjectiveDetailFor(uri), 'lo-1');
    final right = parseOpenPanels(uri).right.map((t) => t.param).toList();
    expect(
      right.whereType<ObjectiveTokenParam>().single.courseId,
      courseId,
      reason: 'the Mission page reads the course the list read it from',
    );
    expect(
      right.whereType<AnalyticsTokenParam>().single.subpage,
      ProgressIndicatorEnum.activities,
      reason: 'beside the Learning Objectives list',
    );
  });

  testWidgets('for any other activity, the link opens the list itself with '
      'the session still open, which the list picks out under Other '
      'activities', (tester) async {
    final room = finishedSession(saved: true);
    await pumpEndCard(
      tester,
      room,
      subscribed: false,
      location: WorkspaceNav.openRoomById(Uri.parse('/'), room.id),
    );

    final uri = await tapSavedLine(tester);

    expect(activeObjectiveDetailFor(uri), isNull);
    expect(activeRoomIdFromPanels(uri), room.id);
    final right = parseOpenPanels(uri).right.map((t) => t.param).toList();
    expect(
      right.whereType<AnalyticsTokenParam>().single.subpage,
      ProgressIndicatorEnum.activities,
    );
  });
}
