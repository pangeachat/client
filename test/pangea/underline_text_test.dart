import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

/// #8426 — a fully transparent underline (the common case for ordinary
/// tokens) must not build the CustomPaint whose painter re-lays-out the
/// text; a visible underline must still paint.
void main() {
  Widget host(Color? underlineColor) => MaterialApp(
    home: Scaffold(
      body: UnderlineText(
        text: 'palabra',
        style: const TextStyle(fontSize: 16),
        underlineColor: underlineColor,
      ),
    ),
  );

  testWidgets('transparent underline renders text without a CustomPaint', (
    tester,
  ) async {
    await tester.pumpWidget(host(Colors.white.withAlpha(0)));
    expect(find.text('palabra', findRichText: true), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UnderlineText),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('null underline color also skips the CustomPaint', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));
    expect(find.text('palabra', findRichText: true), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UnderlineText),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('a visible underline still paints', (tester) async {
    await tester.pumpWidget(host(Colors.green.withAlpha(200)));
    expect(find.text('palabra', findRichText: true), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UnderlineText),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
