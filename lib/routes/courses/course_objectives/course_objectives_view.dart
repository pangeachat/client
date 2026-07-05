import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';

/// The objective groups that should render: those with at least one activity.
/// An activity-less objective would otherwise show a header over a fixed-height
/// activity-card row that is all empty space, so it is dropped (#7114). Null
/// (still loading / no data) maps to an empty list.
@visibleForTesting
List<QuestObjectiveGroup> objectiveGroupsWithActivities(
  List<QuestObjectiveGroup>? groups,
) => (groups ?? const <QuestObjectiveGroup>[])
    .where((g) => g.activities.isNotEmpty)
    .toList();

/// The Activities / Course-plan tab of a selected course (world_v2): the
/// course's learning objectives, each with the activities that satisfy it.
/// Objectives are the unlockable unit; activities are interchangeable
/// options. Objectives have no icons yet — a placeholder stands in.
/// Tapping an activity opens it as a first-class world object (`/<uuid>`).
class CourseObjectivesList extends StatefulWidget {
  /// The course room, when shown inside a JOINED course (the card's Course Plan
  /// tab). Null in a PREVIEW of an unjoined plan (SelectedCourse), where
  /// [questId] is supplied directly and there is no completion / in-room
  /// activity context.
  final Room? room;

  /// The v3 quest id whose outline to render. Defaults to the room's
  /// `coursePlan.uuid` when [room] is given; required when [room] is null.
  final String? questId;

  /// Per-activity completion, e.g. `controller.roomSummariesModel
  /// .hasCompletedActivity`. Null in a preview → no completion overlay.
  final bool Function(String userId, String activityId)? hasCompletedActivity;

  /// Shrink-wrap the objective list instead of filling/scrolling its own
  /// viewport. Set true when embedded inside another scroll view (the
  /// SelectedCourse / preview pages place this inside an outer `ListView`);
  /// leave false when given a bounded slot (the card's Course Plan tab uses an
  /// `Expanded`).
  final bool shrinkWrap;

  const CourseObjectivesList({
    this.room,
    this.questId,
    this.hasCompletedActivity,
    this.shrinkWrap = false,
    super.key,
  });

  @override
  State<CourseObjectivesList> createState() => _CourseObjectivesListState();
}

class _CourseObjectivesListState extends State<CourseObjectivesList> {
  late Future<List<QuestObjectiveGroup>> _groupsFuture;
  final ScrollController _scrollController = ScrollController();

  String? get _questId => widget.questId ?? widget.room?.coursePlan?.uuid;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll this list from a vertical mouse wheel anywhere over the panel —
  /// including the gaps between cards and the objective headers. Those areas are
  /// hit-transparent, so without an OPAQUE listener the wheel falls straight
  /// through this floating panel to the persistent world map below and zooms it,
  /// while the list (whose own Scrollable only captures a wheel landing on a
  /// card) never moves. Registering on the shared [PointerSignalResolver] yields
  /// to the list's native Scrollable when the wheel IS over a card (it registers
  /// first, being deeper in the tree) and only drives the controller for the
  /// fall-through areas — so there is no double-scroll. See routing.instructions.md.
  void _claimVerticalScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (!_scrollController.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      resolved as PointerScrollEvent;
      final position = _scrollController.position;
      final target = (position.pixels + resolved.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
  }

  @override
  void didUpdateWidget(covariant CourseObjectivesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questId != widget.questId ||
        oldWidget.room?.id != widget.room?.id) {
      _groupsFuture = _load();
    }
  }

  Future<List<QuestObjectiveGroup>> _load() async {
    // world_v2 → v3: the course space's coursePlan.uuid (or the previewed
    // plan's uuid) points at a quest-plans id. The outline (Missions + their
    // activities) comes from the v3 quest read layer; the v1
    // course-plans/topics fan-out is retired.
    final questId = _questId;
    if (questId == null) return [];
    final outline = await QuestRepo.outline(questId);
    return outline.groups;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuestObjectiveGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        // Activity-less objectives are dropped (see [objectiveGroupsWithActivities],
        // #7114). Filtering before the empty check means an outline that is ALL
        // activity-less still falls through to the "no activities" message.
        final groups = objectiveGroupsWithActivities(snapshot.data);
        if (groups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                L10n.of(context).noActivitiesFound,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          );
        }
        final list = ListView.separated(
          controller: widget.shrinkWrap ? null : _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          shrinkWrap: widget.shrinkWrap,
          physics: widget.shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 24.0),
          itemBuilder: (context, i) => _ObjectiveSection(
            index: i,
            group: groups[i],
            room: widget.room,
            hasCompletedActivity: widget.hasCompletedActivity,
          ),
        );
        // In a preview the list is embedded in an outer scroll view (shrinkWrap)
        // with no map behind it, so a wheel can't leak — return it bare. The
        // standalone course-card panel floats over the map, so capture the wheel
        // OPAQUELY across the whole panel: the gaps between cards and the
        // objective headers are hit-transparent, and a wheel there would zoom the
        // map instead of scrolling the list. See [_claimVerticalScroll].
        if (widget.shrinkWrap) return list;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _claimVerticalScroll,
          child: list,
        );
      },
    );
  }
}

