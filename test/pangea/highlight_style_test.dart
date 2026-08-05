import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/tokens/highlight_style.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

void main() {
  const c = Color(0xFF123456);

  group('highlightTextStyle', () {
    test('fill: false -> uses the paid-speech underline height', () {
      final s = highlightTextStyle(color: c, fill: false);
      expect(s.decoration, TextDecoration.underline);
      expect(s.decorationColor, c);
      expect(s.decorationThickness, tokenUnderlineHeight);
      expect(s.backgroundColor, isNull);
    });

    test('fill: true -> backfill only (no underline)', () {
      final s = highlightTextStyle(color: c, fill: true);
      expect(s.backgroundColor, c);
      expect(s.decoration, isNull);
      expect(s.decorationColor, isNull);
      expect(s.decorationThickness, isNull);
    });

    test('defaults to underline (fill defaults false)', () {
      expect(highlightTextStyle(color: c).decoration, TextDecoration.underline);
    });
  });

  group('highlightBox', () {
    testWidgets('draws a 12px-radius box tinted with color at alpha 50', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: highlightBox(color: c, child: const Text('hi')),
          ),
        ),
      );
      expect(find.text('hi'), findsOneWidget);
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text('hi'), matching: find.byType(DecoratedBox)),
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, c.withAlpha(50));
      expect(d.borderRadius, BorderRadius.circular(12));
    });
  });
}
