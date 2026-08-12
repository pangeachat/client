// The CTA colour hierarchy the start page's buttons render, pinned here so the
// look stays consistent wherever [ActivitySessionCTAButton] is reused.
//
// Per activity-start-page.instructions.md § The CTA row, the web CTA list (and
// the mobile row it mirrors) carries a two-tier hierarchy: exactly one PRIMARY
// action is the darker filled `primary`; every following action is a fully
// filled but lighter `primaryContainer` button — never a bare outline. The
// button also went public so the archived fallback body can render its Leave
// action outside the CTA footer (#8064), and it takes an optional leading icon
// so the state CTAs can echo the map pins' iconography.

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';

void main() {
  Widget wrap(Widget child, {double width = 600.0}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('the primary CTA is a filled primary ElevatedButton', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const ActivitySessionCTAButton('Start', null)),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final context = tester.element(find.byType(ElevatedButton));
    final scheme = Theme.of(context).colorScheme;

    expect(button.style?.backgroundColor?.resolve({}), scheme.primary);
    expect(button.style?.foregroundColor?.resolve({}), scheme.onPrimary);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('CTA spans the width it is given', (tester) async {
    await tester.pumpWidget(
      wrap(const ActivitySessionCTAButton('Leave', null), width: 480.0),
    );

    expect(tester.getSize(find.byType(ElevatedButton)).width, 480.0);
  });

  testWidgets('the secondary variant is a lighter filled button, never an '
      'outline', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ActivitySessionCTAButton('Start my own', null, secondary: true),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final context = tester.element(find.byType(ElevatedButton));
    final scheme = Theme.of(context).colorScheme;

    expect(button.style?.backgroundColor?.resolve({}), scheme.primaryContainer);
    expect(
      button.style?.foregroundColor?.resolve({}),
      scheme.onPrimaryContainer,
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('an icon renders as a leading glyph before the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ActivitySessionCTAButton('Join', null, icon: Icons.group),
      ),
    );

    expect(find.byIcon(Icons.group), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('no icon is drawn when none is given', (tester) async {
    await tester.pumpWidget(
      wrap(const ActivitySessionCTAButton('Confirm', null)),
    );

    expect(find.byType(Icon), findsNothing);
  });
}
