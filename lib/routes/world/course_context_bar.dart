import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';
import 'package:fluffychat/routes/chat/chat_details/course_header_actions.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_progress_bar.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The miniature course overview that takes the map search bar's slot while a
/// course is selected and its panel is closed (#8736): the course's name, its
/// two header actions ([CourseHeaderActions]), and its progress bar — the
/// course panel's header with the panel closed.
///
/// It exists so the scoped map always says WHICH course it is scoped to: with
/// the card closed the only signal was the rail's course highlight, easy to
/// miss, and a learner could start a course activity thinking they were on the
/// world map. It is deliberately **not closeable** — the course context is
/// what it reports, and `?c=` is cleared by the World control, not here — and
/// tapping it anywhere but its actions reopens the course card.
///
/// Owns its own [QuestObjectivesLoader] rather than borrowing the panel's:
/// the panel is closed exactly when this shows, so there is none to borrow.
/// Both read the same cached outline + shared progression, so the two can't
/// disagree about the star totals (quests.instructions.md).
class CourseContextBar extends StatefulWidget {
  final String spaceId;

  const CourseContextBar({required this.spaceId, super.key});

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 4.0, 4.0, 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      // The name rides the bar's own semantics label above.
                      child: ExcludeSemantics(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    CourseHeaderActions(
                      room: room,
                      objectivesProvider: _objectivesProvider,
                    ),
                  ],
                ),
                CourseProgressBar(objectivesProvider: _objectivesProvider),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
