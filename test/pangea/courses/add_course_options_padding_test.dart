import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/add_course_options.dart';

void main() {
  // #8299: the empty-state add-course buttons had no horizontal padding, so a
  // label long enough to wrap (German, Greek) filled the whole button and left
  // the leading icon flush against the rounded edge. One locale per file — a
  // second one pumps an empty subtree.
  testWidgets('leading icons keep padding when the label wraps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SizedBox(width: 300.0, child: AddCourseOptions())),
      ),
    );
    await tester.pumpAndSettle();

    // The private-course label wraps at this width and the first one doesn't —
    // the taller button is the case the bug reproduced on.
    expect(
      tester.getSize(find.byType(FilledButton).at(1)).height,
      greaterThan(tester.getSize(find.byType(FilledButton).first).height),
    );

    for (final icon in [
      Icons.auto_stories_outlined,
      Icons.vpn_key_outlined,
      Icons.travel_explore_outlined,
    ]) {
      final iconFinder = find.byIcon(icon);
      final button = find.ancestor(
        of: iconFinder,
        matching: find.byType(FilledButton),
      );
      expect(
        tester.getRect(iconFinder).left - tester.getRect(button).left,
        greaterThanOrEqualTo(8.0),
        reason: '$icon should not sit against the button edge',
      );
    }
  });
}
