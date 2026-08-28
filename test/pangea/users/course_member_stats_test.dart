import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/users/course_member_stats.dart';
import '../../utils/test_client.dart';

/// What a course page shows about another member (#8438): their banked stars
/// and level in THE COURSE'S language, which is not necessarily the language
/// that member is studying now.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

class _StubUserController extends UserController {
  _StubUserController(this.profiles);

  final Map<String, PublicProfileModel> profiles;

  @override
  Future<PublicProfileModel?> getPublicProfile(String userId) async =>
      profiles[userId];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const starredId = '@starred:example.invalid';
  const levelOnlyId = '@levelonly:example.invalid';
  const otherLanguageId = '@other:example.invalid';
  const emptyId = '@empty:example.invalid';

  late Client client;

  PublicProfileModel profile(
    Map<String, LanguageAnalyticsProfileEntry> analytics,
  ) => PublicProfileModel(
    analytics: AnalyticsProfileModel(
      targetLanguage: 'de',
      languageAnalytics: analytics,
    ),
  );

  setUpAll(() async {
    client = await prepareTestClient();
    SharedPreferences.setMockInitialValues({});
    MatrixState.pangeaController = PangeaController(
      matrixState: _FakeMatrixState(client),
    );
    MatrixState.pangeaController.userController = _StubUserController({
      starredId: profile({
        'de': LanguageAnalyticsProfileEntry(3, 0, stars: 12),
      }),
      levelOnlyId: profile({'de': LanguageAnalyticsProfileEntry(2, 0)}),
      // Studying something else: nothing published for the course's language.
      otherLanguageId: profile({
        'es': LanguageAnalyticsProfileEntry(5, 0, stars: 40),
      }),
      emptyId: PublicProfileModel(analytics: AnalyticsProfileModel()),
    });
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpStats(WidgetTester tester, String userId) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: CourseMemberStats(userId: userId, langCode: 'de'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the star count for the course language', (tester) async {
    await pumpStats(tester, starredId);
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('a member with a level but no stars shows no star count', (
    tester,
  ) async {
    await pumpStats(tester, levelOnlyId);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(
      tester.getSize(find.byType(CourseMemberStats)).height,
      greaterThan(0),
    );
  });

  testWidgets("another language's stars are never shown for this course", (
    tester,
  ) async {
    await pumpStats(tester, otherLanguageId);
    expect(find.text('40'), findsNothing);
    expect(tester.getSize(find.byType(CourseMemberStats)), Size.zero);
  });

  testWidgets('a member with nothing to show takes up no space', (
    tester,
  ) async {
    await pumpStats(tester, emptyId);
    expect(tester.getSize(find.byType(CourseMemberStats)), Size.zero);
  });
}
