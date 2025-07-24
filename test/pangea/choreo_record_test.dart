import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/models/choreo_edit.dart';

void main() async {
  group("Optimized choreo record tests", () {
    test("Test that data saved in via choreo_edit can be accurately retrieved",
        () {
      const String originalText = "Aqui esta un menaje";
      const String editedText = "Aqui esta un mensaje";

      final ChoreoEdit edits = ChoreoEdit.fromText(
          originalText: originalText, editedText: editedText);
      debugPrint('Edits length: ${edits.length}');

      final retrievedText = edits.editedText(originalText);
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
