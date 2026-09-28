import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/role_badge.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';

/// Coverage for the Courses hub's tile list: the tiles are one Tab stop
/// (#9154), and a course the viewer administers wears the Admin label, which
/// its tile also announces (#9207).
class _StubCourseTileContent extends AddCourseTileContent {
  final String _title;

  @override
  final bool isAdmin;

  _StubCourseTileContent(this._title, {this.isAdmin = false});

  @override
  Room? get space => null;

  @override
  String title(L10n l10n) => _title;

  @override
  int? get members => 12;
}

void main() {
  setUpAll(() {
    // `Avatar` inside `CourseAvatar` resolves the bot name from the environment
    // at build time; initialize dotenv inline so no real `.env` is needed.
    dotenv.testLoad(fileInput: 'BOT_NAME=@bot:example.org');
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SizedBox(width: 360, height: 800, child: child)),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the tree isn't
    // built until localizations finish loading.
    await tester.pumpAndSettle();
  }

  // The tiles have no fixed count, so they are one Tab stop with the arrow
  // keys moving between them (#9154; accessibility.instructions.md, "One Tab
  // stop per list").
  testWidgets('the course tiles are one Tab stop, walked by the arrows', (
    tester,
  ) async {
    final tapped = <int>[];
    await pump(
      tester,
      AddCourseTileList(
        content: [
          _StubCourseTileContent('Deutsch A1'),
          _StubCourseTileContent('Español 2'),
          _StubCourseTileContent('Korean Basics'),
        ],
        onTap: tapped.add,
      ),
    );

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    // Tab enters on the first tile; Down moves on.
    await press(LogicalKeyboardKey.tab);
    await press(LogicalKeyboardKey.enter);
    expect(tapped, [0]);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.enter);
    expect(tapped, [0, 2]);

    // The list is one stop. It is the only one in this host, so Tab wraps
    // back to it, on the tile last focused; it never lands on the middle tile.
    await press(LogicalKeyboardKey.tab);
    await press(LogicalKeyboardKey.enter);
    expect(tapped, [0, 2, 2]);
  });

  group('Admin label', () {
    testWidgets('an administered course wears it and announces it', (
      tester,
    ) async {
      await pump(
        tester,
        AddCourseTileList(
          content: [_StubCourseTileContent('Deutsch A1', isAdmin: true)],
          onTap: (_) {},
        ),
      );

      expect(find.byType(RoleBadge), findsOneWidget);
      final l10n = L10n.of(tester.element(find.byType(RoleBadge)));
      expect(find.text(l10n.admin), findsOneWidget);
      // The label is a bare decoration inside the tile's own labeled button
      // node, so the tile says it out loud, the way it says "invited".
      final tileSemantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(AddCourseTile),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        tileSemantics.properties.label,
        'Deutsch A1, ${l10n.countParticipants(12)}, ${l10n.admin}',
      );
    });

    testWidgets('sits at the bottom-right corner of the tile', (tester) async {
      await pump(
        tester,
        AddCourseTileList(
          content: [_StubCourseTileContent('Deutsch A1', isAdmin: true)],
          onTap: (_) {},
        ),
      );

      final tile = tester.getRect(find.byType(AddCourseTile));
      final badge = tester.getRect(find.byType(RoleBadge));
      // Inside the tile's 1px border and 12px padding, flush with its
      // content's right and bottom edges.
      expect(tile.right - badge.right, 13.0);
      expect(tile.bottom - badge.bottom, lessThanOrEqualTo(13.0));
      expect(badge.center.dy, greaterThan(tile.center.dy));
    });

    testWidgets('a course the viewer does not administer has none', (
      tester,
    ) async {
      await pump(
        tester,
        AddCourseTileList(
          content: [_StubCourseTileContent('Korean Basics')],
          onTap: (_) {},
        ),
      );

      expect(find.byType(RoleBadge), findsNothing);
    });
  });
}