class _ObjectiveSection extends StatelessWidget {
  final int index;
  final QuestObjectiveGroup group;

  /// Null in a preview (unjoined plan): no completion overlay, and tapping an
  /// activity opens it standalone rather than as an in-course `?activity=`
  /// overlay.
  final Room? room;
  final bool Function(String userId, String activityId)? hasCompletedActivity;

  const _ObjectiveSection({
    required this.index,
    required this.group,
    required this.room,
    required this.hasCompletedActivity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final cardWidth = isColumnMode ? 160.0 : 120.0;
    final cardHeight = isColumnMode ? 280.0 : 200.0;
    final userId = room?.client.userID;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Objective header: placeholder icon + the can-do statement.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ObjectivePlaceholderIcon(index: index),
            const SizedBox(width: 12.0),
            Expanded(
              child: Text(
                group.objective.objective,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        // The activities that satisfy this objective.
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: group.activities.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16.0),
            itemBuilder: (context, i) {
              final ref = group.activities[i];
              final complete =
                  userId != null &&
                  (hasCompletedActivity?.call(userId, ref.activityId) ?? false);
              final starsEarned =
                  room?.client.userStarsByActivity[ref.activityId] ?? 0;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  // In a preview (no room), open the activity as a standalone
                  // world object (`/<activityId>`). In a joined course, open it
                  // as the focused detail over the map: DROP the `left=course`
                  // card (so it isn't left blank beside the activity) but KEEP
                  // the `?m=course:` filter. That surviving course scope is what
                  // marks this plan as the card's child: its close is a back-arrow
                  // that reopens the card (a pin-opened plan drops the scope and so
                  // closes with an X). The map stays course-scoped and zooms to
                  // this activity (`mapFocusFor` → `ActivityFocus`). See
                  // routing.instructions.md.
                  onTap: () {
                    if (room == null) {
                      // The legacy standalone `/<uuid>` path is an inbound shim
                      // only; this is behavior-neutral (the legacy path also
                      // dropped context) but now token-native. See
                      // routing.instructions.md.
                      context.go(
                        WorkspaceNav.openActivity(
                          GoRouterState.of(context).uri,
                          ref.activityId,
                          clearContext: true,
                        ),
                      );
                      return;
                    }
                    // Immersive in-course open: the token producer drops the
                    // `left=course` card (and any right panel) and keeps the
                    // `?m=course:` scope, so the plan takes the card's slot and
                    // backs out to it. A video hero autostarts (muted).
                    context.go(
                      WorkspaceNav.openCourseActivity(
                        room!.id,
                        ref.activityId,
                        autoplay:
                            ref.plan.heroBlock?.isVideo == true ||
                            ref.plan.heroBlock?.isYoutube == true,
                      ),
                    );
                  },
                  child: Stack(
                    children: [
                      ActivitySuggestionCard(
                        activity: ref.plan,
                        width: cardWidth,
                        height: cardHeight,
                        fontSize: isColumnMode ? 16.0 : 12.0,
                        fontSizeSmall: isColumnMode ? 12.0 : 8.0,
                        iconSize: isColumnMode ? 12.0 : 8.0,
                        starsEarned: starsEarned,
                      ),
                      if (complete)
                        Container(
                          width: cardWidth,
                          height: cardHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.0),
                            color: theme.colorScheme.surface.withAlpha(180),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/pangea/check.svg',
                              width: 48.0,
                              height: 48.0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Placeholder objective icon until real learning-objective icons exist.
/// Deterministic color per position so the list reads as distinct items.
class _ObjectivePlaceholderIcon extends StatelessWidget {
  final int index;
  const _ObjectivePlaceholderIcon({required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    return Container(
      width: 40.0,
      height: 40.0,
      decoration: BoxDecoration(
        color: palette[index % palette.length],
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Icon(Icons.flag_outlined, size: 22.0, color: scheme.onSurface),
    );
  }
}
