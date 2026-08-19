import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/courses/course_plan_filter_widget.dart';

/// #8501 — the add-course pages (Browse public courses / Start my own) rendered
/// an empty panel as soon as a language was selected.
///
/// [CoursePlanFilter]'s closed button is a `Row`, and a `Row` lays its NON-flex
/// children out with an unbounded main axis. The label those pages hand it is
/// itself a `Row` holding a `Flexible` (so a long language name wraps instead of
/// overflowing at large device text sizes — #7719), so laying it out unbounded
/// threw "RenderFlex children have non-zero flex but incoming width constraints
/// are unbounded". A failed layout has no size, so every ancestor up to the
/// page body failed in turn and nothing below the app bar painted.
///
/// The label slot therefore has to arrive BOUNDED. These tests pin that from
/// the outside: a label containing a `Flexible` must lay out, and must be given
/// real width to lay out in.
void main() {
  /// The label shape the language picker passes — a `Row` + `Flexible`, the
  /// combination that needs a bounded width.
  Widget wrappingLabel(String text) =>
      Row(children: [Flexible(child: Text(text))]);

  Future<void> pumpFilter(
    WidgetTester tester, {
    String? value,
    double width = 400.0,
    TextScaler textScaler = TextScaler.noScaling,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SizedBox(
            width: width,
            // The picker sits in a Row beside the search button on both
            // add-course pages, so the filter arrives inside an Expanded.
            child: Row(
              children: [
                Expanded(
                  child: CoursePlanFilter<String>(
                    value: value,
                    items: const ['es', 'de'],
                    onChanged: (_) {},
                    defaultName: 'All languages',
                    displayname: (v) => wrappingLabel('displayname $v'),
                    selectedItemBuilder: (v) => wrappingLabel('Spanish'),
                  ),
                ),
                const Icon(Icons.search),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  group('CoursePlanFilter closed button', () {
    testWidgets('lays out a selected label that contains a Flexible', (
      tester,
    ) async {
      await pumpFilter(tester, value: 'es');

      expect(
        tester.takeException(),
        isNull,
        reason:
            'an unbounded label slot throws RenderFlex-unbounded-flex and '
            'blanks the whole add-course page (#8501)',
      );
      expect(find.text('Spanish'), findsOneWidget);
    });

    testWidgets('gives the selected label a bounded, usable width', (
      tester,
    ) async {
      await pumpFilter(tester, value: 'es');

      final labelWidth = tester.getSize(find.text('Spanish')).width;
      expect(labelWidth, greaterThan(0.0));
      expect(
        labelWidth,
        lessThan(400.0),
        reason: 'the label must fit inside the button, not overrun it',
      );
    });

    testWidgets('still renders the default name when nothing is selected', (
      tester,
    ) async {
      await pumpFilter(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('All languages'), findsOneWidget);
    });

    testWidgets('lays out a selected label at the largest device text size', (
      tester,
    ) async {
      // iOS AX5 is ~3.1x; 3.0 is the worst realistic case (see
      // text_scaling_overflow_test.dart).
      await pumpFilter(
        tester,
        value: 'es',
        textScaler: const TextScaler.linear(3.0),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Spanish'), findsOneWidget);
    });
  });
}
