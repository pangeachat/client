/// Which column a panel belongs to, which fixes its role and its justification.
enum PanelColumn { left, right }

/// Static layout metadata for a panel type. Pure data (no widgets), so the URL
/// parser in `route_facts.dart` and the width allocator can read it without a
/// widget binding; the widget builder is resolved separately by the shell.
///
/// Two explicit relationships describe the **navigation tree** every surface
/// lives in — one structure the parser, the allocator's fold, and the
/// narrow-mode focus all read, so there is no second system to keep in sync
/// (see `routing.instructions.md`):
///
///  - **[parent]** — the type whose *detail* this panel is (its master). A
///    **child** opens as a coexisting panel beside its parent when width allows
///    and otherwise **stacks** on it: the parent folds away and the child keeps
///    the column, the parent one back-step behind. A `null` parent is a
///    **root** (a section master with nothing behind it).
///  - **[siblingGroups]** — children that share a slot. **Siblings** can't
///    coexist: opening one replaces every other open token in any group it
///    shares (one live view; one cross-column "zoom" detail).
///
/// Most trees are two generations (a chat list → a chat; the analytics summary
/// → a construct detail). Deeper levels (security → password reset) are
/// **pushes** *within* a panel (its own token param, [pushable]), not new
/// panels — so the panel-level tree stays parent → child.
class PanelDef {
  /// This panel's own type — the key it is registered under. Stored on the def
  /// so the allocator can resolve [parent] links (which name a type) without the
  /// registry map. Kept consistent with the map key by `PanelRegistry` (and a
  /// guard test). Defaults to empty for ad-hoc defs built outside the registry.
  final String type;

  final PanelColumn column;

  /// The type whose **detail** this panel is — its parent in the navigation
  /// tree (above). `null` for a root master. A child folds onto / stacks on its
  /// parent under width pressure and, on a narrow screen, its parent is the back
  /// target. The parent is usually the same column (a `room` details the
  /// `chats` list) but may be the other column (a left `session` review details
  /// the right `analytics` sessions list) — folding is per-column, so only a
  /// SAME-column parent/child pair folds, while narrow focus reads the link
  /// across columns. See `routing.instructions.md`.
  final String? parent;

  /// The hard floor used when sizing the panels that survived folding: a panel
  /// compresses no narrower than this. (Folding happens earlier, at
  /// [reasonableMin].)
  final double minWidth;

  /// The narrowest *comfortable* width. Compressing below this is the signal to
  /// fold a master/detail (parent/child) pair into one panel rather than keep
  /// shrinking — the fold trigger (see `routing.instructions.md`). Falls back to
  /// [minWidth] when unset, so a panel with no distinct comfort width never
  /// folds early.
  final double? reasonableMinWidth;

  /// The growth cap (the de-facto max — a panel never grows past its ideal).
  final double idealWidth;

  /// Tiebreak only. Folding and narrow focus are decided by the [parent] tree;
  /// priority breaks ties *between* independent trees — which master folds first
  /// when several master/detail pairs are all under pressure, and which leaf is
  /// the narrow focus when several independent panels are open (a cold deep link
  /// has no recency to consult). A child is never folded and always wins focus
  /// over its own parent regardless of priority.
  final int priority;

  /// An exclusive panel collapses the others while it is open (immersive).
  final bool exclusive;

  /// **Sibling** groups: opening this panel as a DETAIL drops every other open
  /// token that shares ANY of these groups, across BOTH columns — siblings can't
  /// coexist, they replace each other. The generalized [WorkspaceNav.openDetail]
  /// reads this instead of hand-coding per-type drop lists. Groups in use:
  ///  - `liveView` — at most one live Matrix timeline (`room`, `session`).
  ///  - `detail` — at most one "zoom" detail across columns (`vocab`, `grammar`,
  ///    `session`, `practice`). A `session` is in BOTH (it's a live chat AND a
  ///    detail).
  /// Roots (a list/menu/summary/course card) declare no group; they are replaced
  /// by the master-opening helpers (e.g. [WorkspaceNav.setSection]), not by
  /// sibling exclusivity.
  final Set<String> siblingGroups;

