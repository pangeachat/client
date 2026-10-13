import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';

/// Coverage for #9492: a section's title and actions share a line when they
/// fit, and the actions move under the title when they don't, instead of
/// overflowing a narrow phone's header.
void main() {
  Future<void> pump(WidgetTester tester, double width) => tester.pumpWidget(
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
                  label: 'New course chat',
                  showLabel: true,
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

  Rect title(WidgetTester tester) => tester.getRect(find.text('Chats'));
  Rect seeAll(WidgetTester tester) =>
      tester.getRect(find.widgetWithText(FilledButton, 'See all'));
  Rect shortcut(WidgetTester tester) =>
      tester.getRect(find.widgetWithText(FilledButton, 'New course chat'));

  testWidgets('title and actions share a line when they fit', (tester) async {
    const width = 700.0;
    await pump(tester, width);

    expect(shortcut(tester).left, greaterThan(title(tester).right));
    expect(
      shortcut(tester).center.dy,
      moreOrLessEquals(title(tester).center.dy),
    );
    expect(seeAll(tester).right, moreOrLessEquals(width, epsilon: 1.0));
  });

  testWidgets('actions move under the title when they do not fit', (
    tester,
  ) async {
    // The test font draws every glyph a full em wide, so the label alone
    // outruns a phone-width header.
    await pump(tester, 360);

    expect(tester.takeException(), isNull);
    expect(shortcut(tester).top, greaterThanOrEqualTo(title(tester).bottom));
    expect(seeAll(tester).top, greaterThanOrEqualTo(title(tester).bottom));
    // Under the title, from the start of the header.
    expect(shortcut(tester).left, lessThan(title(tester).left));
  });
}
