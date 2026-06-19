import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/navigation/panel_registry.dart';

/// How a panel renders for the resolved layout.
enum PanelVis {
  /// Sized between its hard min and ideal width.
  full,

  /// Not drawn. Either an exclusive panel holds the screen, the column **folded**
  /// this panel away (its content is one back-step away on the higher-priority
  /// sibling that stayed), or narrow mode seats only the focused panel. There is
  /// no peek stripe — fold replaces it. See `routing.instructions.md`.
  hidden,
}

/// The placement of one panel: its x offset from the viewport's left edge, its
/// width, and how it renders.
@immutable
class PanelSlot {
  final double left;
  final double width;
  final PanelVis vis;

  /// True when this (full) panel is the **surviving detail over a folded
  /// master** — a sibling in the same column was folded away under width
  /// pressure, so closing this panel reveals it (a back-step). The close
  /// affordance reads this to show `←` instead of `X`. Only set in column mode;
  /// narrow mode's single-pane back-step is decided from the breakpoint, not
  /// here. See `routing.instructions.md`.
  final bool foldedOver;

  const PanelSlot({
    required this.left,
    required this.width,
    required this.vis,
    this.foldedOver = false,
  });
}

/// The resolved workspace layout: a slot per open panel (parallel to the input
/// lists), the chrome inset actually used, whether the cluster shows, and the
/// map camera padding for the area the panels cover.
@immutable
class WorkspaceLayout {
  /// Slots parallel to the input `left` defs (left-to-right placement order).
  final List<PanelSlot> left;

  /// Slots parallel to the input `right` defs (left-to-right; group right-justified).
  final List<PanelSlot> right;

  /// The left chrome inset in use (the nav rail width in column mode, 0 narrow).
  final double railWidth;

  /// Whether the top-right cluster shows (hidden behind an exclusive/narrow panel).
  final bool clusterVisible;

  /// Map camera padding: the width the panels cover on each side, so a camera
  /// fit lands in the uncovered middle.
  final double mapLeftOverlay;
  final double mapRightOverlay;

  const WorkspaceLayout({
    required this.left,
    required this.right,
    required this.railWidth,
    required this.clusterVisible,
    required this.mapLeftOverlay,
    required this.mapRightOverlay,
  });
}

/// The world_v2 shell's single layout authority — a shared-width allocator over
/// N panels per column (it superseded the old single-panel-per-side budget).
/// Both columns draw from one budget: each panel grows greedily to its ideal
/// (the map fills whatever is left), and when they can't all fit, they compress
/// toward their reasonable-min and only then **fold** — a **parent** (master)
/// drops out of the layout behind its **child** (detail), which keeps the column
/// (not drawn, no stripe; the parent one back-step away), never a full-screen
/// takeover. Folding reads the registry's explicit parent/child/sibling tree
/// ([PanelDef.parent]). Narrow-mode focus seats the most-recently-opened panel
/// ([focusHint]) and falls back to the active leaf of that same tree when there
/// is no recency (a cold deep link). Pure + unit-tested. See
/// `routing.instructions.md`.
abstract class PanelAllocator {
  /// Right margin reserved for the cluster beside the right column.
  static const double clusterGutter = 88.0;

  /// Gap between two adjacent panels in the same column.
  static const double panelGap = 16.0;

  /// Max width of an opaque detail/canvas (chat, course) — the map peeks beyond.
  /// The route-driven center detail caps to this.
  static const double detailMax = 720.0;

  /// Default nav-rail width in column mode (caller may override).
  static const double defaultRailWidth = 73.0;

