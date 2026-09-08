import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_shortcut.dart';

/// Coverage for #8815: a section's shortcut (invite, create a chat) is a
/// tonal button beside "See all" — the same fill, the header's glyph size,
/// named by its tooltip — rather than the bare glyph it was, which read as
/// decoration.
void main() {
  testWidgets('is a tonal button, named by its tooltip, at the header glyph '
      'size', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: CourseSectionShortcut(
              icon: Icons.person_add_outlined,
              tooltip: 'Invite',
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Invite'), findsOneWidget);
    expect(
      tester.getSize(find.byIcon(Icons.person_add_outlined)),
      const Size.square(CourseSectionHeader.iconSize),
    );

    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(IconButton),
            matching: find.byType(Material),
          )
          .first,
    );
    final colors = Theme.of(
      tester.element(find.byType(IconButton)),
    ).colorScheme;
    expect(surface.color, colors.secondaryContainer);

    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });
}
