import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/navi_rail_item.dart';
import '../../utils/test_client.dart';

/// #8215: a bare [Tooltip] shows the moment the pointer enters, so items
/// sweeping under the cursor while the rail scrolls each spawned a tooltip
/// and made the scroll jitter. The rail item's tooltip must sit out a brief
/// scroll sweep but still appear on an intentional hover.
class _FakeMatrixState extends MatrixState {
  _FakeMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

void main() {
  const toolTip = 'My course';

  late Client client;

  setUpAll(() async {
    client = await prepareTestClient();
  });

  tearDownAll(() => client.dispose());

  Future<void> pumpItem(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Provider<MatrixState>.value(
            value: _FakeMatrixState(client),
            child: Center(
              child: NaviRailItem(
                toolTip: toolTip,
                isSelected: false,
                onTap: () {},
                icon: const Icon(Icons.public),
                naviRailWidth: 80,
              ),
            ),
          ),
        ),
      ),
    );
    // L10n is deferred-loaded, so the subtree only builds once it resolves.
    await tester.pumpAndSettle();
  }

  testWidgets('a scroll sweep does not trigger the tooltip; a sustained '
      'hover still does', (tester) async {
    await pumpItem(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byType(NaviRailItem)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.text(toolTip),
      findsNothing,
      reason:
          'an item passing under the cursor mid-scroll must not '
          'spawn a tooltip',
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      find.text(toolTip),
      findsOneWidget,
      reason:
          'an intentional hover past the wait duration must still '
          'show the tooltip',
    );

    // Leave the item so the tooltip dismisses and no timers outlive the test.
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
  });
}
