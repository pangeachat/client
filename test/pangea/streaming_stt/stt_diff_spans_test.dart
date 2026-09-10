import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/stt_diff_spans.dart';

void main() {
  String recon(List<TextSpan> spans) => spans.map((s) => s.text ?? '').join();

  // Sentinels, not the real constants: which colour each run wears is the
  // CALLER's decision now (it is theme-dependent, #8764), so what this function
  // owes is faithful pass-through.
  const changedColor = Color(0xFF112233);
  const unchangedColor = Color(0xFF445566);

  List<TextSpan> spansFor(
    String original,
    String edited, {
    bool fill = false,
  }) => sttDiffTextSpans(
    original,
    edited,
    fill: fill,
    changedColor: changedColor,
    unchangedColor: unchangedColor,
  );

  // D10 contract: the diff signal is a green/orange UNDERLINE (or BACKFILL when
  // fill:true), NOT the text color. So unchanged words carry the unchanged
  // colour as decorationColor, changed words the changed one; the text color
  // itself stays the inherited default (null).
  test(
    'unchanged words are green-underlined separately; spaces stay plain',
    () {
      final spans = spansFor('hola mundo', 'hola mundo');
      expect(recon(spans), 'hola mundo');
      expect(spans.map((span) => span.text), ['hola', ' ', 'mundo']);
      expect(spans[0].style?.decorationColor, unchangedColor);
      expect(
        spans[1].style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
      );
      expect(spans[2].style?.decorationColor, unchangedColor);
      expect(spans[0].style?.color, isNull); // NOT green text
    },
  );

  test(
    'changed word -> ORANGE underline (warning); unchanged -> GREEN underline (success)',
    () {
      final spans = spansFor('ola mundo', 'hola mundo');
      expect(recon(spans), 'hola mundo');
      final changed = spans.firstWhere((s) => s.text == 'hola');
      expect(changed.style?.decoration, TextDecoration.underline);
      expect(changed.style?.decorationColor, changedColor);
      expect(changed.style?.color, isNull); // NOT orange text
      final unchanged = spans.firstWhere((s) => s.text == 'mundo');
      expect(unchanged.style?.decorationColor, unchangedColor);
    },
  );

  // SC 1.4.1: with colour removed the two runs must still differ.
  test('unchanged runs are DASHED and changed runs SOLID', () {
    final spans = spansFor('ola mundo', 'hola mundo');
    final changed = spans.firstWhere((s) => s.text == 'hola');
    final unchanged = spans.firstWhere((s) => s.text == 'mundo');
    expect(changed.style?.decorationStyle, TextDecorationStyle.solid);
    expect(unchanged.style?.decorationStyle, TextDecorationStyle.dashed);
    expect(
      changed.style?.decorationStyle,
      isNot(unchanged.style?.decorationStyle),
    );
  });

  test(
    'fill: true -> BACKFILL (backgroundColor) not underline, both colors',
    () {
      final spans = spansFor('ola mundo', 'hola mundo', fill: true);
      final changed = spans.firstWhere((s) => s.text == 'hola');
      expect(changed.style?.backgroundColor, changedColor);
      expect(
        changed.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
      );
      // No underline to style when the run is a backfill.
      expect(changed.style?.decorationStyle, isNull);
      final unchanged = spans.firstWhere((s) => s.text == 'mundo');
      expect(unchanged.style?.backgroundColor, unchangedColor);
      expect(unchanged.style?.decorationStyle, isNull);
    },
  );

  test('baseStyle is merged onto every run (fontSize preserved)', () {
    const base = TextStyle(fontSize: 17);
    final spans = sttDiffTextSpans(
      'a',
      'b',
      baseStyle: base,
      changedColor: changedColor,
      unchangedColor: unchangedColor,
    );
    expect(spans.single.style?.fontSize, 17);
  });

  test('empty edited -> no spans', () {
    expect(spansFor('hola', ''), isEmpty);
  });
}
