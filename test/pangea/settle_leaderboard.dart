import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

/// Pumps until the leaderboard found by [leaderboard] has mounted and its
/// profiles have loaded, then settles.
///
/// L10n's delegate resolves from a deferred library on the fake clock, so
/// nothing is in the tree until a pump advances it. The profiles then load
/// over the test client, whose answers need real time to pass, and the
/// spinner shown meanwhile never lets `pumpAndSettle` return. So the two
/// clocks take turns until the spinner is gone.
Future<void> settle(WidgetTester tester, Finder leaderboard) async {
  bool loaded() =>
      leaderboard.evaluate().isNotEmpty &&
      find.byType(CircularProgressIndicator).evaluate().isEmpty;
  for (var i = 0; i < 50 && !loaded(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
}
