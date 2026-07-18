import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: SizedBox(width: 400, child: Center(child: child)),
    ),
  );

  /// The gold fill: the DecoratedBox inside the LayoutBuilder that measures the
  /// track and sizes the fill. The gray track is a bare DecoratedBox outside any
  /// LayoutBuilder, so anchoring on the LayoutBuilder picks out the fill alone.
  Finder fillFinder() => find.descendant(
    of: find.descendant(
      of: find.byType(ProgressBarRow),
      matching: find.byType(LayoutBuilder),
    ),
    matching: find.byType(DecoratedBox),
  );

  group('ProgressBarRow', () {
    testWidgets('gold fill has nonzero size for partial progress (#7603)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ProgressBarRow(summary: QuestStarSummary(earned: 3, total: 40)),
        ),
      );
      // The async L10n delegate load gates MaterialApp's first real frame.
      await tester.pumpAndSettle();

      final fillSize = tester.getSize(fillFinder().first);
      expect(fillSize.height, greaterThan(0));
      expect(fillSize.width, greaterThan(0));

      // The fill spans the summary's fraction of the track. 3/40 of the 400px
      // track is 30px — comfortably above the minimum-width floor below, so the
      // fraction is what's asserted here.
      final trackWidth = tester.getSize(find.byType(ProgressBarRow)).width;
      expect(fillSize.width, moreOrLessEquals(trackWidth * 3 / 40, epsilon: 1));
    });

    testWidgets('a sliver of progress is floored to the bar height', (
      tester,
    ) async {
      // 1/100 of the 400px track is 4px — a gold sliver too thin to read as a
      // rounded pill. It is floored to the bar height (20px) instead.
      await tester.pumpWidget(
        wrap(
          const ProgressBarRow(
            summary: QuestStarSummary(earned: 1, total: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(fillFinder().first).width, 20.0);
    });

    testWidgets('null summary renders no fill at all', (tester) async {
      // Zero progress draws the bare gray track: the fill is omitted entirely
      // rather than rendered at zero width (both are invisible; this is the
      // cheaper tree).
      await tester.pumpWidget(wrap(const ProgressBarRow(summary: null)));
      await tester.pumpAndSettle();
      expect(fillFinder(), findsNothing);
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
