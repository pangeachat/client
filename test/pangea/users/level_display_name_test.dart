import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/level_display_name.dart';
import '../../utils/test_client.dart';

/// Regression coverage for #8238 ("Don't reserve space below activeness status
/// in profile"): the bot has no language pair and no level, but the chip padded
/// itself and drew a spacer regardless, so every profile that showed it kept a
/// band of empty space for a widget that was never there.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Stands in for the network fetch, which is all [LevelDisplayName] uses the
/// controller for.
class _StubUserController extends UserController {
  _StubUserController(this.profiles);

  final Map<String, PublicProfileModel> profiles;

  @override
  Future<PublicProfileModel?> getPublicProfile(String userId) async =>
      profiles[userId];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const botId = '@bot:example.invalid';
  const learnerId = '@learner:example.invalid';
  const unknownId = '@unknown:example.invalid';

  final english = LanguageModel(langCode: 'en', displayName: 'English');
  final german = LanguageModel(langCode: 'de', displayName: 'German');

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
    // The controller builds a PLanguageStore, which reads its cache from
    // shared preferences on construction.
    SharedPreferences.setMockInitialValues({});
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    MatrixState.pangeaController.userController = _StubUserController({
      // What the bot and any account that hasn't started learning resolve to.
      botId: PublicProfileModel(analytics: AnalyticsProfileModel()),
      learnerId: PublicProfileModel(
        analytics: AnalyticsProfileModel(
          baseLanguage: english,
          targetLanguage: german,
          languageAnalytics: {german: LanguageAnalyticsProfileEntry(2, 0)},
        ),
      ),
    });
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpChip(WidgetTester tester, String userId) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // Loose constraints, like the column of profile lines the chip sits
          // in — so its own size is what's measured.
          body: Center(
            child: LevelDisplayName(userId: userId, showFlags: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a profile with nothing learned takes up no space', (
    tester,
  ) async {
    await pumpChip(tester, botId);
    expect(tester.getSize(find.byType(LevelDisplayName)), Size.zero);
  });

  testWidgets('a profile that fails to resolve takes up no space', (
    tester,
  ) async {
    await pumpChip(tester, unknownId);
    expect(tester.getSize(find.byType(LevelDisplayName)), Size.zero);
  });

  testWidgets('a learner still gets the language pair and level', (
    tester,
  ) async {
    await pumpChip(tester, learnerId);
    expect(
      tester.getSize(find.byType(LevelDisplayName)).height,
      greaterThan(0),
    );
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
