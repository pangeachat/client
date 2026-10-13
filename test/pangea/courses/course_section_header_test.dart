import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';

/// Coverage for #9492: on a narrow screen every section's actions sit on their
/// own line under the title, so the sections match; on a wide screen they
/// share the title's line when they fit and move under it when they don't.
void main() {
  const narrowScreen = Size(400, 800);
  const wideScreen = Size(1200, 900);

  Future<void> pump(
    WidgetTester tester, {
    required Size screen,
    required double width,
    required bool labeledShortcut,
  }) {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CourseSectionHeader(
                title: 'Chats',
                icon: Icons.forum_outlined,
                actions: [
                  CourseSectionShortcut(
                    icon: Icons.add_comment_outlined,
                    label: 'New',
                    showLabel: labeledShortcut,
                    onPressed: () {},
                  ),
                  FilledButton.tonal(
                    onPressed: () {},
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect title(WidgetTester tester) => tester.getRect(find.text('Chats'));
  Rect seeAll(WidgetTester tester) =>
      tester.getRect(find.widgetWithText(FilledButton, 'See all'));

  void expectActionsUnderTitle(WidgetTester tester) {
    // The header's own gap, above the button's transparent tap margin.
    expect(seeAll(tester).top - title(tester).bottom, greaterThanOrEqualTo(8));
    // From the start of the header, under the section glyph.
    expect(
      tester.getRect(find.byType(CourseSectionShortcut)).left,
      lessThan(title(tester).left),
    );
  }

  testWidgets('a narrow screen puts the actions under the title, even when '
      'they would fit beside it', (tester) async {
    await pump(
      tester,
      screen: narrowScreen,
      width: 368,
      labeledShortcut: false,
    );

    expect(FluffyThemes.isColumnModeByWidth(narrowScreen.width), isFalse);
    expectActionsUnderTitle(tester);
  });

  testWidgets('a wide screen keeps title and actions on one line when they '
      'fit', (tester) async {
    const width = 700.0;
    await pump(tester, screen: wideScreen, width: width, labeledShortcut: true);

    expect(FluffyThemes.isColumnModeByWidth(wideScreen.width), isTrue);
    expect(seeAll(tester).center.dy, moreOrLessEquals(title(tester).center.dy));
    expect(seeAll(tester).right, moreOrLessEquals(width, epsilon: 1.0));
  });

  testWidgets('a wide screen moves the actions under the title when they do '
      'not fit', (tester) async {
    // The test font draws every glyph a full em wide, so both buttons outrun
    // a header this narrow.
    await pump(tester, screen: wideScreen, width: 300, labeledShortcut: true);

    expect(tester.takeException(), isNull);
    expectActionsUnderTitle(tester);
  });
}
