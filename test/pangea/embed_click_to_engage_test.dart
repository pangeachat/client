import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/embed_click_to_engage.dart';

void main() {
  /// Taps recorded by the stand-in embed — on web these would be the browser's
  /// clicks reaching the `<iframe>`, which only happens once it is engaged.
  late int embedTaps;
  late int engagements;

  Widget subject({required bool enabled}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          height: 100,
          child: EmbedClickToEngage(
            enabled: enabled,
            onEngage: () => engagements++,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => embedTaps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );

  /// Moves a mouse onto the embed and off it again, which is what hands the
  /// pointer back and re-arms the shield.
  Future<void> moveMouseAway(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(EmbedClickToEngage)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump();
  }

  setUp(() {
    embedTaps = 0;
    engagements = 0;
  });

  testWidgets('disabled: every tap goes straight to the embed', (tester) async {
    await tester.pumpWidget(subject(enabled: false));

    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();

    expect(embedTaps, 1);
    expect(engagements, 0);
  });

  testWidgets('armed: the first tap engages instead of reaching the embed', (
    tester,
  ) async {
    await tester.pumpWidget(subject(enabled: true));

    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();

    expect(embedTaps, 0);
    expect(engagements, 1);
  });

  testWidgets('engaged: later taps reach the embed', (tester) async {
    await tester.pumpWidget(subject(enabled: true));

    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();
    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();

    expect(embedTaps, 1);
    expect(engagements, 1);
  });

  testWidgets('the pointer leaving re-arms it', (tester) async {
    await tester.pumpWidget(subject(enabled: true));

    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();
    await moveMouseAway(tester);

    await tester.tap(find.byType(EmbedClickToEngage));
    await tester.pump();

    expect(embedTaps, 0, reason: 'the shield is back up');
    expect(engagements, 2);
  });
}
