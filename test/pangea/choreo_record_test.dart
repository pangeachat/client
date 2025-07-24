import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:bsdiff/bsdiff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  group("Optimized choreo record tests", () {
    test("Test that data saved in patches can be accurately retrieved", () {
      const String originalText = "a";
      const String editedText = "a";
      debugPrint('Original message length: ${originalText.length}');
      debugPrint('Edited message length: ${editedText.length}');

      final Uint8List edits =
          bsdiff(utf8.encode(originalText), utf8.encode(editedText));
      debugPrint('Edits length: ${edits.length}');

      final retrievedText =
          utf8.decode(bspatch(utf8.encode(originalText), edits));
      debugPrint('Retrieved text: $retrievedText');
      expect(
        retrievedText,
        equals(editedText),
        reason:
            'Applying edits to the original text should produce the entire edited message',
      );
    });
  });
}
