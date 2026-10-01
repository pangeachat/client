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

  // #8764 — the STT diff dashes its unchanged words so the two underlines are
  // still distinguishable with colour removed (SC 1.4.1).
  group('dashed', () {
    /// Every `drawRect` the underline painter issues, in paint order.
    List<Rect> underlineRects(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(UnderlineText),
          matching: find.byType(CustomPaint),
        ),
      );
      return _RectSpy.record(paint.painter!, const Size(200, 40));
    }

    testWidgets('solid draws one continuous rule per line', (tester) async {
      await tester.pumpWidget(host(Colors.green));
      expect(underlineRects(tester), hasLength(1));
    });

    testWidgets('dashed breaks the same rule into several dashes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnderlineText(
              text: 'palabra',
              style: const TextStyle(fontSize: 16),
              underlineColor: Colors.green,
              dashed: true,
            ),
          ),
        ),
      );
      final dashes = underlineRects(tester);
      expect(dashes.length, greaterThan(1));

      // The dashes span the same run the solid rule would, and none overhangs
      // the word's end.
      final solid = Rect.fromLTRB(
        dashes.first.left,
        dashes.first.top,
        dashes.last.right,
        dashes.first.bottom,
      );
      expect(dashes.every((d) => d.right <= solid.right + 0.01), isTrue);
      expect(dashes.every((d) => d.top == solid.top), isTrue);

      // Gaps, not a butted-up run of rects — otherwise it reads as solid.
      expect(dashes[1].left, greaterThan(dashes[0].right));
    });
  });
}

/// Captures the rects a [CustomPainter] draws, so the dash geometry can be
/// asserted without a golden file.
class _RectSpy implements Canvas {
  final List<Rect> rects = [];

  static List<Rect> record(CustomPainter painter, Size size) {
    final spy = _RectSpy();
    painter.paint(spy, size);
    return spy.rects;
  }

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
