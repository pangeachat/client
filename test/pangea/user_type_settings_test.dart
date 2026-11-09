import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' show Client;

import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/user_type_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/test_client.dart';
import 'onboarding_tests/seed_language_store.dart';

class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Any account can set or change its self-identified role in learning
/// settings, the same value onboarding saves (profile.instructions.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;

  setUpAll(() async {
    await seedLanguageStore();
    // The view model listens to the user controller's profile streams.
    client = await prepareTestClient();
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    // Loading a translation is real async work, which a test body's fake
    // clock never runs.
    await lookupL10n(const Locale('en'));
  });

  tearDownAll(() => client.dispose());

  testWidgets('a role picked in settings is what the page saves', (_) async {
    var saves = 0;
    final viewModel = LearningSettingsViewModel(
      Profile(
        userSettings: UserSettings(sourceLanguage: 'en', targetLanguage: 'es'),
      ),
      onUpdateProfile: () => saves++,
    );
    addTearDown(viewModel.dispose);
    expect(viewModel.userType, isNull);

    viewModel.setUserType(UserType.student);
    expect(
      viewModel.updatedProfile.userSettings.selfIdentifiedRole,
      UserType.student,
    );
    expect(saves, 1);

    viewModel.setUserType(UserType.teacher);
    expect(
      viewModel.updatedProfile.userSettings.selfIdentifiedRole,
      UserType.teacher,
    );
    expect(saves, 2);
  });

  Future<void> pumpDropdown(
    WidgetTester tester, {
    required UserType? userType,
    required ValueChanged<UserType> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: UserTypeDropdown(userType: userType, onChanged: onChanged),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an account with no role sees none chosen, and can pick one', (
    tester,
  ) async {
    UserType? picked;
    await pumpDropdown(tester, userType: null, onChanged: (t) => picked = t);
    expect(find.text('I use Pangea Chat to'), findsOneWidget);
    expect(find.text('Teach'), findsNothing);
    expect(find.text('Learn'), findsNothing);

    await tester.tap(find.byType(UserTypeDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn').last);
    await tester.pumpAndSettle();
    expect(picked, UserType.student);
  });

  testWidgets('shows the saved role', (tester) async {
    await pumpDropdown(tester, userType: UserType.teacher, onChanged: (_) {});
    expect(find.text('Teach'), findsOneWidget);
  });
}
