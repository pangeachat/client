import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/features/course_plans/map_border.dart';
import 'package:fluffychat/features/course_plans/map_clipper.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';
import '../../utils/test_client.dart';

/// Covers the course-avatar half of #8724 (finding 5 of the 2026-09 a11y
/// triage, #8689): a rail item's InkWell paints its focus highlight on a
/// transparent Material BEHIND the icon, so the opaque course-avatar banner
/// hides all but ~350 of its pixels (measured imperceptible on staging).
/// With [NaviRailItem.focusRingShape] set, the item wears the app's explicit
/// gold focus ring — a [MapBorder], tracing the avatar's own silhouette in
/// the foreground — and Enter still activates it.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
  });

  tearDownAll(() => client.dispose());

  /// Whether the tree currently paints the gold focus ring (the 3px-side
  /// ShapeDecoration FocusRingTapTarget draws while focused — the same
  /// assertion cluster_keyboard_focus_test uses).
  bool showsFocusRing(WidgetTester tester) {
    return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((
      box,
    ) {
      final decoration = box.decoration;
      return decoration is ShapeDecoration &&
          decoration.shape is OutlinedBorder &&
          (decoration.shape as OutlinedBorder).side.width == 3.0;
    });
  }

  testWidgets(
    'a rail item with a focusRingShape shows the gold ring on Tab and '
    'activates on Enter',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Provider<MatrixState>.value(
              value: _FakeMatrixState(client),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NaviRailItem(
                      toolTip: 'My course',
                      isSelected: false,
                      onTap: () => opened++,
                      // An opaque banner standing in for the course avatar —
                      // the exact fill that swallowed the behind-the-child
                      // highlight.
                      icon: ClipPath(
                        clipper: MapClipper(),
                        child: Container(
                          width: 56,
                          height: 56,
                          color: Colors.blueGrey,
                        ),
                      ),
                      naviRailWidth: 80,
                      backgroundColor: Colors.transparent,
                      // The production shape (_SpaceItem): the ring traces
                      // the avatar's own banner silhouette.
                      focusRingShape: const MapBorder(),
                    ),
                    // A focusable after the item, so the last Tab can move
                    // focus OFF it (with one focusable, Tab wraps in place).
                    TextButton(onPressed: () {}, child: const Text('after')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(showsFocusRing(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester),
        isTrue,
        reason:
            'Tab must focus the rail item with a VISIBLE ring — the ink '
            'highlight behind an opaque course avatar is imperceptible '
            '(#8724)',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, 1, reason: 'Enter on the focused item must activate it');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        showsFocusRing(tester),
        isFalse,
        reason: 'the ring must follow focus off the item',
      );
    },
  );
}
