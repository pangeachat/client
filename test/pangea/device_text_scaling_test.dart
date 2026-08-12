import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/tokens/token_rendering_util.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

/// #7719 — the app has no font-size setting of its own; the device's text-size
/// setting is the single source of text size.
///
/// `RichText` and `TextPainter` both default to `TextScaler.noScaling`, so
/// neither sees the device setting unless it is passed one explicitly. Token
/// text is rendered by a `RichText` and underlined from a *separate*
/// `TextPainter` layout of the same span, so the two must agree — if they
/// disagree, every word underline lands off its word.
void main() {
  Future<void> pumpAt(WidgetTester tester, double scale, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  const style = TextStyle(fontSize: 16, color: Colors.black);

  testWidgets('token text grows with the device text scaler', (tester) async {
    await pumpAt(tester, 1.0, const UnderlineText(text: 'hello', style: style));
    final normal = tester.getSize(find.byType(RichText).first);

    await pumpAt(tester, 2.0, const UnderlineText(text: 'hello', style: style));
    final large = tester.getSize(find.byType(RichText).first);

    expect(
      large.height,
      greaterThan(normal.height),
      reason:
          'RichText defaults to noScaling; it must be passed the '
          'device scaler explicitly',
    );
    expect(large.width, greaterThan(normal.width));
  });

  /// Width of the drawn underline, in pixels, measured off the rendered
  /// image. The bar is painted behind the glyphs, so [UnderlineText.gap]
  /// pushes it clear of them and it can be found by colour alone.
  Future<double> underlineWidth(WidgetTester tester, double scale) async {
    await pumpAt(
      tester,
      scale,
      const UnderlineText(
        text: 'hello',
        style: style,
        underlineColor: Color(0xFFFF0000),
        gap: 40,
        underlineHeight: 4,
      ),
    );

    final image = await tester.binding.runAsync(
      () async =>
          (await (find
                      .ancestor(
                        of: find.byType(RichText).first,
                        matching: find.byType(RepaintBoundary),
                      )
                      .evaluate()
                      .first
                      .renderObject!
                  as RenderRepaintBoundary)
              .toImage()),
    );
    final data = await tester.binding.runAsync(
      () async => image!.toByteData(format: ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();

    var minX = image!.width, maxX = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        if (bytes[i] > 200 && bytes[i + 1] < 80 && bytes[i + 2] < 80) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    return maxX < 0 ? 0 : (maxX - minX + 1).toDouble();
  }

  testWidgets('the underline is drawn the width of the scaled text', (
    tester,
  ) async {
    // The painter lays the span out itself, separately from the RichText that
    // draws the word. Give the two different scalers and the bar runs short of
    // its word — the #7719 regression. Measuring the drawn pixels is the only
    // check that catches a painter-side mistake; comparing widget boxes does
    // not, because CustomPaint simply takes its child's size either way.
    final normal = await underlineWidth(tester, 1.0);
    final large = await underlineWidth(tester, 2.0);

    expect(normal, greaterThan(0), reason: 'no underline was drawn at all');
    expect(
      large / normal,
      closeTo(2.0, 0.15),
      reason: 'the underline must track the text width across scales',
    );
  });

  test('the token width cache is keyed by scale, not just font size', () {
    final util = TokenRenderingUtil();

    final atOne = util.tokenTextWidthForContainer(
      'hello',
      Colors.black,
      style,
      16,
      TextScaler.noScaling,
    );
    final atTwo = util.tokenTextWidthForContainer(
      'hello',
      Colors.black,
      style,
      16,
      const TextScaler.linear(2.0),
    );

    expect(
      atTwo,
      greaterThan(atOne),
      reason:
          'same text and fontSize at a different scale must not hit the '
          'cached width measured at the old scale',
    );
  });
}
