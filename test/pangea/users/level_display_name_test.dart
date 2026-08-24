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
  int fetchCount = 0;

  @override
  Future<PublicProfileModel?> getPublicProfile(String userId) async {
    fetchCount++;
    return profiles[userId];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const botId = '@bot:example.invalid';
  const learnerId = '@learner:example.invalid';
  const unknownId = '@unknown:example.invalid';

  final english = LanguageModel(langCode: 'en', displayName: 'English');
  final german = LanguageModel(langCode: 'de', displayName: 'German');

  late Client client;
  late _StubUserController stubController;

  setUpAll(() async {
    client = await prepareTestClient();
    // The controller builds a PLanguageStore, which reads its cache from
    // shared preferences on construction.
    SharedPreferences.setMockInitialValues({});
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    stubController = _StubUserController({
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
    MatrixState.pangeaController.userController = stubController;
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

  /// Regression for #8513: the invite page rebuilds this chip (among other
  /// widgets) on every room-state event. When it was a StatelessWidget, a
  /// fresh Future was built every rebuild, so FutureBuilder reset to
  /// "waiting" and re-hit the network on each one — a spinner flash for
  /// every visible row, every time. Converting to a StatefulWidget that
  /// fetches once and only refetches when userId actually changes fixes
  /// both: no redundant network calls, and no loading-state flash on an
  /// unrelated parent rebuild.
  testWidgets(
    'an unrelated parent rebuild does not refetch or flash back to loading',
    (tester) async {
      stubController.fetchCount = 0;
      final rebuild = ValueNotifier(0);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<int>(
                valueListenable: rebuild,
                builder: (context, _, child) =>
                    LevelDisplayName(userId: learnerId, showFlags: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(stubController.fetchCount, 1);
      expect(find.text('EN'), findsOneWidget);

      // Simulate the invite page's shared StreamBuilder rebuilding this
      // subtree for an unrelated reason (e.g. another row's membership
      // changed).
      rebuild.value++;
      await tester.pump();

      // No refetch, and no reversion to the loading spinner mid-rebuild.
      expect(stubController.fetchCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('EN'), findsOneWidget);
    },
  );
}
