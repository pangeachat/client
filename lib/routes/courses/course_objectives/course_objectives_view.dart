import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/activity_suggestion_card.dart';

/// The Activities / Course-plan tab of a selected course (world_v2): the
/// course's learning objectives, each with the activities that satisfy it.
/// Objectives are the unlockable unit; activities are interchangeable
/// options. Objectives have no icons yet — a placeholder stands in.
/// Tapping an activity opens it as a first-class world object (`/<uuid>`).
class CourseObjectivesList extends StatefulWidget {
  final Room room;

  /// Per-activity completion, e.g. `controller.roomSummariesModel
  /// .hasCompletedActivity`.
  final bool Function(String userId, String activityId) hasCompletedActivity;

  const CourseObjectivesList({
    required this.room,
    required this.hasCompletedActivity,
    super.key,
  });

  @override
  State<CourseObjectivesList> createState() => _CourseObjectivesListState();
}

class _CourseObjectivesListState extends State<CourseObjectivesList> {
  late Future<List<QuestObjectiveGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _load();
  }

  @override
  void didUpdateWidget(covariant CourseObjectivesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _groupsFuture = _load();
    }
  }

  Future<List<QuestObjectiveGroup>> _load() async {
    // world_v2 → v3: the course space's coursePlan.uuid now points at a
    // quest-plans id. The outline (Missions + their activities) comes from the
    // v3 quest read layer; the v1 course-plans/topics fan-out is retired.
    final questId = widget.room.coursePlan?.uuid;
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
        final groups = snapshot.data ?? const [];
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
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 24.0),
          itemBuilder: (context, i) => _ObjectiveSection(
            index: i,
            group: groups[i],
            room: widget.room,
            hasCompletedActivity: widget.hasCompletedActivity,
          ),
        );
      },
    );
  }
}

class _ObjectiveSection extends StatelessWidget {
  final int index;
  final QuestObjectiveGroup group;
  final Room room;
  final bool Function(String userId, String activityId) hasCompletedActivity;

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
    final userId = room.client.userID!;

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
              final complete = hasCompletedActivity(userId, ref.activityId);
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  // Open the activity in-place over the course (the `?activity=`
                  // detail panel) instead of navigating to the standalone
                  // `/<activityId>` page, so the course context is preserved.
                  onTap: () {
                    final uri = GoRouter.of(
                      context,
                    ).routeInformationProvider.value.uri;
                    context.go(
                      uri
                          .replace(
                            queryParameters: {
                              ...uri.queryParameters,
                              'activity': ref.activityId,
                            },
                          )
                          .toString(),
                    );
                  },
                  child: Stack(
                    children: [
                      ActivitySuggestionCard(
                        activity: ref.plan,
                        width: cardWidth,
                        height: cardHeight,
                        fontSize: isColumnMode ? 20.0 : 12.0,
                        fontSizeSmall: isColumnMode ? 12.0 : 8.0,
                        iconSize: isColumnMode ? 12.0 : 8.0,
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
