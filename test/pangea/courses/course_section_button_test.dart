import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';

/// Coverage for #8475: the course page's "see all" affordances used to be
/// primary-colored label + chevron — the same treatment as the current
/// Mission text right above them, so neither read as the clickable one. They
/// are filled buttons now, carrying the primary color as a fill instead.
///
/// And for #8744: those buttons moved out from under their section's content
/// into the section header's trailing slot, and gained a leading glyph so
/// they read as one family with the Participants section's invite button.
void main() {
  const seed = Color(0xFF6750A4);
  const width = 360.0;

  /// The button where it actually lives — its section's header — since the
  /// header is what sizes and places it.
  Future<ColorScheme> pump(
    WidgetTester tester,
    CourseSectionButton button, {
    String title = 'Chats',
    Brightness brightness = Brightness.dark,
  }) async {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: seed,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: width,
            // The sections stretch their children, so the header is what has
            // to keep the button hugging its own content.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [CourseSectionHeader(title: title, trailing: button)],
            ),
          ),
        ),
      ),
    );
    return theme.colorScheme;
  }

  testWidgets('carries the primary color as a fill, not as label color', (
    tester,
  ) async {
    final colors = await pump(
      tester,
      CourseSectionButton(
        label: 'All chats',
        icon: Icons.chat_bubble_outline,
        onPressed: () {},
      ),
    );

    final button = find.byType(FilledButton);
    final material = tester
        .widgetList<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        )
        .first;
    expect(material.color, colors.primary);

    final label = tester.renderObject<RenderParagraph>(find.text('All chats'));
    expect(label.text.style?.color, colors.onPrimary);
  });

  testWidgets('fills against the light scheme too', (tester) async {
    final colors = await pump(
      tester,
      CourseSectionButton(
        label: 'All chats',
        icon: Icons.chat_bubble_outline,
        onPressed: () {},
      ),
      brightness: Brightness.light,
    );

    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          ),
        )
        .first;
    expect(material.color, colors.primary);
  });

  testWidgets('the section glyph leads, the chevron trails (#8744)', (
    tester,
  ) async {
    await pump(
      tester,
      CourseSectionButton(
        label: 'All chats',
        icon: Icons.group_outlined,
        onPressed: () {},
      ),
    );

    double left(Finder f) => tester.getTopLeft(f).dx;
    expect(
      left(find.byIcon(Icons.group_outlined)),
      lessThan(left(find.text('All chats'))),
    );
    expect(
      left(find.text('All chats')),
      lessThan(left(find.byIcon(Icons.chevron_right))),
    );
  });

  testWidgets('sits at the end of its header, opposite the title (#8744)', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      CourseSectionButton(
        label: 'All chats',
        icon: Icons.chat_bubble_outline,
        onPressed: () => taps++,
      ),
    );

    // Same row as the title — not stacked under the section's content — and
    // flush with the section's trailing edge.
    final title = tester.getRect(find.text('Chats'));
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.left, greaterThan(title.right));
    expect(button.right, moreOrLessEquals(width, epsilon: 1.0));

    // It hugs its label rather than filling the width the header allows it —
    // a button that stretched would sit exactly at that cap.
    expect(button.width, lessThan(width * 0.7));

    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
  });

  testWidgets('a label too long for the column wraps instead of overflowing', (
    tester,
  ) async {
    await pump(
      tester,
      CourseSectionButton(
        label: 'Vollstandigen Kursplan mit allen Missionen anzeigen',
        icon: Icons.map_outlined,
        onPressed: () {},
      ),
      title: 'Vorgeschlagene Aktivitaten',
    );

    // It wraps within the share of the row the header allows it; what the
    // header must not do is paint past the section it sits in.
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CourseSectionHeader)).width,
      lessThanOrEqualTo(width),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).width,
      lessThanOrEqualTo(width),
    );
  });
}
