import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/users/about_me_display.dart';

/// Regression coverage for #7117 ("About me goes out of Profile Box"): a long
/// about-me must wrap within the profile box and scroll, not overflow it. The
/// old layout put the text in a Row (unbounded width), so a long bio rendered as
/// one wide line that spilled out of the box.
void main() {
  testWidgets('a long about wraps within a narrow box without overflowing', (
    tester,
  ) async {
    final longAbout = List.generate(80, (i) => 'word$i').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AboutMeText(about: longAbout, textSize: 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No RenderFlex overflow (the old Row overflowed on a long bio).
    expect(tester.takeException(), isNull);
    final text = find.text(longAbout);
    expect(text, findsOneWidget);
    // Wrapped: the text lays out within the box width rather than one long line.
    expect(tester.getSize(text).width, lessThanOrEqualTo(200.0));
  });

  testWidgets('a short about renders without scrolling issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: AboutMeText(about: 'hi', textSize: 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('hi'), findsOneWidget);
  });
}
