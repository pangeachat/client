import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client, Event, Membership, Room;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/joined_course_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — the course card only wants a client on the subtree
/// for its info chips to resolve the course room off.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  // ignore: must_call_super
  void initState() {}

  @override
  Client get client => _client;
}

/// #8593 — the joined-course page is where a link join now finishes even when
/// the course's quest doesn't resolve, so it has to say what was joined from
/// the space alone. See `joining-courses.instructions.md`.
///
/// #8949 — the card's language / level / count chips are now the shared
/// [CourseInfoChips], so the count is the course's activities (from the quest
/// outline) rather than its Mission count, and every course surface reads the
/// same three chips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spaceId = '!course:fakeServer.notExisting';
  const spaceName = 'Intro to German';

  late Client client;

  setUpAll(() async {
    // A warm language cache — the info chips' language chip resolves through
    // PLanguageStore, and an unseeded store fetches over the network.
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'de',
            'language_name': 'German',
            'l2_support': 'full',
          },
          {'language_code': 'en', 'language_name': 'English'},
        ],
      }),
    });
    await PLanguageStore.initialize();
    // The course avatar reads the bot name out of the environment.
    dotenv.testLoad(mergeWith: <String, String>{});
    // Localizations are deferred-loaded, so a subtree built before the locale
    // resolves pumps empty. Preload the one locale this file renders in.
    await lookupL10n(const Locale('en'));
    client = await getTestClient();

    final space = Room(
      id: spaceId,
      client: client,
      membership: Membership.join,
    );
    space.setState(
      Event(
        type: 'm.room.name',
        content: {'name': spaceName},
        stateKey: '',
        senderId: '@test:fakeServer.notExisting',
        eventId: '\$name',
        originServerTs: DateTime.utc(2026, 1, 1),
        room: space,
      ),
    );
    client.rooms.add(space);
    // The info chips' language chip reads the learner's languages off the
    // controller.
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
  });

  tearDownAll(() => client.dispose());

  setUp(QuestRepo.resetOutlineCacheForTest);

  tearDown(() {
    QuestRepo.debugBuildOutline = null;
    QuestRepo.resetOutlineCacheForTest();
  });

  /// The quest behind [quest], as the info chips read it: two Missions holding
  /// three activities between them.
  void seedOutline() {
    ActivityPlanModel plan(String id) => ActivityPlanModel(
      req: ActivityPlanRequest(
        topic: '',
        mode: '',
        objective: '',
        media: MediaEnum.nan,
        cefrLevel: LanguageLevelTypeEnum.a1,
        languageOfInstructions: 'en',
        targetLanguage: 'de',
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

    QuestRepo.debugBuildOutline = (_, {String? courseRoomId}) async =>
        Result.value(
          QuestOutline(
            quest: QuestPlan(
              id: 'quest-1',
              name: 'German A1: Your Journey',
              description: '',
              targetLanguage: 'de',
              targetCefr: 'A1',
              sequence: const [],
            ),
            groups: [
              group('lo-a', ['a', 'b']),
              group('lo-b', ['c']),
            ],
          ),
        );
  }

  CoursePlanModel quest() => CoursePlanModel(
    uuid: 'quest-1',
    title: 'German A1: Your Journey',
    description: 'Travel the German-speaking world.',
    targetLanguage: 'de',
    languageOfInstructions: 'en',
    cefrLevel: LanguageLevelTypeEnum.a1,
    topicIds: const ['a', 'b'],
    mediaIds: const [],
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  Future<void> pumpPage(WidgetTester tester, {CoursePlanModel? course}) async {
    final state = OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    )..setJoinedRoomId(spaceId);
    if (course != null) state.setJoinedCoursePlan(course);

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrixState(client),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: JoinedCourseStepView(
              step: JoinedCourseOnboardingStep(
                client: client,
                state: state,
                maxRemainingSteps: 0,
              ),
              loading: false,
              hasNextStep: false,
              forward: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without a quest the space still names what was joined', (
    tester,
  ) async {
    seedOutline();
    await pumpPage(tester);
    expect(find.text(spaceName), findsOneWidget);
    // The chips and description describe the quest, so they stay away.
    expect(find.text('DE'), findsNothing);
    expect(find.textContaining('activit'), findsNothing);
  });

  testWidgets('with a quest the full course card is shown', (tester) async {
    seedOutline();
    await pumpPage(tester, course: quest());

    expect(find.text('German A1: Your Journey'), findsOneWidget);
    expect(find.text('Travel the German-speaking world.'), findsOneWidget);
    // The shared course info chips (#8949): the course's language, its level,
    // and how many activities it holds — never its Mission count.
    expect(find.text('DE'), findsOneWidget);
    expect(find.text('3 activities'), findsOneWidget);
    expect(find.textContaining('module'), findsNothing);
  });
}
