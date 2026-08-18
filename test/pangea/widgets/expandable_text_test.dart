import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/expandable_text.dart';

/// The course page's description control (#8357): text within the line cap
/// renders plainly; overflowing text collapses with an inline "Show more"
/// that expands in place to the full text with an inline "Show less".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shortText = 'A short description.';
  // Long enough to overflow two lines at 320px, short enough that the
  // expanded text (and its inline "Show less") stays on the test surface —
  // tapOnText can only hit visible ranges.
  final longText = List.filled(8, 'many words that wrap').join(' ');

  Future<BuildContext> pump(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SizedBox(width: 320, child: ExpandableText(text))),
      ),
    );
    await tester.pumpAndSettle();
    return tester.element(find.byType(ExpandableText));
  }

  testWidgets('text within the cap renders with no toggle', (tester) async {
    final context = await pump(tester, shortText);
    final l10n = L10n.of(context);

    expect(find.text(shortText), findsOneWidget);
    expect(find.textContaining(l10n.showMore), findsNothing);
    expect(find.textContaining(l10n.showLess), findsNothing);
  });

  testWidgets('overflowing text truncates and toggles open and closed', (
    tester,
  ) async {
    final context = await pump(tester, longText);
    final l10n = L10n.of(context);

    // Collapsed: a cut of the text plus the inline "Show more" tail.
    expect(find.textContaining(l10n.showMore), findsOneWidget);
    expect(find.textContaining(longText), findsNothing);

    // Expand: the full text with an inline "Show less".
    await tester.tapOnText(find.textRange.ofSubstring(l10n.showMore));
    await tester.pumpAndSettle();
    expect(find.textContaining(longText), findsOneWidget);
    expect(find.textContaining(l10n.showLess), findsOneWidget);

    // Collapse again.
    await tester.tapOnText(find.textRange.ofSubstring(l10n.showLess));
    await tester.pumpAndSettle();
    expect(find.textContaining(l10n.showMore), findsOneWidget);
    expect(find.textContaining(longText), findsNothing);
  });
}
