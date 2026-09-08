import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/toolbar/message_practice/dotted_border_painter.dart';

void main() {
  group('DottedBorderPainter', () {
    final borderRadius = BorderRadius.circular(14.0);

    test('repaints when the outline colour changes', () {
      // The chosen blank turns its outline to the primary colour. The painter
      // used to answer false unconditionally, so that never reached the screen.
      final before = DottedBorderPainter(
        color: Colors.white,
        borderRadius: borderRadius,
      );
      final after = DottedBorderPainter(
        color: Colors.purple,
        borderRadius: borderRadius,
      );

      expect(after.shouldRepaint(before), isTrue);
    });

    test('repaints when the shape changes', () {
      final before = DottedBorderPainter(
        color: Colors.white,
        borderRadius: borderRadius,
      );

      expect(
        DottedBorderPainter(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4.0),
        ).shouldRepaint(before),
        isTrue,
      );
      expect(
        DottedBorderPainter(
          color: Colors.white,
          borderRadius: borderRadius,
          strokeWidth: 4.0,
        ).shouldRepaint(before),
        isTrue,
      );
    });

    test('does not repaint when nothing changed', () {
      final before = DottedBorderPainter(
        color: Colors.white,
        borderRadius: borderRadius,
      );
      final same = DottedBorderPainter(
        color: Colors.white,
        borderRadius: borderRadius,
      );

      expect(same.shouldRepaint(before), isFalse);
    });
  });
}
