import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/activity_star_row.dart';

/// #8595: every host gives the star row a box that can't grow taller, so it
/// must shrink to stay on one line instead of wrapping a run outside the card.
void main() {
  Future<Size> pumpRow(
    WidgetTester tester, {
    required int total,
    required double maxWidth,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ActivityStarRow(total: total, earned: 2, iconSize: 22.0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(ActivityStarRow));
  }

  // Six 22pt stars want 142pt. The role card at 375pt gives each of its two
  // cards ~136pt of content, so they only fit scaled down.
  const naturalWidth = 6 * 22.0 + 5 * 2.0;

  testWidgets('shrinks to one row in a role-card-width box', (tester) async {
    final size = await pumpRow(tester, total: 6, maxWidth: 136.0);
    expect(size.width, lessThanOrEqualTo(136.0));
    expect(size.height, lessThanOrEqualTo(22.0));
  });

  testWidgets('is not scaled when it already fits', (tester) async {
    final size = await pumpRow(tester, total: 6, maxWidth: 200.0);
    expect(size.width, closeTo(naturalWidth, 0.01));
    expect(size.height, closeTo(22.0, 0.01));
  });

  // #9032: ListTile tightens its subtitle to the text column's width, which
  // shrinks when a trailing widget (the Stars list's CEFR label) is there. A
  // centred row therefore sat at a different offset from row to row.
  testWidgets('starts at the same offset with and without a trailing widget', (
    tester,
  ) async {
    Future<double> starsLeft({required bool withTrailing}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListTile(
              title: const Text('Ordering a coffee'),
              subtitle: const ActivityStarRow(
                total: 3,
                earned: 2,
                iconSize: 22.0,
              ),
              trailing: withTrailing ? const Text('A2') : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The first star itself, not [ActivityStarRow]'s box: the box IS the
      // whole tightened text column either way, so only where the stars land
      // inside it tells the two apart.
      return tester.getTopLeft(find.byIcon(Icons.star).first).dx;
    }

    final withCefr = await starsLeft(withTrailing: true);
    final withoutCefr = await starsLeft(withTrailing: false);
    expect(withCefr, closeTo(withoutCefr, 0.01));

    // And flush with the title above them, not floating in the leftover space.
    expect(tester.getTopLeft(find.text('Ordering a coffee')).dx, withoutCefr);
  });
}
