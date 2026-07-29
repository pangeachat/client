import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/invited_course_badge.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';

/// Coverage for #7636: a course the learner has been *invited* to must read as
/// an invitation, not as an error. In the courses list that means a gold
/// "Invited" chip and an envelope glyph — never the error-colored warning badge
/// the state used to borrow.
class _StubCourseTileContent extends AddCourseTileContent {
  @override
  final bool invited;

  final int? memberCount;

  _StubCourseTileContent({required this.invited, this.memberCount = 12});

  @override
  String title(L10n l10n) => 'Elementary German I';

  @override
  int? get members => memberCount;

  @override
  Future<Event?>? get unreadCoursePingEvent => Future.value(null);

  @override
  Set<String?> get courseChildrenIds => const {};
}

void main() {
  setUpAll(() {
    // `Avatar` inside `CourseAvatar` resolves the bot name from the environment
    // at build time; initialize dotenv inline so no real `.env` is needed.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  Future<void> pumpTile(WidgetTester tester, {required bool invited}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              child: AddCourseTile(
                content: _StubCourseTileContent(invited: invited),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the tile isn't in
    // the tree until localizations finish loading.
    await tester.pumpAndSettle();
  }

  testWidgets('invited course shows a gold Invited chip', (tester) async {
    await pumpTile(tester, invited: true);

    final context = tester.element(find.byType(AddCourseTile));
    final l10n = L10n.of(context);

    final chip = tester.widget<CourseInfoChip>(
      find.byWidgetPredicate(
        (w) => w is CourseInfoChip && w.text == l10n.invited,
      ),
    );

    expect(chip.icon, Icons.mail);
    expect(chip.highlightColor, AppConfig.goldByTheme(context));
    expect(
      chip.foregroundColor,
      AppConfig.onGoldByTheme(context),
      reason: 'gold is a light fill; the label needs dark ink to stay legible',
    );
  });

  testWidgets('invited course badge is gold and envelope-shaped, not an error', (
    tester,
  ) async {
    await pumpTile(tester, invited: true);

    expect(find.byType(InvitedCourseBadge), findsOneWidget);

    final context = tester.element(find.byType(AddCourseTile));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(InvitedCourseBadge),
        matching: find.byType(Icon),
      ),
    );

    expect(icon.icon, Icons.mail);
    expect(icon.icon, isNot(Icons.error_outline));
    expect(icon.color, AppConfig.onGoldByTheme(context));
    expect(
      icon.color,
      isNot(Theme.of(context).colorScheme.error),
      reason: 'an invitation is an opportunity, not a problem (#7636)',
    );
  });

  testWidgets('invited state is announced instead of the participant count', (
    tester,
  ) async {
    await pumpTile(tester, invited: true);

    final context = tester.element(find.byType(AddCourseTile));
    final l10n = L10n.of(context);

    final semantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(AddCourseTile),
            matching: find.byType(Semantics),
          )
          .first,
    );

    expect(semantics.properties.label, contains(l10n.invited));
    expect(
      semantics.properties.label,
      isNot(contains(l10n.countParticipants(12))),
      reason: 'the member chip is hidden while invited, so do not announce it',
    );
  });

  // The joined branch of the tile renders `UnreadRoomsBadge`, which needs a
  // `Provider<MatrixState>` this change doesn't touch — so the chip's own
  // contract is covered directly instead of through a fully-mounted tile.
  testWidgets('chip paints icon and text with the given foreground', (
    tester,
  ) async {
    const ink = Color(0xFF123456);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CourseInfoChip(
            icon: Icons.mail,
            text: 'Invited',
            fontSize: 12.0,
            iconSize: 12.0,
            highlightColor: AppConfig.gold,
            foregroundColor: ink,
          ),
        ),
      ),
    );

    expect(tester.widget<Icon>(find.byIcon(Icons.mail)).color, ink);
    expect(tester.widget<Text>(find.text('Invited')).style?.color, ink);
  });
}
