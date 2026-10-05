import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/utils/show_menu_long_press.dart';

/// #8767 — on web, a screen reader's "show menu" command reaches the app only
/// as a DOM `contextmenu` event on an opted-in semantics node. The web bridge
/// hands that node's id to [ShowMenuLongPress.perform], which opens its
/// long-press menu and reports whether one existed, so the browser's page
/// menu is suppressed only when the app has a menu to show instead.
void main() {
  testWidgets('performs the long-press of the node with that id', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var longPressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(
            title: const Text('row'),
            onTap: () {},
            onLongPress: () => longPressed++,
          ),
        ),
      ),
    );

    final row = tester.getSemantics(find.byType(ListTile));
    expect(ShowMenuLongPress.perform(row.id), isTrue);
    await tester.pump();
    expect(longPressed, 1);
    semantics.dispose();
  });

  testWidgets('declines a node without a long-press, and an unknown id', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: TextButton(onPressed: () {}, child: const Text('tap only')),
        ),
      ),
    );

    final button = tester.getSemantics(find.byType(TextButton));
    expect(
      button.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
      reason: 'the node exists and is interactive, just not long-pressable',
    );
    expect(ShowMenuLongPress.perform(button.id), isFalse);
    expect(ShowMenuLongPress.perform(-1), isFalse);
    semantics.dispose();
  });
}
