import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_button.dart';
import 'package:fluffychat/routes/chat/chat_details/course_overview/course_section_header.dart';

/// Coverage for #8744: every course-page section's full-page link moved out
/// from under the section's content into its header, opposite the title, and
/// every one of them now reads the same "See all" — the header beside it
/// names the section. A screen reader has no such adjacency, so the section
/// has to reach the accessible name instead, or four buttons speak alike.
void main() {
  const width = 360.0;

  /// The button where it actually lives — its section's header — since the
  /// header is what sizes and places it.
  Future<void> pump(
    WidgetTester tester,
    CourseSectionButton button, {
    String title = 'Chats',
    IconData? icon,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            width: width,
            // The sections stretch their children, so the header is what has
            // to keep the button hugging its own content.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CourseSectionHeader(title: title, icon: icon, trailing: button),
              ],
            ),
          ),
        ),
      ),
    );
    // L10n's delegate resolves from a deferred library, so the tree isn't
    // built until localizations finish loading.
    await tester.pumpAndSettle();
  }

  testWidgets('reads "See all", and says which section to a screen reader', (
    tester,
  ) async {
    await pump(
      tester,
      const CourseSectionButton(section: 'Chats', onPressed: _noop),
      title: 'Chats',
    );

    expect(find.text('See all'), findsOneWidget);
    // The visible label stays short; the accessible name carries it plus the
    // section, so it still contains what a sighted user reads.
    final semantics = tester.getSemantics(find.byType(TextButton));
    expect(semantics.label, contains('See all Chats'));
  });

  testWidgets('is a text link, not a filled pill', (tester) async {
    await pump(
      tester,
      const CourseSectionButton(section: 'Chats', onPressed: _noop),
    );

    // #8475 made these filled so they wouldn't read as the Mission text
    // right above them; in the header there is no such neighbour, and Will's
    // #8744 review asked for the lighter treatment back.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('sits at the end of its header, opposite the title', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      CourseSectionButton(section: 'Chats', onPressed: () => taps++),
    );

    // Same row as the title — not stacked under the section's content — and
    // flush with the section's trailing edge.
    final title = tester.getRect(find.text('Chats'));
    final button = tester.getRect(find.byType(TextButton));
    expect(button.left, greaterThan(title.right));
    expect(button.right, moreOrLessEquals(width, epsilon: 1.0));

    // It hugs its label rather than filling the width the header allows it —
    // a button that stretched would sit exactly at that cap.
    expect(button.width, lessThan(width * 0.7));

    await tester.tap(find.byType(TextButton));
    expect(taps, 1);
  });

  testWidgets('the section glyph leads the header, before the title', (
    tester,
  ) async {
    await pump(
      tester,
      const CourseSectionButton(section: 'Chats', onPressed: _noop),
      icon: Icons.forum_outlined,
    );

    // The glyph stands for the section, so it rides the header rather than
    // any one control in it (#8744).
    expect(
      tester.getTopLeft(find.byIcon(Icons.forum_outlined)).dx,
      lessThan(tester.getTopLeft(find.text('Chats')).dx),
    );
  });

  testWidgets('a long localized header does not overflow its section', (
    tester,
  ) async {
    await pump(
      tester,
      const CourseSectionButton(
        section: 'Vorgeschlagene Aktivitaten',
        onPressed: _noop,
      ),
      title: 'Vorgeschlagene Aktivitaten',
      icon: Icons.assignment_outlined,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CourseSectionHeader)).width,
      lessThanOrEqualTo(width),
    );
  });
}

void _noop() {}
