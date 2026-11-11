import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/profile_setup_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  // ignore: must_call_super
  void initState() {}

  @override
  Client get client => _client;
}

/// Someone who leaves onboarding before their learning language is saved
/// restarts it at the profile page, with fresh onboarding state. The page must
/// show the avatar they already saved, and Next must not replace it with a
/// random preset; an account with no avatar still gets one. See
/// `onboarding.instructions.md`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const avatarEndpoint =
      '/client/v3/profile/%40test%3AfakeServer.notExisting/avatar_url';

  late Client client;

  setUpAll(() async {
    dotenv.testLoad(mergeWith: <String, String>{});
    client = await getTestClient();
  });

  setUp(() => FakeMatrixApi.calledEndpoints.remove(avatarEndpoint));

  tearDownAll(() => client.dispose());

  Future<void> storeProfile({Uri? avatarUrl}) =>
      client.database.storeUserProfile(
        client.userID!,
        CachedProfileInformation.fromProfile(
          ProfileInformation(avatarUrl: avatarUrl, displayname: 'Saved Name'),
          outdated: false,
          updated: DateTime.now(),
        ),
      );

  ProfileSetupOnboardingStep newStep() => ProfileSetupOnboardingStep(
    client: client,
    state: OnboardingStateController(
      accountUpdater: MockAccountUpdater(),
      courseProvider: MockCourseProvider(),
      avatarProvider: MockAvatarProvider(),
      trialInfoProvider: MockTrialInfoProvider(),
    ),
    maxRemainingSteps: 5,
  );

  testWidgets('a restarted onboarding keeps the saved avatar', (tester) async {
    final saved = Uri.parse('mxc://fakeServer.notExisting/uploaded');
    await tester.runAsync(() => storeProfile(avatarUrl: saved));
    final step = newStep();

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrixState(client),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ProfileSetupStepView(
              step: step,
              loading: false,
              error: null,
              hasNextStep: true,
              forward: () {},
            ),
          ),
        ),
      ),
    );
    // Two zero-duration pumps: the first builds before the async localization
    // delegate resolves, the second rebuilds with L10n available and builds
    // the page, which starts loading the saved profile.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    // The saved profile is read from the client's database, which answers in
    // real time; its result is then handled on the test's fake clock.
    for (var i = 0; step.state.displayName == null && i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(step.state.displayName, 'Saved Name');
    expect(step.state.avatarInfo?.avatarUrl, saved);

    await tester.runAsync(step.execute);
    expect(FakeMatrixApi.calledEndpoints[avatarEndpoint], isNull);
  });

  // Next can come before the page has loaded the profile and picked an avatar.
  test(
    'Next before the page loads still gives a new account a preset',
    () async {
      await storeProfile();
      final step = newStep();

      await step.execute();

      final preset = MockAvatarProvider().getRandomAvatarUrl();
      final writes = FakeMatrixApi.calledEndpoints[avatarEndpoint];
      expect(writes, hasLength(1));
      expect(jsonDecode(writes!.single as String), {
        'avatar_url': preset.toString(),
      });
      expect(step.state.avatarInfo?.avatarUrl, preset);
    },
  );
}
