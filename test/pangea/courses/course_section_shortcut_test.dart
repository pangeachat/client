import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';

/// Coverage for #8815: a section's shortcut (invite, create a chat) is a
/// tonal button beside "See all" — the same fill, the header's glyph size,
/// named by its tooltip — rather than the bare glyph it was, which read as
/// decoration. #9492 adds a visible label for a shortcut people missed as an
/// icon.
void main() {
  Future<void> pump(WidgetTester tester, CourseSectionShortcut shortcut) =>
      tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(body: Center(child: shortcut)),
        ),
      );

  void expectTonalFill(WidgetTester tester, Finder button) {
    final surface = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );
    expect(
      surface.color,
      Theme.of(tester.element(button)).colorScheme.secondaryContainer,
    );
  }

  testWidgets('is a tonal button, named by its tooltip, at the header glyph '
      'size', (tester) async {
    var taps = 0;
    await pump(
      tester,
      CourseSectionShortcut(
        icon: Icons.person_add_outlined,
        label: 'Invite',
        showLabel: false,
        onPressed: () => taps++,
      ),
    );

    expect(find.byTooltip('Invite'), findsOneWidget);
    expect(find.text('Invite'), findsNothing);
    expect(
      tester.getSize(find.byIcon(Icons.person_add_outlined)),
      const Size.square(CourseSectionHeader.iconSize),
    );
    expectTonalFill(tester, find.byType(IconButton));

    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });

  testWidgets('with its label shown, reads its name beside the icon, once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      CourseSectionShortcut(
        icon: Icons.add_comment_outlined,
        label: 'New course chat',
        showLabel: true,
        onPressed: () => taps++,
      ),
    );

    final button = find.byType(FilledButton);
    expect(
      find.descendant(of: button, matching: find.text('New course chat')),
      findsOneWidget,
    );
    expect(find.byTooltip('New course chat'), findsOneWidget);
    expect(
      tester.getSize(find.byIcon(Icons.add_comment_outlined)),
      const Size.square(CourseSectionHeader.iconSize),
    );
    expectTonalFill(tester, button);

    // The tooltip repeats the visible label, so it stays out of the
    // accessible name rather than having a screen reader say it twice.
    final node = tester.getSemantics(button);
    expect(node.label, 'New course chat');
    expect(node.tooltip, isEmpty);

    await tester.tap(button);
    expect(taps, 1);
    semantics.dispose();
  });
}
