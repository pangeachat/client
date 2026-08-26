import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client, Event, Membership, Room;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/joined_course_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/joined_course_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../get_test_client.dart';

/// #8593 — the joined-course page is where a link join now finishes even when
/// the course's quest doesn't resolve, so it has to say what was joined from
/// the space alone. See `joining-courses.instructions.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const spaceId = '!course:fakeServer.notExisting';
  const spaceName = 'Intro to German';

  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
  });

  tearDownAll(() => client.dispose());

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
      MaterialApp(
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
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without a quest the space still names what was joined', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text(spaceName), findsOneWidget);
    // The chips and description describe the quest, so they stay away.
    expect(find.text('A1'), findsNothing);
  });

  testWidgets('with a quest the full course card is shown', (tester) async {
    await pumpPage(tester, course: quest());

    expect(find.text('German A1: Your Journey'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('Travel the German-speaking world.'), findsOneWidget);
  });
}
