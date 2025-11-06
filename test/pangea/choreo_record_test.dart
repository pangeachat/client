import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/choreographer/choreo_edit_model.dart';
import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';

void main() async {
  group("Optimized choreo record tests", () {
    test("Test that choreo_edit parameters are accurately calculated", () {
      const String originalText = "Parameter";
      const String editedText = "Perrimeter";

      final ChoreoEditModel edits = ChoreoEditModel.fromText(
        originalText: originalText,
        editedText: editedText,
      );

      assert(
        edits.offset == 1 && edits.length == 3 && edits.insert == "erri",
      );
    });

    test("Test that data saved via ChoreoEdit can be accurately retrieved", () {
      const String originalText = "step";
      const String editedText = "steps";

      final ChoreoEditModel edits = ChoreoEditModel.fromText(
        originalText: originalText,
        editedText: editedText,
      );

      final String retrieved = edits.editedText(originalText);

      assert(
        retrieved == editedText,
      );
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
}
