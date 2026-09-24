import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/overlay/transparent_backdrop.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// #9255 — on web, with a platform view in the scene, CanvasKit re-darkens the
/// backdrop for every BackdropFilter over the scrim. A backdrop carries a
/// filter only when it blurs, and the filter sits beneath its tint.
void main() {
  /// The Dismiss label comes from `L10n`, whose delegate loads from a
  /// deferred library: settle, or nothing is in the tree yet.
  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required bool blurBackground,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TransparentBackdrop(
          backgroundColor: Colors.black,
          blurBackground: blurBackground,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final filter = find.descendant(
    of: find.byType(TransparentBackdrop),
    matching: find.byType(BackdropFilter),
  );

  testWidgets('a backdrop that does not blur has no BackdropFilter', (
    tester,
  ) async {
    await pumpBackdrop(tester, blurBackground: false);
    expect(filter, findsNothing);
  });

  testWidgets('a blurring backdrop filters beneath its tint', (tester) async {
    await pumpBackdrop(tester, blurBackground: true);
    expect(filter, findsOneWidget);
    expect(
      find.descendant(of: filter, matching: find.byType(InkWell)),
      findsOneWidget,
    );
  });
}
