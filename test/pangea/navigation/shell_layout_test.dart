import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/widgets/layouts/shell_layout.dart';

void main() {
  // Realistic insets: rail (73) only for world; rail + left column (73 + 381)
  // for a course/chat detail that keeps its list column.
  const railOnly = 73.0;
  const railPlusColumn = 73.0 + 381.0;

  ShellLayout resolve({
    double viewport = 1600,
    bool isColumnMode = true,
    double leftInset = railOnly,
    CanvasMode canvas = CanvasMode.mapHole,
    bool panelOpen = false,
    bool panelDetailOpen = false,
    bool mapVisible = true,
  }) =>
      ShellLayout.resolve(
        viewport: viewport,
        isColumnMode: isColumnMode,
        leftInset: leftInset,
        canvas: canvas,
        panelOpen: panelOpen,
        panelDetailOpen: panelDetailOpen,
        mapVisible: mapVisible,
      );

  group('non-overlap invariant (the whole point)', () {
    test('a docked panel never overlaps the detail — detail ends at/before the '
        'panel left edge across widths', () {
      for (final viewport in [1334.0, 1440.0, 1600.0, 1920.0]) {
        final l = resolve(
          viewport: viewport,
          leftInset: railPlusColumn,
          canvas: CanvasMode.detail,
          panelOpen: true,
        );
        if (l.analyticsMode == AnalyticsPanelMode.dockedCard) {
          // detail right edge <= panel left edge (= viewport - rightInset)
          expect(
            l.leftInset + l.detailWidth,
            lessThanOrEqualTo(viewport - l.rightInset + 0.001),
            reason: 'overlap at $viewport',
          );
        }
      }
    });
  });

  group('world (map hole) + panel', () {
    test('tiles as a docked card; map is flexible so it always fits', () {
      final l = resolve(canvas: CanvasMode.mapHole, panelOpen: true);
      expect(l.analyticsMode, AnalyticsPanelMode.dockedCard);
      expect(l.analyticsZoneWidth, ShellLayout.analyticsCardMax);
      expect(l.rightInset,
          ShellLayout.analyticsCardMax + ShellLayout.clusterGutter);
      expect(l.clusterVisible, isTrue);
    });

    test('detail-open shows two cards', () {
      final l = resolve(
        canvas: CanvasMode.mapHole,
        panelOpen: true,
        panelDetailOpen: true,
      );
      expect(l.analyticsZoneWidth,
          ShellLayout.analyticsCardMax * 2 + ShellLayout.analyticsCardGap);
    });
  });

  group('course/chat detail + panel', () {
    test('wide viewport tiles (panel docked, detail bounded)', () {
      final l = resolve(
        viewport: 1600,
        leftInset: railPlusColumn,
        canvas: CanvasMode.detail,
        panelOpen: true,
      );
      expect(l.analyticsMode, AnalyticsPanelMode.dockedCard);
      expect(l.detailWidth, greaterThan(0));
    });

    test('tight viewport falls back to a full-bleed Slide-Over (no overlap, '
        'cluster hidden)', () {
      final l = resolve(
        viewport: 1100,
        leftInset: railPlusColumn,
        canvas: CanvasMode.detail,
        panelOpen: true,
      );
      expect(l.analyticsMode, AnalyticsPanelMode.fullBleed);
      expect(l.rightInset, 0);
      expect(l.clusterVisible, isFalse);
    });
  });

  group('narrow mode', () {
    test('panel is full-bleed; cluster hidden while open', () {
      final l = resolve(viewport: 400, isColumnMode: false, panelOpen: true);
      expect(l.analyticsMode, AnalyticsPanelMode.fullBleed);
      expect(l.leftInset, 0);
      expect(l.clusterVisible, isFalse);
    });

    test('no panel + map visible shows the cluster', () {
      final l = resolve(
        viewport: 400,
        isColumnMode: false,
        canvas: CanvasMode.mapHole,
      );
      expect(l.analyticsMode, AnalyticsPanelMode.none);
      expect(l.clusterVisible, isTrue);
    });
  });

  group('column mode, no panel', () {
    test('detail fills the center capped at detailMax; no right inset', () {
      final l = resolve(
        viewport: 1600,
        leftInset: railPlusColumn,
        canvas: CanvasMode.detail,
      );
      expect(l.analyticsMode, AnalyticsPanelMode.none);
      expect(l.rightInset, 0);
      expect(l.detailWidth, ShellLayout.detailMax); // 1600-454 > 720 → capped
    });
  });
}
