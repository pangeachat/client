import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';

/// Coverage for #8475: the course page's "see all" affordances used to be
/// primary-colored label + chevron — the same treatment as the current
/// Mission text right above them, so neither read as the clickable one. They
/// are filled buttons now, carrying the primary color as a fill instead.
void main() {
  const seed = Color(0xFF6750A4);

  Future<ColorScheme> pump(
    WidgetTester tester,
    Widget child, {
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
            width: 360,
            // The sections stretch their children, so the button has to hug
            // its own content rather than inherit the card's full width.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [child],
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
      CourseSectionButton(label: 'See full course plan', onPressed: () {}),
    );

    final button = find.byType(FilledButton);
    final material = tester
        .widgetList<Material>(
          find.descendant(of: button, matching: find.byType(Material)),
        )
        .first;
    expect(material.color, colors.primary);

    final label = tester.renderObject<RenderParagraph>(
      find.text('See full course plan'),
    );
    expect(label.text.style?.color, colors.onPrimary);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('fills against the light scheme too', (tester) async {
    final colors = await pump(
      tester,
      CourseSectionButton(label: 'All chats', onPressed: () {}),
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

  testWidgets('hugs its content and reports the tap', (tester) async {
    var taps = 0;
    await pump(
      tester,
      CourseSectionButton(label: 'All chats', onPressed: () => taps++),
    );

    expect(tester.getSize(find.byType(FilledButton)).width, lessThan(360));
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
  });

  testWidgets('a trailing indicator rides inside the button', (tester) async {
    await pump(
      tester,
      CourseSectionButton(
        label: 'See full course plan',
        onPressed: () {},
        trailing: const Icon(Icons.notifications_outlined, key: Key('badge')),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byKey(const Key('badge')),
      ),
      findsOneWidget,
    );
    // The chevron stays between the label and the indicator.
    double left(Finder f) => tester.getTopLeft(f).dx;
    expect(
      left(find.text('See full course plan')),
      lessThan(left(find.byIcon(Icons.chevron_right))),
    );
    expect(
      left(find.byIcon(Icons.chevron_right)),
      lessThan(left(find.byKey(const Key('badge')))),
    );
  });

  testWidgets('a label too long for the column wraps instead of overflowing', (
    tester,
  ) async {
    await pump(
      tester,
      CourseSectionButton(
        label: 'Vollstandigen Kursplan mit allen Missionen anzeigen',
        onPressed: () {},
      ),
    );

    // It grows to the column and wraps; what it must not do is paint past it.
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FilledButton)).width,
      lessThanOrEqualTo(360),
    );
  });
}
