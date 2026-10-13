import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
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

/// What a course page shows about another member (#8438): their banked goal checkmarks
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
  const bigNumbersId = '@big:example.invalid';
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
      // Two digits on both counts — the widest the row gets in practice.
      bigNumbersId: profile({
        'de': LanguageAnalyticsProfileEntry(12, 0, stars: 99),
      }),
      // Studying something else: nothing published for the course's language.
      otherLanguageId: profile({
        'es': LanguageAnalyticsProfileEntry(5, 0, stars: 40),
      }),
      emptyId: PublicProfileModel(analytics: AnalyticsProfileModel()),
    });
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpStats(
    WidgetTester tester,
    String userId, {
    double textScale = 1.0,
    bool inCard = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Center(
              child: inCard
                  // The card's real geometry: a fixed box the row cannot grow.
                  ? SizedBox(
                      width: 100.0,
                      height: 20.0,
                      child: CourseMemberStats(userId: userId, langCode: 'de'),
                    )
                  // Loose, so the widget's own size is what gets measured.
                  : CourseMemberStats(userId: userId, langCode: 'de'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the goal count for the course language', (tester) async {
    await pumpStats(tester, starredId);
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('a member with a level but no goals shows no goal count', (
    tester,
  ) async {
    await pumpStats(tester, levelOnlyId);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      tester.getSize(find.byType(CourseMemberStats)).height,
      greaterThan(0),
    );
  });

  testWidgets("another language's goals are never shown for this course", (
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

  // The shield path fills its box edge to edge; a Material icon insets its
  // glyph inside its own (`Icons.check_circle` at 16 paints 12.75 of ink). So a shield
  // that reads as the mark's equal is drawn a little SMALLER than the mark's
  // nominal size — and never larger, which is what the old `iconSize + 2`
  // produced back when the number still had to fit inside it (#8918).
  testWidgets(
    'the level shield is drawn no larger than the checkmark beside it',
    (tester) async {
      await pumpStats(tester, starredId);
      final mark = tester.getSize(find.byIcon(Icons.check_circle));
      final shield = tester.getSize(find.byType(SvgPicture));
      expect(shield.height, lessThan(mark.height));
      expect(shield.height, greaterThan(mark.height * 0.7));
    },
  );

  // Moving the level number out of the shield widened the row (#8918): the
  // goal pair and the level pair now sit side by side. At normal text size
  // both must still fit the card outright, with no scale-down — the FittedBox
  // is there for large OS text sizes, not for the default one.
  testWidgets(
    'the goal count and level fit the card unscaled at normal text size',
    (tester) async {
      await pumpStats(tester, bigNumbersId, inCard: true);
      final row = find
          .descendant(of: find.byType(FittedBox), matching: find.byType(Row))
          .first;
      // getSize is the row's own layout; getRect is what the FittedBox paints.
      expect(
        tester.getRect(row).width,
        closeTo(tester.getSize(row).width, 0.01),
        reason: 'the row was scaled down to fit the card',
      );
      expect(find.text('99'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    },
  );

  // The card is ~100px wide and 20px high and cannot grow, so at large OS text
  // sizes the row has to scale down rather than overflow. iOS accessibility
  // sizes reach roughly 3x.
  testWidgets('does not overflow the card at large text scale', (tester) async {
    for (final scale in [1.5, 2.0, 3.0]) {
      await pumpStats(tester, starredId, textScale: scale, inCard: true);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflowed at textScale $scale',
      );
      expect(find.text('12'), findsOneWidget);
    }
  });
}
