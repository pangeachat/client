/// Which column a panel belongs to, which fixes its role and its justification.
enum PanelColumn { left, right }

/// Static layout metadata for a panel type. Pure data (no widgets), so the URL
/// parser in `route_facts.dart` and the width allocator can read it without a
/// widget binding; the widget builder is resolved separately by the shell.
/// See `routing.instructions.md`.
class PanelDef {
  final PanelColumn column;

  /// The hard floor used when sizing the panels that survived folding: a panel
  /// compresses no narrower than this. (Folding happens earlier, at
  /// [reasonableMin].)
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

  /// Mutual-exclusion groups: opening this panel as a DETAIL drops every other
  /// open token that shares ANY of these groups, across BOTH columns. The
  /// generalized [WorkspaceNav.openDetail] reads this instead of hand-coding
  /// per-type drop lists. Groups in use:
  ///  - `liveView` — at most one live Matrix timeline (`room`, `session`).
  ///  - `detail` — at most one "zoom" detail across columns (`vocab`, `grammar`,
  ///    `session`). A `session` is in BOTH (it's a live chat AND a detail).
  /// Masters (a list/menu/summary/course card) declare no group; they are
  /// replaced via [WorkspaceNav.openMaster], not by detail exclusivity.
  final Set<String> exclusiveGroups;

  /// Whether this panel hosts deeper pages in its own token param (a *push*):
  /// settings (menu → page → leaf), a course (card → details/invite/analytics),
  /// a room (chat → members/search/invite). Non-pushable panels have no param
  /// depth beyond their identity.
  final bool pushable;

  /// Whether this panel is **map content** — a selection on the world map (a
  /// course, an activity, the add-course flow). On narrow screens map content
  /// renders as a Google-Maps bottom sheet (pin peek → draggable sheet); other
  /// details render as a full-screen push. See `world-v2-architecture`.
  final bool mapContent;

  const PanelDef({
    required this.column,
    required this.minWidth,
    required this.idealWidth,
    required this.priority,
    this.reasonableMinWidth,
    this.exclusive = false,
    this.exclusiveGroups = const {},
    this.pushable = false,
    this.mapContent = false,
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
      exclusiveGroups: {'liveView'},
      pushable: true, // chat → members / search / invite
    ),
    // A completed-activity-session **review** opened from the analytics sessions
    // list — the actual (locked) chat, rendered exactly like a `room`. It is a
    // distinct type so it can carry detail-slot semantics a live `room` must
    // not: a session shares the single "detail" slot with the right-column
    // vocab/grammar details (opening any one closes the others), while a live
    // chat stays independent. Same widths/priority as `room` (it IS a chat).
    // See routing.instructions.md.
    'session': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 80,
      // A session is BOTH a live timeline (one at a time with `room`) AND a
      // "zoom" detail (one at a time with vocab/grammar, across columns).
      exclusiveGroups: {'liveView', 'detail'},
    ),
    'course': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 60,
      pushable: true, // course card → details / invite / analytics / edit
      mapContent: true, // selecting a course scopes the map (mobile: bottom sheet)
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
      pushable: true, // hub → own / browse / private steps
      mapContent: true, // the add-course flow is a map bottom sheet on mobile
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
      pushable: true, // menu → page → leaf
    ),
    'profile': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 600,
      priority: 50,
      pushable: true,
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
      exclusiveGroups: {'detail'},
    ),
    'grammar': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 50,
      exclusiveGroups: {'detail'},
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
