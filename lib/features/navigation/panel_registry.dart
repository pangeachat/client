import 'package:fluffychat/features/navigation/panel_types_enum.dart';

/// Which column a panel belongs to, which fixes its role and its justification.
enum PanelColumn { left, right }

/// The three width families every panel draws from (#7572). Panels that can
/// replace each other in a slot share a family, so navigating between them
/// never changes the column's width — the only width step left is the
/// deliberate list↔wide difference. Defined once here (not per-def literals)
/// so the families can't drift apart.
///
///  - **list** — the thin index columns (the chat list, the DM-create picker).
///  - **wide** — the live/content surfaces: a chat, a session, an activity or
///    course card, and the course flow pages (details / invite / edit / add),
///    which host forms and media and want the same room.
///  - **tool** — the entire right column (settings, analytics + its details,
///    practice), one width for every tool panel.
abstract class PanelWidths {
  static const double listMin = 300;
  static const double listComfort = 340;
  static const double listIdeal = 380;

  static const double wideMin = 360;
  static const double wideComfort = 480;
  static const double wideIdeal = 720;

  static const double toolMin = 360;
  static const double toolComfort = 440;
  static const double toolIdeal = 520;
}

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
  /// AND the activity plan ride the nav widget's expandable cavity over the
  /// (scoped) map (`MobileNavWidget`, via the shell's `cavityIndex`) — the
  /// plan as a half-open sheet with the camera on its pin, the Google Maps
  /// UX. See `routing.instructions.md`.
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
    super.minWidth = PanelWidths.listMin,
    super.reasonableMinWidth = PanelWidths.listComfort,
    super.idealWidth = PanelWidths.listIdeal,
    super.priority = 30,
  }) : super(type: PanelTypesEnum.chats, column: PanelColumn.left);
}

class RoomPanelDef extends PanelDef {
  const RoomPanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
    super.priority = 80,
  }) : super(
         type: PanelTypesEnum.room,
         column: PanelColumn.left,
         parent: PanelTypesEnum.chats,
         siblingGroups: const {'liveView'},
         pushable: true, // chat → members / search / invite
       );
}

class SessionPanelDef extends PanelDef {
  const SessionPanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
  }) : super(
         type: PanelTypesEnum.session,
         column: PanelColumn.left,
         parent: PanelTypesEnum.analytics,
         priority: 80,
         // A session is BOTH a live timeline (one at a time with `room`) AND a
         // "zoom" detail (one at a time with vocab/grammar, across columns).
         siblingGroups: const {'liveView', 'detail'},
       );
}

class ActivityPanelDef extends PanelDef {
  const ActivityPanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
  }) : super(
         type: PanelTypesEnum.activity,
         column: PanelColumn.left,
         priority: 80,
         siblingGroups: const {'liveView'},
         mapContent: true,
       );
}

class CoursePanelDef extends PanelDef {
  const CoursePanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
  }) : super(
         idealWidth: PanelWidths.wideIdeal,
         type: PanelTypesEnum.course,
         column: PanelColumn.left,
         priority: 60,
         mapContent:
             true, // selecting a course scopes the map (mobile: bottom sheet)
       );
}

class CoursePagePanelDef extends PanelDef {
  const CoursePagePanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
  }) : super(
         type: PanelTypesEnum.coursepage,
         column: PanelColumn.left,
         parent: PanelTypesEnum.course,
         priority: 65,
         siblingGroups: const {'coursepage'},
         pushable: true,
       );
}

class AddCoursePanelDef extends PanelDef {
  const AddCoursePanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
  }) : super(
         type: PanelTypesEnum.addcourse,
         column: PanelColumn.left,
         priority: 45,
         mapContent:
             true, // the add-course flow is a map bottom sheet on mobile
       );
}

class AddCoursePagePanelDef extends PanelDef {
  const AddCoursePagePanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
  }) : super(
         type: PanelTypesEnum.addcoursepage,
         column: PanelColumn.left,
         priority: 45,
         pushable: true, // hub → own / browse / private steps
         parent: PanelTypesEnum.addcourse,
         mapContent:
             true, // the add-course flow is a map bottom sheet on mobile
       );
}

class SettingsPanelDef extends PanelDef {
  const SettingsPanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.settings,
         column: PanelColumn.right,
         priority: 40,
       );
}

class SettingsPagePanelDef extends PanelDef {
  const SettingsPagePanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    // Same tool family as the `settings` menu so a page folded into the menu's
    // slot (under width pressure) doesn't resize and jump the close/back icon
    // when drilling in or out (#7146) — now guaranteed by the shared family.
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.settingspage,
         column: PanelColumn.right,
         parent: PanelTypesEnum.settings,
         priority: 55,
         siblingGroups: const {'settingsdetail'},
         pushable: true,
       );
}

class AnalyticsPanelDef extends PanelDef {
  const AnalyticsPanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.analytics,
         column: PanelColumn.right,
         priority: 40,
       );
}

class VocabPanelDef extends PanelDef {
  const VocabPanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.vocab,
         column: PanelColumn.right,
         parent: PanelTypesEnum.analytics,
         priority: 50,
         siblingGroups: const {'detail'},
       );
}

class GrammarPanelDef extends PanelDef {
  const GrammarPanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.grammar,
         column: PanelColumn.right,
         parent: PanelTypesEnum.analytics,
         priority: 50,
         siblingGroups: const {'detail'},
       );
}

class ReviewPanelDef extends PanelDef {
  const ReviewPanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.review,
         column: PanelColumn.right,
         priority: 70,
       );
}

class PracticePanelDef extends PanelDef {
  const PracticePanelDef({
    super.minWidth = PanelWidths.toolMin,
    super.reasonableMinWidth = PanelWidths.toolComfort,
    super.idealWidth = PanelWidths.toolIdeal,
  }) : super(
         type: PanelTypesEnum.practice,
         column: PanelColumn.right,
         priority: 55,
         siblingGroups: const {'detail'},
       );
}

class NewPrivateChatPanelDef extends PanelDef {
  const NewPrivateChatPanelDef({
    super.minWidth = PanelWidths.listMin,
    super.reasonableMinWidth = PanelWidths.listComfort,
    super.idealWidth = PanelWidths.listIdeal,
  }) : super(
         type: PanelTypesEnum.newprivatechat,
         column: PanelColumn.left,
         parent: PanelTypesEnum.chats,
         priority: 10,
       );
}

class ArchivePanelDef extends PanelDef {
  const ArchivePanelDef({
    super.minWidth = PanelWidths.listMin,
    super.reasonableMinWidth = PanelWidths.listComfort,
    super.idealWidth = PanelWidths.listIdeal,
    super.priority = 10,
  }) : super(type: PanelTypesEnum.archive, column: PanelColumn.left);
}

class ArchivedRoomPanelDef extends PanelDef {
  const ArchivedRoomPanelDef({
    super.minWidth = PanelWidths.wideMin,
    super.reasonableMinWidth = PanelWidths.wideComfort,
    super.idealWidth = PanelWidths.wideIdeal,
    super.priority = 30,
  }) : super(
         type: PanelTypesEnum.archivedroom,
         column: PanelColumn.left,
         parent: PanelTypesEnum.archive,
         siblingGroups: const {'liveView'},
         pushable: true, // chat → members / search / invite
       );
}
