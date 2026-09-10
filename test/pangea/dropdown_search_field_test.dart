import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// A dropdown menu opens under the cursor that just clicked the button, so the
/// second click of a double-click lands on the menu's search field while the
/// menu is still animating open. On web that tap desynchronises the browser's
/// DOM focus from Flutter's: the field keeps framework focus and paints a
/// caret, but keystrokes go nowhere and no later click recovers it (#8973).
///
/// [DropdownSearchField] closes that window by swallowing pointer input until
/// the menu's open transition has finished. These tests pin the gate: that it
/// finds the dropdown route's own animation, and that it lets go once the menu
/// has settled.
void main() {
  Widget harness(TextEditingController controller) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: DropdownButtonFormField2<String>(
            value: 'a',
            items: const [
              DropdownMenuItem(value: 'a', child: Text('Alpha')),
              DropdownMenuItem(value: 'b', child: Text('Beta')),
            ],
            onChanged: (_) {},
            dropdownSearchData: DropdownSearchData(
              searchController: controller,
              searchInnerWidgetHeight: 50,
              searchInnerWidget: DropdownSearchField(
                labelText: 'Search',
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('a tap lands only once the menu has finished opening', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(harness(controller));

    await tester.tap(find.byType(DropdownButtonFormField2<String>));
    await tester.pump(); // push the menu route
    await tester.pump(const Duration(milliseconds: 150)); // mid-transition

    await tester.tap(find.byType(PangeaSearchBar), warnIfMissed: false);
    await tester.pump();
    expect(
      fieldHasFocus(tester),
      isFalse,
      reason: 'a tap must not reach the field while the menu is animating',
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(PangeaSearchBar));
    await tester.pump();
    expect(
      fieldHasFocus(tester),
      isTrue,
      reason: 'the settled field has to accept taps again',
    );
  });
}
