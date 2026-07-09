import 'package:fluffychat/features/navigation/panel_types_enum.dart';

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
sealed class PanelDef {
  /// This panel's own type — the key it is registered under. Stored on the def
  /// so the allocator can resolve [parent] links (which name a type) without the
  /// registry map. Kept consistent with the map key by `PanelRegistry` (and a
  /// guard test). Defaults to empty for ad-hoc defs built outside the registry.
  final PanelTypesEnum type;

  final PanelColumn column;

  /// The type whose **detail** this panel is — its parent in the navigation
  /// tree (above). `null` for a root master. A child folds onto / stacks on its
  /// parent under width pressure and, on a narrow screen, its parent is the back
  /// target. The parent is usually the same column (a `room` details the
  /// `chats` list) but may be the other column (a left `session` review details
  /// the right `analytics` sessions list) — folding is per-column, so only a
  /// SAME-column parent/child pair folds, while narrow focus reads the link
  /// across columns. See `routing.instructions.md`.
  final PanelTypesEnum? parent;

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
    required this.type,
    this.parent,
    this.reasonableMinWidth,
    this.siblingGroups = const {},
    this.pushable = false,
    this.mapContent = false,
  });

  /// The comfort floor the fold trigger uses: an explicit [reasonableMinWidth],
  /// or the hard [minWidth] when none is set.
  double get reasonableMin => reasonableMinWidth ?? minWidth;
}

class ChatsPanelDef extends PanelDef {
  const ChatsPanelDef({
    super.type = PanelTypesEnum.chats,
    super.column = PanelColumn.left,
    super.minWidth = 300,
    super.reasonableMinWidth = 340,
    super.idealWidth = 380,
    super.priority = 30,
  });
}

class RoomPanelDef extends PanelDef {
  const RoomPanelDef({
    super.type = PanelTypesEnum.room,
    super.column = PanelColumn.left,
    super.parent = PanelTypesEnum.chats,
    super.minWidth = 360,
    super.reasonableMinWidth = 480,
    super.idealWidth = 720,
    super.priority = 80,
    super.siblingGroups = const {'liveView'},
    super.pushable = true, // chat → members / search / invite
  });
}

class SessionPanelDef extends PanelDef {
  const SessionPanelDef({
    super.type = PanelTypesEnum.session,
    super.column = PanelColumn.left,
    super.parent = PanelTypesEnum.analytics,
    super.minWidth = 360,
    super.reasonableMinWidth = 480,
    super.idealWidth = 720,
    super.priority = 80,
    // A session is BOTH a live timeline (one at a time with `room`) AND a
    // "zoom" detail (one at a time with vocab/grammar, across columns).
    super.siblingGroups = const {'liveView', 'detail'},
  });
}

class ActivityPanelDef extends PanelDef {
  const ActivityPanelDef({
    super.type = PanelTypesEnum.activity,
    super.column = PanelColumn.left,
    super.minWidth = 360,
    super.reasonableMinWidth = 480,
    super.idealWidth = 720,
    super.priority = 80,
    super.siblingGroups = const {'liveView'},
    super.mapContent = true,
  });
}

class CoursePanelDef extends PanelDef {
  const CoursePanelDef({
    super.type = PanelTypesEnum.course,
    super.column = PanelColumn.left,
    super.minWidth = 360,
    super.reasonableMinWidth = 480,
    super.idealWidth = 720,
    super.priority = 60,
    super.mapContent =
        true, // selecting a course scopes the map (mobile: bottom sheet)
  });
}

class CoursePagePanelDef extends PanelDef {
  const CoursePagePanelDef({
    super.type = PanelTypesEnum.coursepage,
    super.column = PanelColumn.left,
    super.parent = PanelTypesEnum.course,
    super.minWidth = 360,
    super.reasonableMinWidth = 440,
    super.idealWidth = 600,
    super.priority = 65,
    super.siblingGroups = const {'coursepage'},
    super.pushable = true,
  });
}

class AddCoursePanelDef extends PanelDef {
  const AddCoursePanelDef({
    super.type = PanelTypesEnum.addcourse,
    super.column = PanelColumn.left,
    super.minWidth = 360,
    super.reasonableMinWidth = 440,
    super.idealWidth = 600,
    super.priority = 45,
    super.pushable = true, // hub → own / browse / private steps
    super.mapContent =
        true, // the add-course flow is a map bottom sheet on mobile
  });
}

class SettingsPanelDef extends PanelDef {
  const SettingsPanelDef({
    super.type = PanelTypesEnum.settings,
    super.column = PanelColumn.right,
    super.minWidth = 360,
    super.reasonableMinWidth = 440,
    super.idealWidth = 520,
    super.priority = 40,
  });
}

class SettingsPagePanelDef extends PanelDef {
  const SettingsPagePanelDef({
    super.type = PanelTypesEnum.settingspage,
    super.column = PanelColumn.right,
    super.parent = PanelTypesEnum.settings,
    super.minWidth = 360,
    super.reasonableMinWidth = 440,
    // Match the `settings` menu width so a page folded into the menu's slot
    // (under width pressure) doesn't resize and jump the close/back icon
    // when drilling in or out (#7146).
    super.idealWidth = 520,
    super.priority = 55,
    super.siblingGroups = const {'settingsdetail'},
    super.pushable = true,
  });
}

class AnalyticsPanelDef extends PanelDef {
  const AnalyticsPanelDef({
    super.type = PanelTypesEnum.analytics,
    super.column = PanelColumn.right,
    super.minWidth = 360,
    super.reasonableMinWidth = 420,
    super.idealWidth = 488,
    super.priority = 40,
  });
}

class VocabPanelDef extends PanelDef {
  const VocabPanelDef({
    super.type = PanelTypesEnum.vocab,
    super.column = PanelColumn.right,
    super.parent = PanelTypesEnum.analytics,
    super.minWidth = 360,
    super.reasonableMinWidth = 420,
    super.idealWidth = 488,
    super.priority = 50,
    super.siblingGroups = const {'detail'},
  });
}

class GrammarPanelDef extends PanelDef {
  const GrammarPanelDef({
    super.type = PanelTypesEnum.grammar,
    super.column = PanelColumn.right,
    super.parent = PanelTypesEnum.analytics,
    super.minWidth = 360,
    super.reasonableMinWidth = 420,
    super.idealWidth = 488,
    super.priority = 50,
    super.siblingGroups = const {'detail'},
  });
}

class ReviewPanelDef extends PanelDef {
  const ReviewPanelDef({
    super.type = PanelTypesEnum.review,
    super.column = PanelColumn.right,
    super.minWidth = 360,
    super.reasonableMinWidth = 420,
    super.idealWidth = 488,
    super.priority = 70,
  });
}

class PracticePanelDef extends PanelDef {
  const PracticePanelDef({
    super.type = PanelTypesEnum.practice,
    super.column = PanelColumn.right,
    super.minWidth = 360,
    super.reasonableMinWidth = 420,
    super.idealWidth = 520,
    super.priority = 55,
    super.siblingGroups = const {'detail'},
  });
}

class NewPrivateChatPanelDef extends PanelDef {
  const NewPrivateChatPanelDef({
    super.type = PanelTypesEnum.newprivatechat,
    super.column = PanelColumn.left,
    super.parent = PanelTypesEnum.chats,
    super.minWidth = 300,
    super.reasonableMinWidth = 380,
    super.idealWidth = 400,
    super.priority = 10,
  });
}
