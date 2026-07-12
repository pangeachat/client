import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_view.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, child: Center(child: child)),
    ),
  );

  /// The gold fill: the FractionallySizedBox's DecoratedBox.
  Finder fillFinder() => find.descendant(
    of: find.byType(FractionallySizedBox),
    matching: find.byType(DecoratedBox),
  );

  group('ProgressBarRow', () {
    testWidgets('gold fill has nonzero size for partial progress (#7603)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ProgressBarRow(
            summary: QuestStarSummary(earned: 3, total: 40),
          ),
        ),
      );
      // The async L10n delegate load gates MaterialApp's first real frame.
      await tester.pumpAndSettle();

      final fillSize = tester.getSize(fillFinder().first);
      expect(fillSize.height, greaterThan(0));
      expect(fillSize.width, greaterThan(0));

      // The fill spans the summary's fraction of the track (the row itself —
      // FractionallySizedBox shrink-wraps its child, so it can't measure it).
      final trackWidth = tester.getSize(find.byType(ProgressBarRow)).width;
      expect(fillSize.width, moreOrLessEquals(trackWidth * 3 / 40, epsilon: 1));
    });

    testWidgets('null summary renders an empty (zero-width) fill', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const ProgressBarRow(summary: null)));
      await tester.pumpAndSettle();
      expect(tester.getSize(fillFinder().first).width, 0);
    });

    testWidgets('full progress fills the whole track', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ProgressBarRow(
            summary: QuestStarSummary(earned: 40, total: 40),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fillSize = tester.getSize(fillFinder().first);
      final trackWidth = tester.getSize(find.byType(ProgressBarRow)).width;
      expect(fillSize.width, moreOrLessEquals(trackWidth, epsilon: 0.01));
      expect(fillSize.height, greaterThan(0));
    });
  });
}
