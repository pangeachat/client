import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart' hide Profile;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/features/tutorials/tutorial_overlay_controller.dart';
import 'package:fluffychat/features/tutorials/tutorial_seen_backfill.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_prompt.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_prompt_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_prompt_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';
import '../tutorials/fake_tutorial_progress.dart';

/// An account with no self-identified role is asked for one when the app
/// opens, at most once a day, until it picks one (profile.instructions.md).

/// Skips `initMatrix()`: the prompt only needs a client and a navigator.
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

/// The profile has loaded; each save is recorded rather than written.
class _RecordingUserController implements UserController {
  final List<Profile> saved = [];

  @override
  Completer<void> initCompleter = Completer<void>()..complete();

  @override
  Future<void> updateProfile(
    Profile Function(Profile) update, {
    waitForDataInSync = false,
  }) async => saved.add(update(Profile(userSettings: UserSettings())));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The tutorial backfill reads the signed-in client off this.
class _ClientMatrixState extends MatrixState {
  _ClientMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

class _TestPangeaController implements PangeaController {
  _TestPangeaController(Client client)
    : matrixState = _ClientMatrixState(client);

  @override
  final MatrixState matrixState;

  @override
  final _RecordingUserController userController = _RecordingUserController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const worldTutorialsSeen = {TutorialEnum.welcome, TutorialEnum.worldMap};
  final appTutorials = MatrixState.tutorialOverlayController;

  late Client client;
  late SharedPreferences store;
  late _TestPangeaController pangeaController;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('user_type_prompt');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    // MatrixState reads the homeserver from the environment on dispose.
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    // Loading a translation is real async work, which a test body's fake
    // clock never runs.
    await lookupL10n(const Locale('en'));
  });

  setUp(() async {
    await GetStorage.init('user_type_prompt');
    await GetStorage('user_type_prompt').erase();
    MatrixState.tutorialOverlayController = TutorialOverlayController(
      progress: const FakeTutorialProgress(seen: worldTutorialsSeen),
    );
    client = await getTestClient();
    pangeaController = _TestPangeaController(client);
    MatrixState.pangeaController = pangeaController;
    // The backfill is an app-wide singleton keyed by user. Resolving it here,
    // on the real clock, keeps its future out of any one test's fake clock,
    // where a later test awaiting it would never see it complete.
    await TutorialSeenBackfill.instance.ensureResolved();
  });

  tearDown(() async {
    MatrixState.tutorialOverlayController = appTutorials;
    await client.dispose();
  });

  void setRole(UserType? role) {
    client.accountData[UserConstants.userProfile] = BasicEvent(
      type: UserConstants.userProfile,
      content: {
        UserConstants.userSettings: UserSettings(
          targetLanguage: 'es',
          selfIdentifiedRole: role,
        ).toJson(),
      },
    );
  }

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(body: UserTypePrompt()),
        ),
      ),
    );
    // L10n resolves on the fake clock; the tutorial backfill and the storage
    // reads run on real time. The two clocks take turns.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }

  Future<bool?> canAsk(WidgetTester tester) =>
      tester.runAsync(() => UserTypePromptRepo.canAsk(userId));

  testWidgets('an account with no role is asked, and what it picks is saved', (
    tester,
  ) async {
    setRole(null);
    await openApp(tester);
    expect(find.byType(UserTypePromptDialog), findsOneWidget);

    await tapAndSettle(tester, 'Teach');
    expect(find.byType(UserTypePromptDialog), findsNothing);
    expect(
      pangeaController
          .userController
          .saved
          .single
          .userSettings
          .selfIdentifiedRole,
      UserType.teacher,
    );
  });

  testWidgets('an account that has a role is not asked', (tester) async {
    setRole(UserType.student);
    await openApp(tester);
    expect(find.byType(UserTypePromptDialog), findsNothing);
  });

  testWidgets(
    'skipped: nothing is saved, and the next open that day does not ask',
    (tester) async {
      setRole(null);
      await openApp(tester);
      await tapAndSettle(tester, 'Skip for now');
      expect(find.byType(UserTypePromptDialog), findsNothing);
      expect(pangeaController.userController.saved, isEmpty);

      await closeApp(tester);
      await openApp(tester);
      expect(find.byType(UserTypePromptDialog), findsNothing);
    },
  );

  testWidgets(
    'gives way to the world-map greeting still to come, and that open does '
    'not count as the day\'s ask',
    (tester) async {
      MatrixState.tutorialOverlayController = TutorialOverlayController(
        progress: const FakeTutorialProgress(),
      );
      setRole(null);
      await openApp(tester);
      expect(find.byType(UserTypePromptDialog), findsNothing);
      expect(await canAsk(tester), isTrue);
    },
  );
}
