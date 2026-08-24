import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';
import 'package:fluffychat/routes/courses/add_course_tile_list.dart';
import 'package:fluffychat/routes/world/left_panel/course_section_header.dart';

/// Coverage for #8425: the Courses hub interleaves Invited / Teaching /
/// Learning section headers into the tile list. The list has to keep the
/// tiles' tap indices pointing at the right course once headers are mixed in,
/// keep a header whose section is fully collapsed (nothing below it, even at
/// the very end), and the header row has to announce itself and toggle.
class _StubCourseTileContent extends AddCourseTileContent {
  final String _title;

  _StubCourseTileContent(this._title);

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

  group('AddCourseTileList.sectionHeaders', () {
    testWidgets('renders headers above their section and keeps tap indices', (
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
          sectionHeaders: {
            0: const [Text('Teaching', key: Key('h-teaching'))],
            2: const [Text('Learning', key: Key('h-learning'))],
          },
        ),
      );

      // Vertical order: Teaching · Deutsch · Español · Learning · Korean.
      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(
        top(find.byKey(const Key('h-teaching'))),
        lessThan(top(find.text('Deutsch A1'))),
      );
      expect(top(find.text('Español 2')), lessThan(top(find.text('Learning'))));
      expect(
        top(find.text('Learning')),
        lessThan(top(find.text('Korean Basics'))),
      );

      // Tap indices refer to the content list, not the flattened rows.
      await tester.tap(find.text('Korean Basics'));
      await tester.tap(find.text('Deutsch A1'));
      expect(tapped, [2, 0]);
    });

    testWidgets('a header keyed past the last tile still renders', (
      tester,
    ) async {
      // A collapsed trailing section: no tiles below it, header still shown.
      await pump(
        tester,
        AddCourseTileList(
          content: [_StubCourseTileContent('Deutsch A1')],
          onTap: (_) {},
          sectionHeaders: {
            0: const [Text('Teaching')],
            1: const [Text('Learning (collapsed)')],
          },
        ),
      );

      expect(find.byType(AddCourseTile), findsOneWidget);
      expect(find.text('Learning (collapsed)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Learning (collapsed)')).dy,
        greaterThan(tester.getTopLeft(find.byType(AddCourseTile)).dy),
      );
    });

    testWidgets('consecutive collapsed sections both keep their headers', (
      tester,
    ) async {
      // Invited and Teaching both collapsed: two headers share index 0, in
      // order, above the first Learning tile.
      await pump(
        tester,
        AddCourseTileList(
          content: [_StubCourseTileContent('Korean Basics')],
          onTap: (_) {},
          sectionHeaders: {
            0: const [
              Text('Invited (collapsed)'),
              Text('Teaching (collapsed)'),
              Text('Learning'),
            ],
          },
        ),
      );

      double top(Finder f) => tester.getTopLeft(f).dy;
      expect(
        top(find.text('Invited (collapsed)')),
        lessThan(top(find.text('Teaching (collapsed)'))),
      );
      expect(
        top(find.text('Teaching (collapsed)')),
        lessThan(top(find.text('Learning'))),
      );
      expect(
        top(find.text('Learning')),
        lessThan(top(find.text('Korean Basics'))),
      );
    });

    testWidgets('no headers means the plain list', (tester) async {
      await pump(
        tester,
        AddCourseTileList(
          content: [
            _StubCourseTileContent('Deutsch A1'),
            _StubCourseTileContent('Korean Basics'),
          ],
          onTap: (_) {},
        ),
      );
      expect(find.byType(AddCourseTile), findsNWidgets(2));
    });
  });

  group('CourseSectionHeader', () {
    testWidgets('shows title and count, toggles on tap, announces state', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: CourseSectionHeader(
            title: 'Teaching',
            count: 3,
            collapsed: false,
            onTap: () => taps++,
          ),
        ),
      );

      expect(find.text('Teaching'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      await tester.tap(find.byType(CourseSectionHeader));
      expect(taps, 1);

      // Bare text + a chevron say nothing to a screen reader; the row has to.
      final context = tester.element(find.byType(CourseSectionHeader));
      final expected = L10n.of(context).courseSectionLabel('Teaching', 3);
      final semantics = tester.getSemantics(find.byType(CourseSectionHeader));
      expect(semantics.label, contains(expected));
      expect(semantics.flagsCollection.isHeader, isTrue);
      expect(semantics.flagsCollection.isExpanded, Tristate.isTrue);
    });

    testWidgets('a collapsed header reads as collapsed', (tester) async {
      await pump(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: CourseSectionHeader(
            title: 'Learning',
            count: 5,
            collapsed: true,
            onTap: () {},
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(CourseSectionHeader));
      expect(semantics.flagsCollection.isExpanded, Tristate.isFalse);
      // The chevron turns to point at the collapsed section.
      final rotation = tester.widget<AnimatedRotation>(
        find.byType(AnimatedRotation),
      );
      expect(rotation.turns, isNot(0));
    });
  });
}
