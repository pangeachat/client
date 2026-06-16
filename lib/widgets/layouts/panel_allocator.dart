import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/navigation/panel_registry.dart';

/// How a panel renders for the resolved layout.
enum PanelVis {
  /// Sized between its min and ideal width.
  full,

  /// Collapsed to a thin stripe/tab because there was no room to seat it.
  peek,

  /// Not shown (an exclusive panel is holding the screen, or narrow mode seats
  /// only the focused panel).
  hidden,
}

/// The placement of one panel: its x offset from the viewport's left edge, its
/// width, and how it renders.
@immutable
class PanelSlot {
  final double left;
  final double width;
  final PanelVis vis;

  const PanelSlot({required this.left, required this.width, required this.vis});
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

/// The world_v2 shell's single layout authority. Replaces the old
/// `ShellLayout.resolve` single-panel-per-side budget with a shared-width
/// allocator over N panels per column. Both columns draw from one budget: each
/// panel grows greedily to its ideal (the map fills whatever is left), and when
/// they can't all fit, they compress toward their per-panel floors and only then
/// does the lowest-priority panel collapse to a peek — never a full-screen
/// takeover. Pure + unit-tested. See `routing.instructions.md`.
abstract class PanelAllocator {
  /// Right margin reserved for the cluster beside the right column.
  static const double clusterGutter = 88.0;

  /// Width of a collapsed panel's stripe/tab.
  static const double peekWidth = 44.0;

  /// Gap between two adjacent panels in the same column.
  static const double panelGap = 16.0;

  /// Default nav-rail width in column mode (caller may override).
  static const double defaultRailWidth = 73.0;

  static WorkspaceLayout allocate({
    required double viewport,
    required bool isColumnMode,
    required List<PanelDef> left,
    required List<PanelDef> right,
    double railWidth = defaultRailWidth,
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

    // ---- narrow: seat the highest-priority panel; bottom nav switches -------
    if (!isColumnMode) {
      if (all.isEmpty) {
        return _build(left, right, 0,
            clusterVisible: true,
            mapLeftOverlay: 0,
            mapRightOverlay: 0,
            slot: (_) => hidden());
      }
      final focus = (all.toList()
            ..sort((a, b) => b.def.priority.compareTo(a.def.priority)))
          .first;
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
    final gapTotal = math.max(0, left.length - 1) * panelGap +
        math.max(0, right.length - 1) * panelGap;

    // Collapse the lowest-priority full panel to a peek until the rest can meet
    // their minimums within the budget (the map is the backdrop, not a panel, so
    // it isn't sized here — it simply shows wherever the panels leave room).
    final peeked = <_Entry>{};
    while (true) {
      final fulls = all.where((e) => !peeked.contains(e)).toList();
      final needMin = fulls.fold(0.0, (s, e) => s + e.def.minWidth) +
          peeked.length * peekWidth +
          gapTotal;
      if (needMin <= content || fulls.isEmpty) break;
      fulls.sort((a, b) => a.def.priority.compareTo(b.def.priority));
      peeked.add(fulls.first);
    }

    // Size the full panels: ideals if they fit, else compress toward mins by
    // distributing the available surplus across each panel's headroom.
    final fulls = all.where((e) => !peeked.contains(e)).toList();
    final avail =
        math.max(0.0, content - peeked.length * peekWidth - gapTotal);
    final sumIdeal = fulls.fold(0.0, (s, e) => s + e.def.idealWidth);
    final sumMin = fulls.fold(0.0, (s, e) => s + e.def.minWidth);
    final headroom = fulls.fold(0.0, (s, e) => s + (e.def.idealWidth - e.def.minWidth));
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
    for (final e in peeked) {
      widths[e] = peekWidth;
    }

    double widthOf(_Entry e) => widths[e] ?? 0.0;
    PanelVis visOf(_Entry e) => peeked.contains(e) ? PanelVis.peek : PanelVis.full;

    // Position: left column fills from the rail rightward; right column is
    // right-justified (its group ends at viewport - gutter), order preserved.
    final placement = <_Entry, PanelSlot>{};
    var x = railWidth;
    for (final e in all.where((e) => e.column == PanelColumn.left)) {
      placement[e] = PanelSlot(left: x, width: widthOf(e), vis: visOf(e));
      x += widthOf(e) + panelGap;
    }
    final leftCovered = left.isEmpty ? railWidth : x - panelGap;

    final rights = all.where((e) => e.column == PanelColumn.right).toList();
    final rightTotal = rights.fold(0.0, (s, e) => s + widthOf(e)) +
        math.max(0, rights.length - 1) * panelGap;
    var rx = viewport - gutter - rightTotal;
    final rightStart = rx;
    for (final e in rights) {
      placement[e] = PanelSlot(left: rx, width: widthOf(e), vis: visOf(e));
      rx += widthOf(e) + panelGap;
    }

    return _build(left, right, railWidth,
        clusterVisible: true,
        mapLeftOverlay: leftCovered,
        mapRightOverlay: right.isEmpty ? 0.0 : viewport - rightStart,
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