  static WorkspaceLayout allocate({
    required double viewport,
    required bool isColumnMode,
    required List<PanelDef> left,
    required List<PanelDef> right,
    double railWidth = defaultRailWidth,
    int? focusHint,
  }) {
    // Combined view with stable identity (column + index in its column).
    final all = <_Entry>[
      for (var i = 0; i < left.length; i++) _Entry(PanelColumn.left, i, left[i]),
      for (var i = 0; i < right.length; i++)
        _Entry(PanelColumn.right, i, right[i]),
    ];

    PanelSlot hidden() =>
        const PanelSlot(left: 0, width: 0, vis: PanelVis.hidden);

    // ---- exclusive: one panel holds the whole content area ------------------
    final exclusive = all.where((e) => e.def.exclusive).toList()
      ..sort((a, b) => b.def.priority.compareTo(a.def.priority));
    if (exclusive.isNotEmpty) {
      final winner = exclusive.first;
      final rail = isColumnMode ? railWidth : 0.0;
      final width = math.max(0.0, viewport - rail);
      return _build(left, right, rail,
          clusterVisible: false,
          mapLeftOverlay: viewport,
          mapRightOverlay: 0,
          slot: (e) => e == winner
              ? PanelSlot(left: rail, width: width, vis: PanelVis.full)
              : hidden());
    }

    // ---- narrow: seat ONE panel — the **most-recently-opened** one ([focusHint],
    // the back-stack top) so opening a panel always brings it forward, per
    // Material 3 / Flutter adaptive guidance. When there is no recency to consult
    // — a cold deep link or a refresh, where focusHint is null — fall back to the
    // active **leaf**: an open panel that no other open panel details (no open
    // child names it as `parent`), so a child shows over its parent (the parent is
    // the back target), tie-broken by priority among independent leaves. The leaf
    // link is read across BOTH columns, so a left `session` is focusable over its
    // right-column `analytics` list. The bottom nav / cluster switch to the
    // others. (Pure priority alone is wrong here: it would keep a high-priority
    // live `room` on top of a panel the user just opened — a visible no-op.) See
    // `routing.instructions.md`.
    if (!isColumnMode) {
      if (all.isEmpty) {
        return _build(left, right, 0,
            clusterVisible: true,
            mapLeftOverlay: 0,
            mapRightOverlay: 0,
            slot: (_) => hidden());
      }
      final _Entry focus;
      if (focusHint != null && focusHint >= 0 && focusHint < all.length) {
        focus = all[focusHint];
      } else {
        final leaves = all
            .where((e) => !all.any((c) => c.def.parent == e.def.type))
            .toList();
        final pool = leaves.isEmpty ? all : leaves;
        focus = pool.reduce((a, b) => b.def.priority > a.def.priority ? b : a);
      }
      return _build(left, right, 0,
          clusterVisible: false,
          mapLeftOverlay: viewport,
          mapRightOverlay: 0,
          slot: (e) => e == focus
              ? PanelSlot(left: 0, width: viewport, vis: PanelVis.full)
              : hidden());
    }

    // ---- column mode: shared-width budget across both columns ---------------
    if (all.isEmpty) {
      return _build(left, right, railWidth,
          clusterVisible: true,
          mapLeftOverlay: railWidth,
          mapRightOverlay: 0,
          slot: (_) => hidden());
    }

    final gutter = right.isNotEmpty ? clusterGutter : 0.0;
    final content = math.max(0.0, viewport - railWidth - gutter);

    // One gap between adjacent panels within each column, for whatever set is
    // actually shown.
    double gapsFor(Iterable<_Entry> vis) {
      final l = vis.where((e) => e.column == PanelColumn.left).length;
      final r = vis.where((e) => e.column == PanelColumn.right).length;
      return (math.max(0, l - 1) + math.max(0, r - 1)) * panelGap;
    }

    // Fold a **parent** behind its **child** until the rest fit at their
    // reasonable min (the comfort floor). A fold neither peeks to a stripe nor
    // reserves width — the parent is simply not drawn, its content one back-step
    // away on the child that keeps the column (the detail keeps the column; its
    // master is a pop behind, reached by closing the detail). Only a parent whose
    // child is also visible in the SAME column is foldable: folding is
    // per-column, and a folded panel is reached by closing its child, so a panel
    // with no same-column child to keep the column never folds — it compresses
    // toward its hard min instead. A child is never folded, so a live `room` (the
    // chat list's detail) keeps its session, and a lone right panel (the
    // analytics summary) is never sacrificed to left-column overflow. The map is
    // the backdrop, not a panel, so it isn't sized here — it shows wherever the
    // panels leave room. See `routing.instructions.md`.
    final folded = <_Entry>{};
    while (true) {
      final vis = all.where((e) => !folded.contains(e)).toList();
      if (vis.length <= 1) break;
      final needReasonable =
          vis.fold(0.0, (s, e) => s + e.def.reasonableMin) + gapsFor(vis);
      if (needReasonable <= content) break;
      final foldable = vis
          .where((parent) => vis.any((child) =>
              child.column == parent.column &&
              child.def.parent == parent.def.type))
          .toList();
      if (foldable.isEmpty) break;
      // Among independent master/detail pairs all under pressure, fold the
      // lowest-priority master first (a cross-tree tiebreak).
      foldable.sort((a, b) => a.def.priority.compareTo(b.def.priority));
      folded.add(foldable.first);
    }

    // Size the surviving panels: ideals if they fit, else compress toward their
    // hard mins by distributing the surplus across each panel's headroom.
    final fulls = all.where((e) => !folded.contains(e)).toList();
    final avail = math.max(0.0, content - gapsFor(fulls));
    final sumIdeal = fulls.fold(0.0, (s, e) => s + e.def.idealWidth);
    final sumMin = fulls.fold(0.0, (s, e) => s + e.def.minWidth);
    final headroom =
        fulls.fold(0.0, (s, e) => s + (e.def.idealWidth - e.def.minWidth));
    final widths = <_Entry, double>{};
    for (final e in fulls) {
      if (sumIdeal <= avail || headroom <= 0) {
        widths[e] = e.def.idealWidth;
      } else {
        final surplus = math.max(0.0, avail - sumMin);
        widths[e] = e.def.minWidth +
            (e.def.idealWidth - e.def.minWidth) / headroom * surplus;
      }
    }

    double widthOf(_Entry e) => widths[e] ?? 0.0;

    // Position: left column fills from the rail rightward; right column is
    // right-justified (its group ends at viewport - gutter). Folded panels are
    // skipped — not drawn, no gap reserved — order otherwise preserved.
    // A surviving panel is "folded over" when its own PARENT (same column) was
    // folded away above — closing it reveals that folded master (a back-step),
    // so its close control becomes `←`. Read straight off the explicit parent
    // link, so only the child whose master folded gets the back arrow; an
    // independent panel (a live room with no folded master) keeps a normal close.
    // See `close_affordance.dart` / `routing.instructions.md`.
    bool isFoldedOver(_Entry e) => folded
        .any((f) => f.column == e.column && f.def.type == e.def.parent);

    final placement = <_Entry, PanelSlot>{};
    var x = railWidth;
    for (final e in fulls.where((e) => e.column == PanelColumn.left)) {
      placement[e] = PanelSlot(
          left: x,
          width: widthOf(e),
          vis: PanelVis.full,
          foldedOver: isFoldedOver(e));
      x += widthOf(e) + panelGap;
    }
    final hasLeft = fulls.any((e) => e.column == PanelColumn.left);
    final leftCovered = hasLeft ? x - panelGap : railWidth;

    final rights = fulls.where((e) => e.column == PanelColumn.right).toList();
    final rightTotal = rights.fold(0.0, (s, e) => s + widthOf(e)) +
        math.max(0, rights.length - 1) * panelGap;
    var rx = viewport - gutter - rightTotal;
    final rightStart = rx;
    for (final e in rights) {
      placement[e] = PanelSlot(
          left: rx,
          width: widthOf(e),
          vis: PanelVis.full,
          foldedOver: isFoldedOver(e));
      rx += widthOf(e) + panelGap;
    }

    return _build(left, right, railWidth,
        clusterVisible: true,
        mapLeftOverlay: leftCovered,
        mapRightOverlay: rights.isEmpty ? 0.0 : viewport - rightStart,
        slot: (e) => placement[e] ?? hidden());
  }

  static WorkspaceLayout _build(
    List<PanelDef> left,
    List<PanelDef> right,
    double railWidth, {
    required bool clusterVisible,
    required double mapLeftOverlay,
    required double mapRightOverlay,
    required PanelSlot Function(_Entry) slot,
  }) {
    return WorkspaceLayout(
      left: [
        for (var i = 0; i < left.length; i++)
          slot(_Entry(PanelColumn.left, i, left[i]))
      ],
      right: [
        for (var i = 0; i < right.length; i++)
          slot(_Entry(PanelColumn.right, i, right[i]))
      ],
      railWidth: railWidth,
      clusterVisible: clusterVisible,
      mapLeftOverlay: mapLeftOverlay,
      mapRightOverlay: mapRightOverlay,
    );
  }
}

/// A panel's identity during allocation: which column and index it came from.
/// Equality is by (column, index) so the slot lookup matches the rebuilt list.
@immutable
class _Entry {
  final PanelColumn column;
  final int index;
  final PanelDef def;

  const _Entry(this.column, this.index, this.def);

  @override
  bool operator ==(Object other) =>
      other is _Entry && other.column == column && other.index == index;

  @override
  int get hashCode => Object.hash(column, index);
}
