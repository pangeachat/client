import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';

/// How the right-docked analytics panel renders for the resolved layout.
enum AnalyticsPanelMode {
  /// Not shown.
  none,

  /// A docked card on the right; the center content is bounded to its left so
  /// they tile without overlap, and the cluster sits in the gutter beside it.
  dockedCard,

  /// Covers the content area (no room to tile, or narrow screen) — a Slide-Over.
  fullBleed,
}

/// The world_v2 shell's single layout authority. Every floating zone over the
/// persistent map — the left column, the center detail/canvas, the right
/// analytics panel, the cluster gutter — is sized from ONE width budget here, so
/// they **tile and never overlap by construction**. The old failure was each
/// zone computing its own width independently (the detail didn't reserve the
/// panel's footprint), which let them collide. The shell ([TwoColumnLayout])
/// reads this and places its `Positioned` children; nothing computes a width on
/// its own. Pure + unit-tested (see shell_layout_test.dart).
@immutable
class ShellLayout {
  /// Reserved left margin: nav rail + left column. 0 in narrow mode.
  final double leftInset;

  /// Reserved right margin: the docked analytics card zone + cluster gutter.
  /// 0 when the panel is closed or rendered full-bleed.
  final double rightInset;

  /// How/whether the analytics panel renders.
  final AnalyticsPanelMode analyticsMode;

  /// Width of the analytics panel's `Positioned` zone (the card area, excluding
  /// the gutter for [AnalyticsPanelMode.dockedCard]; the covered content-area
  /// width for [AnalyticsPanelMode.fullBleed]).
  final double analyticsZoneWidth;

  /// Capped, left-anchored width for opaque detail content in the center band.
  /// Bounded by [leftInset] + [rightInset] so it cannot slide under the panel.
  final double detailWidth;

  /// Whether the top-right user cluster shows (hidden behind a full-bleed panel).
  final bool clusterVisible;

  /// Map camera padding so a course fit lands in the area the overlays don't
  /// cover (left = rail+column+detail; right = the docked panel zone).
  final double mapLeftOverlay;
  final double mapRightOverlay;

  const ShellLayout({
    required this.leftInset,
    required this.rightInset,
    required this.analyticsMode,
    required this.analyticsZoneWidth,
    required this.detailWidth,
    required this.clusterVisible,
    required this.mapLeftOverlay,
    required this.mapRightOverlay,
  });

  // ---- layout tokens (the single source for these widths) -------------------

  /// Right gutter for the vertical cluster, beside the docked panel.
  static const double clusterGutter = 88.0;

  /// Max width of a single analytics card (summary or detail).
  static const double analyticsCardMax = 488.0;

  /// Gap between the detail card and the summary card when both are open.
  static const double analyticsCardGap = 16.0;

  /// Max width of an opaque detail/canvas (chat, course) — the map peeks beyond.
  static const double detailMax = 720.0;

  /// Minimum usable width for opaque center content alongside the panel. Below
  /// this the panel can't tile, so it takes over as a full-bleed Slide-Over.
  static const double minCenter = 360.0;

  /// Resolve the whole shell budget. [leftInset] is the rail + left column the
  /// caller already computed; [canvas] is the route's canvas mode; [panelOpen]
  /// and [panelDetailOpen] describe the analytics panel; [mapVisible] is whether
  /// the map shows behind (so the cluster could appear).
  static ShellLayout resolve({
    required double viewport,
    required bool isColumnMode,
    required double leftInset,
    required CanvasMode canvas,
    required bool panelOpen,
    required bool panelDetailOpen,
    required bool mapVisible,
  }) {
    final opaqueCenter =
        canvas == CanvasMode.detail || canvas == CanvasMode.fullBleed;

    double detailFor(double left, double right) =>
        math.min(detailMax, math.max(0.0, viewport - left - right));

    double leftOverlayFor(double left, double detailW) =>
        left + (canvas == CanvasMode.detail ? detailW : 0.0);

    // Narrow: one content zone fills; the panel (if open) is a full-bleed
    // Slide-Over; the cluster hides while it's open.
    if (!isColumnMode) {
      return ShellLayout(
        leftInset: 0,
        rightInset: 0,
        analyticsMode:
            panelOpen ? AnalyticsPanelMode.fullBleed : AnalyticsPanelMode.none,
        analyticsZoneWidth: viewport,
        detailWidth: viewport,
        clusterVisible: mapVisible && !panelOpen,
        mapLeftOverlay: 0,
        mapRightOverlay: 0,
      );
    }

    // Column mode, panel closed: the detail fills the center (capped).
    if (!panelOpen) {
      final detailW = detailFor(leftInset, 0);
      return ShellLayout(
        leftInset: leftInset,
        rightInset: 0,
        analyticsMode: AnalyticsPanelMode.none,
        analyticsZoneWidth: 0,
        detailWidth: detailW,
        clusterVisible: mapVisible,
        mapLeftOverlay: leftOverlayFor(leftInset, detailW),
        mapRightOverlay: 0,
      );
    }

    // Column mode, panel open. Try to tile: the panel claims a card zone + the
    // cluster gutter on the right; the center keeps the rest.
    final wantZone = panelDetailOpen
        ? (analyticsCardMax * 2 + analyticsCardGap)
        : analyticsCardMax;
    final tiledRight = wantZone + clusterGutter;
    final centerIfTiled = viewport - leftInset - tiledRight;

    // The map is flexible (it can shrink to any sliver), so a map-hole center
    // always tiles. Opaque content tiles only if it keeps [minCenter]; else the
    // panel takes over as a full-bleed Slide-Over (the no-room fallback).
    final canTile = !opaqueCenter || centerIfTiled >= minCenter;

    if (canTile) {
      final zone = math.min(wantZone, viewport - leftInset - clusterGutter);
      final detailW = detailFor(leftInset, zone + clusterGutter);
      return ShellLayout(
        leftInset: leftInset,
        rightInset: zone + clusterGutter,
        analyticsMode: AnalyticsPanelMode.dockedCard,
        analyticsZoneWidth: math.max(0.0, zone),
        detailWidth: detailW,
        clusterVisible: mapVisible,
        mapLeftOverlay: leftOverlayFor(leftInset, detailW),
        mapRightOverlay: zone + clusterGutter,
      );
    }

    // No room to tile: the panel covers the content area to the right of the
    // left column; the detail keeps its width behind it; the cluster hides.
    final detailW = detailFor(leftInset, 0);
    return ShellLayout(
      leftInset: leftInset,
      rightInset: 0,
      analyticsMode: AnalyticsPanelMode.fullBleed,
      analyticsZoneWidth: math.max(0.0, viewport - leftInset),
      detailWidth: detailW,
      clusterVisible: false,
      mapLeftOverlay: leftOverlayFor(leftInset, detailW),
      mapRightOverlay: 0,
    );
  }
}
