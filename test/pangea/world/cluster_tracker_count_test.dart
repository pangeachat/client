import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/compact_count.dart';
import 'package:fluffychat/routes/world/world_user_cluster.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';

/// Pins the width contract that keeps the world user cluster's powerups pill
/// inside the allocator's fixed `PanelAllocator.clusterGutter` (#7508): raw
/// 4-5 digit tracker counts grew the pill past the gutter and under the right
/// column's card, so [ClusterTrackerButton] displays [compactCount]'s
/// abbreviation (never more than 4 glyphs) while its semantics label keeps
/// the exact count for assistive tech.
void main() {
  group('compactCount', () {
    test('passes counts below 1000 through exactly', () {
      expect(compactCount(0), '0');
      expect(compactCount(42), '42');
      expect(compactCount(999), '999');
    });

    test('abbreviates thousands, floored, dropping a zero decimal', () {
      expect(compactCount(1000), '1k');
      expect(compactCount(1049), '1k');
      expect(compactCount(1250), '1.2k');
      expect(compactCount(9999), '9.9k');
      expect(compactCount(10000), '10k');
      expect(compactCount(99999), '99k');
      expect(compactCount(999999), '999k', reason: 'floored, never 1M early');
    });

    test('abbreviates millions the same way', () {
      expect(compactCount(1000000), '1M');
      expect(compactCount(1234567), '1.2M');
      expect(compactCount(999999999), '999M');
    });

    test('never exceeds 4 glyphs for any reachable count', () {
      for (final n in [0, 9, 99, 999, 1000, 9999, 99999, 999999, 999999999]) {
        expect(
          compactCount(n).length,
          lessThanOrEqualTo(4),
          reason: '$n must render width-bounded',
        );
      }
    });
  });

  group('ClusterTrackerButton', () {
    Future<void> pumpTracker(WidgetTester tester, int count) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ClusterTrackerButton(
                indicator: ProgressIndicatorEnum.wordsUsed,
                count: count,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      // The L10n delegates load asynchronously (same as the analytics bar
      // tests); one pump isn't enough for the tracker to mount.
      await tester.pumpAndSettle();
    }

    double trackerWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ClusterTrackerButton)).width;

    testWidgets('a 5-digit count renders no wider than a 3-digit count', (
      tester,
    ) async {
      await pumpTracker(tester, 999);
      final threeDigitWidth = trackerWidth(tester);

      await pumpTracker(tester, 99999);
      expect(
        trackerWidth(tester),
        threeDigitWidth,
        reason:
            'abbreviation ("99k") must keep a 5-digit count at 3 glyphs, so '
            'the pill stays inside PanelAllocator.clusterGutter',
      );
    });

    testWidgets('the displayed count never exceeds 4 glyphs of width', (
      tester,
    ) async {
      // Measure one glyph's advance from the trackers themselves (the test
      // font's digits aren't exactly 1em wide), then cap every abbreviated
      // count at four advances — the widest string compactCount can emit.
      // Production fonts render '.'/'k' narrower than digits, so real widths
      // sit below this cap, inside the gutter budget (88 clusterGutter - 12
      // chrome margin - 18 pill chrome around the widest tracker).
      await pumpTracker(tester, 99);
      final twoGlyphs = trackerWidth(tester);
      await pumpTracker(tester, 999);
      final threeGlyphs = trackerWidth(tester);
      final maxWidth = threeGlyphs + (threeGlyphs - twoGlyphs);

      for (final count in [9999, 99999, 999999, 1234567]) {
        await pumpTracker(tester, count);
        expect(
          trackerWidth(tester),
          lessThanOrEqualTo(maxWidth),
          reason: 'count $count must render at most 4 glyphs',
        );
      }
    });

    testWidgets('shows the abbreviation but announces the exact count', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTracker(tester, 99999);

      expect(find.text('99k'), findsOneWidget);
      expect(find.text('99999'), findsNothing);

      final l10n = L10n.of(tester.element(find.byType(Scaffold)));
      expect(
        find.bySemanticsLabel('${l10n.vocab}: 99999'),
        findsOneWidget,
        reason: 'assistive tech must get the exact count, not "99k"',
      );

      semantics.dispose();
    });
  });
}
