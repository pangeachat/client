import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_diff_spans.dart';

void main() {
  String recon(List<TextSpan> spans) => spans.map((s) => s.text ?? '').join();

  // D10 contract: the diff signal is a green/orange UNDERLINE (or BACKFILL when
  // fill:true), NOT the text color. So unchanged words carry a GREEN underline in
  // AppConfig.success (decorationColor), changed words an ORANGE underline in
  // AppConfig.warning; the text color itself stays the inherited default (null).
  test(
    'unchanged words are green-underlined separately; spaces stay plain',
    () {
      final spans = sttDiffTextSpans('hola mundo', 'hola mundo');
      expect(recon(spans), 'hola mundo');
      expect(spans.map((span) => span.text), ['hola', ' ', 'mundo']);
      expect(spans[0].style?.decorationColor, AppConfig.success);
      expect(
        spans[1].style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
      );
      expect(spans[2].style?.decorationColor, AppConfig.success);
      expect(spans[0].style?.color, isNull); // NOT green text
    },
  );

  test(
    'changed word -> ORANGE underline (warning); unchanged -> GREEN underline (success)',
    () {
      final spans = sttDiffTextSpans('ola mundo', 'hola mundo');
      expect(recon(spans), 'hola mundo');
      final changed = spans.firstWhere((s) => s.text == 'hola');
      expect(changed.style?.decoration, TextDecoration.underline);
      expect(changed.style?.decorationColor, AppConfig.warning);
      expect(changed.style?.color, isNull); // NOT orange text
      final unchanged = spans.firstWhere((s) => s.text == 'mundo');
      expect(unchanged.style?.decorationColor, AppConfig.success);
    },
  );

  test(
    'fill: true -> BACKFILL (backgroundColor) not underline, both colors',
    () {
      final spans = sttDiffTextSpans('ola mundo', 'hola mundo', fill: true);
      final changed = spans.firstWhere((s) => s.text == 'hola');
      expect(changed.style?.backgroundColor, AppConfig.warning);
      expect(
        changed.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
      );
      final unchanged = spans.firstWhere((s) => s.text == 'mundo');
      expect(unchanged.style?.backgroundColor, AppConfig.success);
    },
  );

  test('baseStyle is merged onto every run (fontSize preserved)', () {
    const base = TextStyle(fontSize: 17);
    final spans = sttDiffTextSpans('a', 'b', baseStyle: base);
    expect(spans.single.style?.fontSize, 17);
  });

  test('empty edited -> no spans', () {
    expect(sttDiffTextSpans('hola', ''), isEmpty);
  });
}
