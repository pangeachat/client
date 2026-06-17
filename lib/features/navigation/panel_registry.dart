/// Which column a panel belongs to, which fixes its role and its justification.
enum PanelColumn { left, right }

/// Static layout metadata for a panel type. Pure data (no widgets), so the URL
/// parser in `route_facts.dart` and the width allocator can read it without a
/// widget binding; the widget builder is resolved separately by the shell.
/// See `routing.instructions.md`.
class PanelDef {
  final PanelColumn column;

  /// The hard floor: below this the panel must yield (fold, then peer-hide).
  final double minWidth;

  /// The narrowest *comfortable* width. Compressing below this is the signal to
  /// fold a master/detail pair into one panel rather than keep shrinking — the
  /// fold trigger (see `routing.instructions.md`). Falls back to [minWidth] when
  /// unset, so a panel with no distinct comfort width never folds early.
  final double? reasonableMinWidth;

  /// The growth cap (the de-facto max — a panel never grows past its ideal).
  final double idealWidth;

  /// Higher-priority panels stay full longer and collapse last under pressure.
  final int priority;

  /// An exclusive panel collapses the others while it is open (immersive).
  final bool exclusive;

  const PanelDef({
    required this.column,
    required this.minWidth,
    required this.idealWidth,
    required this.priority,
    this.reasonableMinWidth,
    this.exclusive = false,
  });

  /// The comfort floor the fold trigger uses: an explicit [reasonableMinWidth],
  /// or the hard [minWidth] when none is set.
  double get reasonableMin => reasonableMinWidth ?? minWidth;
}

/// The known panel types. Adding a surface is one entry here plus its builder in
/// the shell. Widths reuse the shell's established sizes: list 380, content max
/// 720, opaque floor 360, right card 488. Priorities and widths are tunable.
abstract class PanelRegistry {
  static const Map<String, PanelDef> defs = {
    // Left — navigation and social.
    'chats': PanelDef(
      column: PanelColumn.left,
      minWidth: 300,
      reasonableMinWidth: 340,
      idealWidth: 380,
      priority: 30,
    ),
    'room': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 80,
    ),
    'course': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 60,
    ),
    // The add-course wizard's first step (own/browse/private), hosted as a
    // left-column panel instead of the route-driven card. See
    // routing.instructions.md.
    'addcourse': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 600,
      priority: 45,
    ),
    // Right — personal review and account surfaces.
    // settings + profile are one right-column panel (world_v2); the active
    // settings sub-page is the `settings` token's param. See
    // routing.instructions.md.
    'settings': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 600,
      priority: 50,
    ),
    'profile': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 600,
      priority: 50,
    ),
    'analytics': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 40,
    ),
    'vocab': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 50,
    ),
    'grammar': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 50,
    ),
    'review': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 70,
    ),
  };

  static PanelDef? defFor(String type) => defs[type];
}