  /// Whether this panel hosts deeper pages in its own token param (a *push*):
  /// settings (menu → page → leaf), a course (card → details/invite/analytics),
  /// a room (chat → members/search/invite). Non-pushable panels have no param
  /// depth beyond their identity.
  final bool pushable;

  /// Whether this panel is **map content** — a selection on the world map (a
  /// course, an activity plan, the add-course flow). On a narrow screen the
  /// section surfaces (the chat list, the add-course hub, the course family)
  /// ride the nav widget's expandable cavity over the (scoped) map (`MobileNavWidget`,
  /// via the shell's `cavityIndex`); the activity plan is a start/join flow and
  /// renders full-screen instead. See `routing.instructions.md`.
  final bool mapContent;

  const PanelDef({
    required this.column,
    required this.minWidth,
    required this.idealWidth,
    required this.priority,
    this.type = '',
    this.parent,
    this.reasonableMinWidth,
    this.exclusive = false,
    this.siblingGroups = const {},
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
///
/// Each entry's `type` MUST equal its map key, and each `parent` MUST name
/// another known type — both guarded by `panel_allocator_test`.
abstract class PanelRegistry {
  static const Map<String, PanelDef> defs = {
    // Left — navigation and social.
    // The chat list — a root master. Its detail is a `room`.
    'chats': PanelDef(
      type: 'chats',
      column: PanelColumn.left,
      minWidth: 300,
      reasonableMinWidth: 340,
      idealWidth: 380,
      priority: 30,
    ),
    // A live chat — the chat list's detail (child of `chats`): it opens beside
    // the list and, under width pressure or on a narrow screen, the list folds
    // behind it (back-step). One live timeline at a time (`liveView` sibling).
    'room': PanelDef(
      type: 'room',
      column: PanelColumn.left,
      parent: 'chats',
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 80,
      siblingGroups: {'liveView'},
      pushable: true, // chat → members / search / invite
    ),
    // A completed-activity-session **review** opened from the analytics sessions
    // list — the actual (locked) chat, rendered exactly like a `room`. Its
    // master is that list, which lives in the right-column `analytics` panel, so
    // its `parent` is the cross-column `analytics` (narrow focus reads this so a
    // session is focusable over its list; folding is per-column, so the
    // cross-column link never folds). It is a distinct type from `room` so it can
    // carry detail-slot semantics a live `room` must not: a session shares the
    // single `detail` slot with the right-column vocab/grammar details (opening
    // any one closes the others), while a live chat stays independent. Same
    // widths/priority as `room` (it IS a chat). See routing.instructions.md.
    'session': PanelDef(
      type: 'session',
      column: PanelColumn.left,
      parent: 'analytics',
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 80,
      // A session is BOTH a live timeline (one at a time with `room`) AND a
      // "zoom" detail (one at a time with vocab/grammar, across columns).
      siblingGroups: {'liveView', 'detail'},
    ),
    // An activity plan/preview — a root master opened from a map pin or a
    // course's activity list (`?m=course:<id>` scopes the map; the plan rides
    // over it). It is **map content** like a `course` (narrow → bottom sheet),
    // but unlike a course it claims the single live view: it is a `liveView`
    // sibling of `room`/`session`, so opening an activity drops any open chat and
    // starting the session (which opens a `room` token) drops the activity. Same
    // widths/priority as `room` — it IS the live work surface before the chat
    // exists — so it never shrinks past the chat's floor (the bug #7385 fixed by
    // pulling it out of the canvas-detail exception into the allocator budget). No
    // sub-pages in its param (the plan never drills in; starting opens a room), so
    // not pushable. See `routing.instructions.md`.
    'activity': PanelDef(
      type: 'activity',
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 80,
      siblingGroups: {'liveView'},
      mapContent: true,
    ),
    // A course card — a root master (opened from a map pin / the Courses
    // launcher). Its detail is a `coursepage` management page.
    'course': PanelDef(
      type: 'course',
      column: PanelColumn.left,
      minWidth: 360,
      reasonableMinWidth: 480,
      idealWidth: 720,
      priority: 60,
      mapContent:
          true, // selecting a course scopes the map (mobile: bottom sheet)
    ),
    // A course-management page (invite, edit, access, permissions, emotes,
    // change-course) — the course card's DETAIL (child of `course`): it opens
    // beside the card when width allows and folds to a push when not, exactly
    // like settings menu→page. The card's identity is the `?m=course:<id>`
    // filter, so this reads its space from there (its param is the page, not the
    // space id). One management page at a time (its own `coursepage` sibling
    // group). Pushable for any `/`-leaf. See routing.instructions.md.
    'coursepage': PanelDef(
      type: 'coursepage',
      column: PanelColumn.left,
      parent: 'course',
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 600,
      priority: 65,
      siblingGroups: {'coursepage'},
      pushable: true,
    ),
    // The add-course wizard's first step (own/browse/private), hosted as a
    // left-column root panel instead of the route-driven card. See
    // routing.instructions.md.
    'addcourse': PanelDef(
      type: 'addcourse',
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
    // The settings/profile MENU — a right-column root master. A selected page
    // opens beside it as a `settingspage` detail (child) — coexist when width
    // allows, fold to a push when not.
    'settings': PanelDef(
      type: 'settings',
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 440,
      idealWidth: 520,
      priority: 40,
    ),
    // A settings/profile PAGE (learning, style, security, …) — the menu's DETAIL
    // (child of `settings`). Its param is the full page path; a `/`-path is a
    // leaf reached by a push within this panel (the page's own back pops it). One
    // page at a time (its own `settingsdetail` sibling group), pushable for
    // leaves. See `routing.instructions.md`.
    'settingspage': PanelDef(
      type: 'settingspage',
      column: PanelColumn.right,
      parent: 'settings',
      minWidth: 360,
      reasonableMinWidth: 440,
      // Match the `settings` menu width so a page folded into the menu's slot
      // (under width pressure) doesn't resize and jump the close/back icon
      // when drilling in or out (#7146).
      idealWidth: 520,
      priority: 55,
      siblingGroups: {'settingsdetail'},
      pushable: true,
    ),
    // The analytics summary — a right-column root master. Its details are a
    // `vocab`/`grammar` construct detail and (cross-column) a `session` review.
    'analytics': PanelDef(
      type: 'analytics',
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 40,
    ),
    // A vocabulary construct detail — the analytics summary's DETAIL (child of
    // `analytics`) and a sibling of `grammar`/`session` in the one `detail` slot.
    'vocab': PanelDef(
      type: 'vocab',
      column: PanelColumn.right,
      parent: 'analytics',
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 50,
      siblingGroups: {'detail'},
    ),
    'grammar': PanelDef(
      type: 'grammar',
      column: PanelColumn.right,
      parent: 'analytics',
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 50,
      siblingGroups: {'detail'},
    ),
    // Retired right-panel placeholder: registered (so the layout reserves it)
    // but has no builder yet, so a hand-edited `?right=review` shows the oops
    // panel. Kept intentionally — it is also the neutral root fixture in the nav
    // tests; remove it only alongside migrating those fixtures.
    'review': PanelDef(
      type: 'review',
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 488,
      priority: 70,
    ),
    // A practice session — the exercise flow that takes over the analytics
    // surface. It is a right-column panel like everything else (not fullscreen),
    // but while it is open the analytics master + any vocab/grammar list/detail
    // are closed and cannot be opened alongside it: it is a `detail` sibling (so
    // opening a vocab/grammar/session detail drops it, and vice versa) and
    // `WorkspaceNav.openPractice` additionally clears the analytics master. It
    // CLEARS rather than coexists-with analytics, so it has no `parent` (backing
    // out of practice on a narrow screen returns to the map, not analytics). Its
    // param is the construct type (`vocab`/`morph`). See routing.instructions.md.
    'practice': PanelDef(
      type: 'practice',
      column: PanelColumn.right,
      minWidth: 360,
      reasonableMinWidth: 420,
      idealWidth: 520,
      priority: 55,
      siblingGroups: {'detail'},
    ),
  };

  static PanelDef? defFor(String type) => defs[type];
}
