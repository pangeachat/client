import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/text_editing/pangea_text_controller.dart';
import 'package:fluffychat/routes/chat/events/tokens/highlight_style.dart';
import 'package:fluffychat/routes/chat/events/tokens/underline_text_widget.dart';

void main() {
  const c = Color(0xFF123456);

  group('PangeaTextController underline-style parity', () {
    test('preserves the deployed composer underline thickness at 5px', () {
      final notSelected = PangeaTextController.underlineStyleForTesting(
        c,
        false,
      );
      expect(notSelected.decoration, TextDecoration.underline);
      expect(notSelected.decorationColor, c);
      expect(notSelected.decorationThickness, 5.0);
      expect(notSelected.backgroundColor, isNull);

      final selected = PangeaTextController.underlineStyleForTesting(c, true);
      expect(selected.backgroundColor, c);
      expect(selected.decoration, isNull);
      expect(selected.decorationColor, isNull);
      expect(selected.decorationThickness, isNull);
    });

    test('shared paid-TTS/read-aloud token highlight remains 3px', () {
      expect(tokenUnderlineHeight, 3.0);
      expect(
        highlightTextStyle(color: c, fill: false).decorationThickness,
        3.0,
      );
    });
  });
}
