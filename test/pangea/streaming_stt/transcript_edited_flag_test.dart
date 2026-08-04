import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/transcript_edited_flag.dart';

void main() {
  Widget host(bool edited) => MaterialApp(
    home: Scaffold(body: TranscriptEditedFlag(edited: edited)),
  );

  testWidgets('renders the neutral edit pencil iff edited == true', (
    tester,
  ) async {
    await tester.pumpWidget(host(true));
    final iconFinder = find.byIcon(Icons.edit_outlined);
    expect(iconFinder, findsOneWidget);
    final icon = tester.widget<Icon>(iconFinder);
    // Neutral meta colour (onSurfaceVariant), NOT the warning-orange — an edit
    // is normal, not an error.
    final expected =
        Theme.of(tester.element(iconFinder)).colorScheme.onSurfaceVariant;
    expect(icon.color, expected);
  });

  testWidgets('uses the supplied colour over the meta-colour fallback', (
    tester,
  ) async {
    // The audio-tile mount passes the bubble's `textColor` so the pencil reads
    // on the (light) voice bubble; onSurfaceVariant is only the fallback and
    // would wash out there. Teeth: dropping the `color ??` in build() makes the
    // icon fall back to onSurfaceVariant here -> RED.
    const supplied = Color(0xFF123456);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TranscriptEditedFlag(edited: true, color: supplied),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.edit_outlined));
    expect(icon.color, supplied);
  });

  testWidgets('renders NOTHING for a verbatim (edited == false) message', (
    tester,
  ) async {
    await tester.pumpWidget(host(false));
    // Teeth: dropping the `if (!edited) return SizedBox` guard makes the icon
    // appear here -> RED.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('edited pencil is passive and owns no gesture surface', (
    tester,
  ) async {
    await tester.pumpWidget(host(true));
    expect(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });
}
