import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/routes/world/world_user_cluster.dart';

/// #7078: while the analytics database is loading, the main-view cluster shows a
/// full-widget shimmer skeleton instead of flashing zeros. The skeleton mirrors
/// the live cluster's shape (avatar, powerups pill, optional language flag).
void main() {
  // The shimmer animates forever (Shimmer.fromColors default loop), so pump a
  // single frame — pumpAndSettle would never return.
  Future<void> pumpShimmer(WidgetTester tester, {required bool showFlag}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: WorldUserClusterShimmer(showFlag: showFlag)),
          ),
        ),
      );

  testWidgets('renders a single continuous shimmer over the skeleton', (
    tester,
  ) async {
    await pumpShimmer(tester, showFlag: true);
    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('showing the language flag adds exactly one skeleton box', (
    tester,
  ) async {
    await pumpShimmer(tester, showFlag: false);
    final withoutFlag = find.byType(Container).evaluate().length;
    await pumpShimmer(tester, showFlag: true);
    final withFlag = find.byType(Container).evaluate().length;
    expect(
      withFlag,
      withoutFlag + 1,
      reason: 'the flag adds one skeleton box vs avatar + pill alone',
    );
  });
}
