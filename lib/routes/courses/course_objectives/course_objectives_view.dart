import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/courses/course_objectives/objective_section.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';

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
  final bool Function(String activityId)? hasCompletedActivity;

  /// Shrink-wrap the objective list instead of filling/scrolling its own
  /// viewport. Set true when embedded inside another scroll view (the
  /// SelectedCourse / preview pages place this inside an outer `ListView`);
  /// leave false when given a bounded slot (the card's Course Plan tab uses an
  /// `Expanded`).
  final bool shrinkWrap;

  final QuestObjectivesLoader objectivesProvider;

  const CourseObjectivesList({
    required this.objectivesProvider,
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
  final ScrollController _scrollController = ScrollController();

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
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.objectivesProvider.questLoader,
      builder: (context, state, _) {
        switch (state) {
          case AsyncLoading():
          case AsyncIdle():
            return const Center(child: CircularProgressIndicator.adaptive());
          case AsyncError(error: final error):
            return _QuestLoadErrorView(
              error,
              showAddCourse: widget.room?.isRoomAdmin == true,
            );
          case AsyncLoaded():
            // The overall quest-star bar now lives in the course card header
            // (above the tabs — [CourseProgressBar]), so it shows on every tab
            // and in the collapsed mobile peek; the list is just the Missions.
            // Per-Mission stars still show once the shared rollup resolves; a
            // preview has no learner progress.
            final groups = widget.objectivesProvider.filteredObjectiveGroups;
            if (groups.isEmpty) {
              return _QuestLoadErrorView(
                MissingQuestException(),
                showAddCourse: widget.room?.isRoomAdmin == true,
              );
            }

            return ValueListenableBuilder(
              valueListenable: widget.objectivesProvider.progression,
              builder: (context, progression, _) {
                // Scoped to THIS course: the shared resolution spans every
                // joined course, and Missions are reused across quests (#7771).
                final hasProgress =
                    widget.room != null &&
                    widget.objectivesProvider.hasResolvedProgress;
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
                    final group = groups[i];
                    return ObjectiveSection(
                      index: i,
                      group: group,
                      hasCompletedActivity: widget.hasCompletedActivity,
                      progress: hasProgress
                          ? widget.objectivesProvider.missionProgress(
                              group.objective.id,
                            )
                          : null,
                      onTap: (ref) {
                        final room = widget.room;
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
                            room.id,
                            ref.activityId,
                            autoplay:
                                ref.plan.heroBlock?.isVideo == true ||
                                ref.plan.heroBlock?.isYoutube == true,
                          ),
                        );
                      },
                      userStarsByActivity: (activityId) =>
                          widget.room?.client.userStarsByActivity[activityId] ??
                          0,
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
              },
            );
        }
      },
    );
  }
}

class _QuestLoadErrorView extends StatelessWidget {
  final Object error;
  final bool showAddCourse;

  const _QuestLoadErrorView(this.error, {required this.showAddCourse});

  @override
  Widget build(BuildContext context) {
    if (error is MissingQuestException) {
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
                        RoomSubpageEnum.addcourse,
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
                      padding: const EdgeInsets.symmetric(vertical: 14.0),
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
  }
}
