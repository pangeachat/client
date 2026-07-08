import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef _ObjectivesLoader =
    ValueNotifier<AsyncState<List<QuestObjectiveGroup>>>;

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
  final _ObjectivesLoader _objectivesLoader = _ObjectivesLoader(AsyncLoading());
  final ScrollController _scrollController = ScrollController();

  /// The shared progression rollup behind the star display — same inputs and
  /// resolver as the world map, so the numbers can never disagree
  /// (quests.instructions.md, "Star display on the course panel"). Empty in a
  /// preview (no room → no learner progress to show) and until the first
  /// resolve completes.
  final JoinedObjectiveCache _objectiveCache = JoinedObjectiveCache();
  ProgressionResolution _progression = ProgressionResolution.empty;

  /// This quest's ordered Mission ids, for the header's quest-star summary.
  List<String> _orderedMissionIds = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _objectivesLoader.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? get _questId => widget.questId ?? widget.room?.coursePlan?.uuid;

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
      _progression = ProgressionResolution.empty;
      _load();
    }
  }

  Future<void> _load() async {
    // world_v2 → v3: the course space's coursePlan.uuid (or the previewed
    // plan's uuid) points at a quest-plans id. The outline (Missions + their
    // activities) comes from the v3 quest read layer; the v1
    // course-plans/topics fan-out is retired.
    final questId = _questId;
    if (questId == null) {
      _objectivesLoader.value = AsyncError(MissingQuestException());
      return;
    }

    _objectivesLoader.value = AsyncLoading();
    final outlineResult = await QuestRepo.outline(questId);
    final outline = outlineResult.result;

    if (!mounted) return;

    if (outline == null) {
      _objectivesLoader.value = AsyncError(
        outlineResult.error ?? MissingQuestException(),
      );
      return;
    }

    _orderedMissionIds = outline.quest.learningObjectiveIds;
    unawaited(_loadProgression());

    final filtered = objectiveGroupsWithActivities(outline.groups);
    if (filtered.isEmpty) {
      _objectivesLoader.value = AsyncError(MissingQuestException());
      return;
    }
    _objectivesLoader.value = AsyncLoaded(filtered);
  }

  /// Resolve the star-display rollup. Joined courses only — a preview has no
  /// learner progress to show. Fire-and-forget from [_load]: the outline
  /// renders immediately and the star chips fill in when the resolve lands.
  Future<void> _loadProgression() async {
    final client = widget.room?.client;
    if (client == null) return;
    await _objectiveCache.rebuildFromJoinedCourses(
      client,
      onError: (uuid, e, s) => ErrorHandler.logError(
        e: e,
        s: s,
        m: 'CourseObjectivesList: course outline failed to resolve',
        data: {'courseUuid': uuid},
      ),
    );
    if (!mounted) return;
    setState(() {
      _progression = _objectiveCache.resolution(client.userStarsByActivity);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _objectivesLoader,
      builder: (context, state, _) {
        switch (state) {
          case AsyncLoading():
          case AsyncIdle():
            return const Center(child: CircularProgressIndicator.adaptive());
          case AsyncError(error: final error):
            if (error is MissingQuestException) {
              final showAddCourse = widget.room?.isRoomAdmin == true;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    spacing: 12.0,
                    children: [
                      Text(
                        showAddCourse
                            ? L10n.of(context).missingCourseOutlineCta
                            : L10n.of(context).missingCourseOutline,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      if (showAddCourse)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => context.go(
                              WorkspaceNav.openCoursePage(
                                GoRouterState.of(context).uri,
                                'addcourse',
                              ),
                            ),
                            icon: Icon(Icons.map_outlined, size: 20.0),
                            label: Text(L10n.of(context).addCoursePlan),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14.0,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }

            return Center(
              child: ErrorIndicator(message: error.toLocalizedString(context)),
            );
          case AsyncLoaded(value: final groups):
            // The quest-star header shows only for a joined course once the shared
            // rollup has resolved; a preview has no learner progress to show.
            final showStars =
                widget.room != null && _progression.rollup.isNotEmpty;
            final list = ListView.separated(
              controller: widget.shrinkWrap ? null : _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              shrinkWrap: widget.shrinkWrap,
              physics: widget.shrinkWrap
                  ? const NeverScrollableScrollPhysics()
                  : null,
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 24.0),
              itemBuilder: (context, i) {
                if (showStars && i == 0) {
                  return _QuestStarsHeader(
                    summary: _progression.questStars(_orderedMissionIds),
                  );
                }
                final group = groups[showStars ? i - 1 : i];
                return _ObjectiveSection(
                  index: showStars ? i - 1 : i,
                  group: group,
                  room: widget.room,
                  hasCompletedActivity: widget.hasCompletedActivity,
                  progress: showStars
                      ? _progression.rollup[group.objective.id]
                      : null,
                );
              },
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
        }
      },
    );
  }
}

/// The quest-level star summary at the top of a joined course's objective
/// list: total earned (each Mission capped at its threshold) over a bar that
/// fills toward the sum of thresholds. See quests.instructions.md.
class _QuestStarsHeader extends StatelessWidget {
  final QuestStarSummary summary;

  const _QuestStarsHeader({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: L10n.of(context).starsEarnedOfTotal(summary.earned, summary.total),
      child: Row(
        children: [
          Icon(Icons.star, size: 22.0, color: AppConfig.goldByTheme(context)),
          const SizedBox(width: 6.0),
          Text(
            '${summary.earned}',
            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: LinearProgressIndicator(
                value: summary.fraction,
                minHeight: 10.0,
                color: AppConfig.goldByTheme(context),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
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

  /// The Mission's rollup from the shared resolver, or null when there is
  /// nothing to show (preview, or the rollup hasn't resolved yet).
  final MissionProgress? progress;

  const _ObjectiveSection({
    required this.index,
    required this.group,
    required this.room,
    required this.hasCompletedActivity,
    required this.progress,
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
        // Objective header: placeholder icon + the can-do statement, with the
        // Mission's earned/threshold stars when the shared rollup is in.
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
            if (progress != null) ...[
              const SizedBox(width: 8.0),
              Semantics(
                label: L10n.of(
                  context,
                ).starsEarnedOfTotal(progress!.stars, progress!.threshold),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: 18.0,
                      color: AppConfig.goldByTheme(context),
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      // Raw stars over the satisfaction threshold — surplus
                      // shows (12/7); only the quest header caps.
                      '${progress!.stars}/${progress!.threshold}',
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 8.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.0),
            child: LinearProgressIndicator(
              value: progress!.threshold <= 0
                  ? 0
                  : (progress!.stars / progress!.threshold).clamp(0.0, 1.0),
              minHeight: 6.0,
              color: AppConfig.goldByTheme(context),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
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
                      // Token-native open; the course context (if any) is kept,
                      // so the plan closes back to it. See routing.instructions.md.
                      context.go(
                        WorkspaceNav.openActivity(
                          GoRouterState.of(context).uri,
                          ref.activityId,
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
