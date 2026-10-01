import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/pass_through_tooltip.dart';

/// #8591 / #8857: a hover label that takes pointer input kills whatever
/// gesture carries it under the cursor. [PassThroughTooltip] must show like a
/// [Tooltip] — on hover, after its wait — while its label passes every tap and
/// scroll through to what it covers, and its child still carries the message
/// as its accessible name.
void main() {
  const message = 'Spanish 101';
  const childKey = Key('child');

  /// The tooltip's child centred over a full-screen stand-in for whatever its
  /// label might cover.
  Future<void> pumpTooltip(
    WidgetTester tester, {
    Duration waitDuration = Duration.zero,
    bool excludeFromSemantics = false,
    VoidCallback? onTapBeneath,
    void Function(PointerSignalEvent)? onScrollBeneath,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Listener(
                onPointerSignal: onScrollBeneath,
                behavior: HitTestBehavior.opaque,
                child: GestureDetector(
                  onTap: onTapBeneath,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              Center(
                child: PassThroughTooltip(
                  message: message,
                  waitDuration: waitDuration,
                  excludeFromSemantics: excludeFromSemantics,
                  child: const SizedBox(key: childKey, width: 40, height: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hoverChild(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(childKey)));
    return mouse;
  }

  testWidgets('shows after the wait duration on hover and hides when the '
      'pointer leaves', (tester) async {
    await pumpTooltip(tester, waitDuration: const Duration(milliseconds: 500));
    final mouse = await hoverChild(tester);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(message), findsNothing);

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(message),
      findsNothing,
      reason: 'leaving before the wait is up cancels the label',
    );

    await mouse.moveTo(tester.getCenter(find.byKey(childKey)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(message), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text(message), findsNothing);
  });

  testWidgets('a tap and a scroll over the label reach what it covers', (
    tester,
  ) async {
    var tapped = false;
    var scrolls = 0;
    await pumpTooltip(
      tester,
      onTapBeneath: () => tapped = true,
      onScrollBeneath: (_) => scrolls++,
    );
    await hoverChild(tester);
    await tester.pumpAndSettle();
    final label = tester.getCenter(find.text(message));

    await tester.tapAt(label);
    await tester.pump();
    expect(tapped, isTrue, reason: 'the label must not swallow taps');

    final wheel = TestPointer(2, PointerDeviceKind.mouse);
    wheel.hover(label);
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(scrolls, 1, reason: 'the label must not swallow scrolls');
  });

  testWidgets('a press on the child dismisses the label', (tester) async {
    await pumpTooltip(tester);
    final mouse = await hoverChild(tester);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);

    await mouse.down(tester.getCenter(find.byKey(childKey)));
    await mouse.up();
    await tester.pump();
    expect(find.text(message), findsNothing);
  });

  testWidgets('the child carries the message as its semantic tooltip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTooltip(tester);

    expect(
      tester.getSemantics(find.byKey(childKey)),
      isSemantics(tooltip: message),
    );
    handle.dispose();
  });

  testWidgets('excludeFromSemantics drops the semantic tooltip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTooltip(tester, excludeFromSemantics: true);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.tooltip == message,
      ),
      findsNothing,
    );
    handle.dispose();
  });
}
