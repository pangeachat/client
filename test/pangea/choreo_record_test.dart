import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/choreographer/choreo_edit_model.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_record_model.dart';

void main() async {
  group("Optimized choreo record tests", () {
    test("Test that choreo_edit parameters are accurately calculated", () {
      const String originalText = "Parameter";
      const String editedText = "Perrimeter";

      final ChoreoEditModel edits = ChoreoEditModel.fromText(
        originalText: originalText,
        editedText: editedText,
      );

      assert(edits.offset == 1 && edits.length == 3 && edits.insert == "erri");
    });

    test("Test that data saved via ChoreoEdit can be accurately retrieved", () {
      const String originalText = "step";
      const String editedText = "steps";

      final ChoreoEditModel edits = ChoreoEditModel.fromText(
        originalText: originalText,
        editedText: editedText,
      );

      final String retrieved = edits.editedText(originalText);

      assert(retrieved == editedText);
    });

    test("Test that addRecord and lastText work correctly", () {
      final List<String> steps = [];

      steps.add("");
      steps.add("Si");

      final record = ChoreoRecordModel(
        originalText: "Yes",
        choreoSteps: [],
        openMatches: [],
      );

      for (final step in steps) {
        record.addRecord(step);
      }

      assert(
        record.choreoSteps[0].edits != null &&
            record.choreoSteps[1].edits != null &&
            record.stepText() == "Si",
      );
    });

    test("Test that fromJSON receives updated version correctly", () {
      final List<String> steps = [];

      steps.add("");
      steps.add("Si");

      final record = ChoreoRecordModel(
        originalText: "Yes",
        choreoSteps: [],
        openMatches: [],
      );

      for (final step in steps) {
        record.addRecord(step);
      }

      final json = record.toJson();
      final received = ChoreoRecordModel.fromJson(json);

      assert(
        received.choreoSteps[0].edits != null &&
            received.choreoSteps[1].edits != null &&
            received.stepText() == "Si",
      );
    });

    test("suggestionStrings is in-memory only, like pastedStrings", () {
      // Send-time scoring reads the live record (#7665); neither exclusion
      // set is serialized.
      final record = ChoreoRecordModel(
        originalText: "",
        choreoSteps: [],
        openMatches: [],
      );

      expect(record.suggestionStrings, isEmpty);
      record.addSuggestionString("quiero un café");
      record.addPastedString("hola");

      final received = ChoreoRecordModel.fromJson(record.toJson());
      expect(received.suggestionStrings, isEmpty);
      expect(received.pastedStrings, isEmpty);
    });

    test("Test that fromJSON converts old version correctly", () {
      final List<String> steps = [];

      steps.add("");
      steps.add("Dos");
      steps.add("Tres");
      steps.add("");
      steps.add("Cinco");
      steps.add("Cincai");

      final record = ChoreoRecordModel(
        originalText: "One",
        choreoSteps: [],
        openMatches: [],
      );

      for (final step in steps) {
        record.addRecord(step);
      }

      final json = record.toJson();
      final received = ChoreoRecordModel.fromJson(json);

      // Initial step and steps following empty strings
      // will have text instead of edits
      assert(
        received.choreoSteps[0].edits != null &&
            received.choreoSteps[1].edits != null &&
            received.choreoSteps[2].edits != null &&
            received.choreoSteps[3].edits != null &&
            received.choreoSteps[4].edits != null &&
            received.choreoSteps[5].edits != null &&
            received.stepText() == "Cincai",
      );
    });
  });

  group("stepText replay with an inapplicable edit", () {
    // A deserialized record can carry edits measured against different text
    // than the recovered originalText, so replay must not assume they apply.
    // See Sentry CLIENT-E42.
    ChoreoRecordModel recordWith(List<ChoreoEditModel> edits) =>
        ChoreoRecordModel(
          originalText: "hello world",
          choreoSteps: edits
              .map((e) => ChoreoRecordStepModel(edits: e))
              .toList(),
          openMatches: [],
        );

    test(
      "stops at an edit reaching past the end, returning the text so far",
      () {
        // "hello world" is 11 chars; offset 18 is the production case.
        final record = recordWith([
          const ChoreoEditModel(offset: 0, length: 5, insert: "howdy"),
          const ChoreoEditModel(offset: 18, length: 2, insert: "!!"),
        ]);

        expect(record.stepText(), "howdy world");
      },
    );

    test(
      "stops at an edit whose offset is in range but whose length is not",
      () {
        final record = recordWith([
          const ChoreoEditModel(offset: 9, length: 40, insert: "x"),
        ]);

        expect(record.stepText(), "hello world");
      },
    );

    test("stops at an edit with a negative offset or length", () {
      expect(
        recordWith([
          const ChoreoEditModel(offset: -1, length: 2, insert: "x"),
        ]).stepText(),
        "hello world",
      );
      expect(
        recordWith([
          const ChoreoEditModel(offset: 0, length: -2, insert: "x"),
        ]).stepText(),
        "hello world",
      );
    });

    test("addRecord does not throw when the stored chain is inconsistent", () {
      final record = recordWith([
        const ChoreoEditModel(offset: 18, length: 2, insert: "!!"),
      ]);

      expect(() => record.addRecord("hello world!"), returnsNormally);
    });

    test("an edit landing exactly at the end still applies", () {
      // offset + length == text.length is in range, not past it — an append
      // must not be mistaken for a broken edit.
      final record = recordWith([
        const ChoreoEditModel(offset: 11, length: 0, insert: "!"),
        const ChoreoEditModel(offset: 6, length: 6, insert: "there!"),
      ]);

      expect(record.stepText(), "hello there!");
    });
  });
}
