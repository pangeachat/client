import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/chat/chat_details/course_header_actions.dart';
import 'package:fluffychat/routes/chat/chat_details/space_details_content.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/routes/world/left_panel/floor_chevron.dart';
import 'package:fluffychat/routes/world/panel_header.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The miniature course overview shown while a course is selected and its
/// panel is closed (#8736): the course panel's header with the panel shut —
/// the same [PanelHeader] chrome, the course's name, its two header actions
/// ([CourseHeaderActions]) and, trailing them, the same chevron the open card
/// carries, one rotation apart ([ChevronToggle]) — over the course's progress
/// bar at the header's content inset ([CoursePeekProgressBar]). The map sizes
/// it to the course panel's own width, and the card grows out of it and
/// shrinks back into it ([CourseCardReveal]), so the two states read as one
/// surface changing height rather than two widgets swapping (#8866).
///
/// It exists so the scoped map always says WHICH course it is scoped to: with
/// the card closed the only signal was the rail's course highlight, easy to
/// miss, and a learner could start a course activity thinking they were on the
/// world map. It is deliberately **not closeable** — the course context is
/// what it reports, and `?c=` is cleared by the World control, not here — and
/// tapping it anywhere but its actions reopens the course card, whose own
/// header collapses it back the same way ([SpaceDetailsHeader], #8909).
///
/// **Wide only** (#8816). It rides the map's search slot, except with an
/// activity plan open, where it docks above that panel instead
/// ([ActivityCourseDock]). Narrow has no bar at all: the course panel there is
/// always mounted at least at its peek, and that peek is this same header in
/// this same place, so a bar would duplicate the panel it points at. See
/// world-map.instructions.md → The course context bar.
///
/// Owns its own [QuestObjectivesLoader] rather than borrowing the panel's:
/// the panel is closed exactly when this shows, so there is none to borrow.
/// Both read the same cached outline + shared progression, so the two can't
/// disagree about the star totals (quests.instructions.md).
class CourseContextBar extends StatefulWidget {
  final String spaceId;

  /// Browse-order key for the bar's semantic container — the map view passes
  /// [WorkspaceOrder.mapChrome] (#8755); the shell's single-column floating bar
  /// passes none.
  final SemanticsSortKey? sortKey;

  /// Whether the bar carries the course's share / focus-on-map actions. The
  /// dock above an activity plan passes false: the plan's own header carries
  /// the same pair, and one per column is enough (#8866). The chevron stays
  /// either way — it is the way back to the card.
  final bool showActions;

  const CourseContextBar({
    required this.spaceId,
    this.sortKey,
    this.showActions = true,
    super.key,
  });

  /// The space under the progress bar, closing the card at the height the
  /// track needs to breathe.
  static const double bottomInset = 12.0;

  /// The bar's height on wide, stated from its parts: the panel header, the
  /// card body's top inset, the progress track, and [bottomInset]. The course
  /// card's reveal starts and ends at exactly this ([CourseCardReveal]), which
  /// is what lets the bar take over from the card without a visible jump.
  static const double height =
      PanelHeader.wideHeight +
      SpaceDetailsContent.bodyTopInset +
      ProgressBarRow.height +
      bottomInset;

  @override
  State<CourseContextBar> createState() => _CourseContextBarState();
}

class _CourseContextBarState extends State<CourseContextBar> {
  late final QuestObjectivesLoader _objectivesProvider;

  Room? get _room => Matrix.of(context).client.getRoomById(widget.spaceId);

  /// The course + quest the loaded outline belongs to. Re-derived on every
  /// build rather than loaded once in `initState`, because both inputs can
  /// arrive late: switching courses keeps this bar mounted (it is chrome, not
  /// a panel), and a cold link resolves `?c=` before the sync that brings the
  /// room and its course plan.
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _objectivesProvider = QuestObjectivesLoader(
      client: Matrix.of(context).client,
    );
  }

  @override
  void dispose() {
    _objectivesProvider.dispose();
    super.dispose();
  }

  /// Post-frame because this runs from `build`: [loadOutline] seats its
  /// loading state synchronously, and notifying the progress bar's listeners
  /// mid-build is a setState-during-build.
  void _ensureOutline(Room room) {
    final key = '${room.id}:${room.coursePlan?.uuid}';
    if (_loadedFor == key) return;
    _loadedFor = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _objectivesProvider.loadOutline(
        room.coursePlan?.uuid,
        pinnedActivitiesByObjective:
            room.teacherMode.pinnedActivitiesByObjective,
        courseRoomId: room.id,
      );
    });
  }

  /// Reopen the course card over the same `?c=` context — the whole point of
  /// the bar being tappable.
  void _openCourse() =>
      context.go(WorkspaceNav.openCourseTab(GoRouterState.of(context).uri));

  @override
  Widget build(BuildContext context) {
    final room = _room;
    // Nothing to name yet — a `?c=` from a cold link, before the sync that
    // brings its room. The stream rebuilds this the moment the room lands.
    if (room == null) {
      return StreamBuilder(
        stream: Matrix.of(context).client.onSync.stream,
        builder: (context, _) => const SizedBox.shrink(),
      );
    }
    _ensureOutline(room);
    final theme = Theme.of(context);
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
    );

    return Semantics(
      label: L10n.of(context).goToCourse(name),
      sortKey: widget.sortKey,
      button: true,
      container: true,
      child: Material(
        elevation: 4,
        color: theme.colorScheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        // The bar sits on the opaque panel surface, which swallows InkWell's
        // behind-the-child focus highlight (#8724) — so the keyboard
        // affordance is the shared explicit gold ring.
        child: FocusRingTapTarget(
          onTap: _openCourse,
          shape: shape,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The open panel's own header chrome, so title, actions and
              // chevron sit exactly where the card's do (#8866). The name
              // rides the bar's semantics label above; PanelHeader excludes
              // its title from semantics already.
              PanelHeader(
                leading: null,
                title: name,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showActions)
                      CourseHeaderActions(
                        room: room,
                        objectivesProvider: _objectivesProvider,
                      ),
                    // The panel header's chevron, in the same trailing slot
                    // and one rotation apart. Wide follows the disclosure
                    // convention, so this points DOWN to say it reveals the
                    // card and the open panel's points UP to say it hides it
                    // again (#8816). Semantics are excluded because the whole
                    // bar is already one button announcing this very action.
                    ChevronToggle(
                      expanded: false,
                      onTap: _openCourse,
                      meaning: ChevronMeaning.disclosure,
                      excludeSemantics: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: SpaceDetailsContent.bodyTopInset,
                  bottom: CourseContextBar.bottomInset,
                ),
                child: CoursePeekProgressBar(
                  objectivesProvider: _objectivesProvider,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
