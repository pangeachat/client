import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_session_button_widget.dart';

/// The session page's CTA button became public so the archived fallback body
/// could render a Leave action outside the CTA footer (#8064). These pin the
/// look it is reused for: a filled `primaryContainer` button that spans the
/// width it is given, so the leave CTA on a removed activity is visually the
/// same call to action as Start / Continue / Confirm.
void main() {
  Widget wrap(Widget child, {double width = 600.0}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('primary CTA is a primaryContainer ElevatedButton', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const ActivitySessionCTAButton('Leave', null)),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final context = tester.element(find.byType(ElevatedButton));
    final scheme = Theme.of(context).colorScheme;

    expect(button.style?.backgroundColor?.resolve({}), scheme.primaryContainer);
    expect(
      button.style?.foregroundColor?.resolve({}),
      scheme.onPrimaryContainer,
    );
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('CTA spans the width it is given', (tester) async {
    await tester.pumpWidget(
      wrap(const ActivitySessionCTAButton('Leave', null), width: 480.0),
    );

    expect(tester.getSize(find.byType(ElevatedButton)).width, 480.0);
  });

  testWidgets('the secondary variant is outlined, not filled', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ActivitySessionCTAButton('Start my own', null, secondary: true),
      ),
    );

    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
