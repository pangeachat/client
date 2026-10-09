import 'package:flutter/material.dart';

import 'package:fluffychat/config/pangea_colors.dart';
import 'package:fluffychat/features/quests/quest_objectives_loader.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// Where one Mission stands in the plan, for its circle.
enum ObjectiveCircleState { complete, current, later }

/// One Mission's circle: its number, its statement (as the tooltip), and its
/// state.
class ObjectiveCircleData {
  final int index;
  final String statement;
  final ObjectiveCircleState state;

  /// The Mission on show in the course page's section — a bold ring, apart
  /// from the state's fill, since a learner can pick a complete or a later
  /// Mission to look at.
  final bool selected;

  const ObjectiveCircleData({
    required this.index,
    required this.statement,
    required this.state,
    this.selected = false,
  });
}

/// The course's Missions as a row of numbered circles, in plan order: a
/// check for a complete Mission, a tint on the current one, a bold ring
/// around the one on show, a plain number for the rest
/// (quests.instructions.md, "Progress display on the course page"). One
/// glance says how far through the course the learner is and where they are
/// now. Wraps when a quest has more Missions than a row holds.
class ObjectiveProgressCircles extends StatelessWidget {
  final List<ObjectiveCircleData> items;

  /// Tapping a circle, with its 1-based index; null draws the circles inert.
  final void Function(int index)? onTap;

  static const double diameter = 32.0;

  const ObjectiveProgressCircles({required this.items, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: [
        for (final item in items)
          _ObjectiveCircle(
            item: item,
            count: items.length,
            onTap: onTap == null ? null : () => onTap!(item.index),
          ),
      ],
    );
  }
}

class _ObjectiveCircle extends StatelessWidget {
  final ObjectiveCircleData item;
  final int count;
  final VoidCallback? onTap;

  const _ObjectiveCircle({
    required this.item,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final (fill, ring, ink, label) = switch (item.state) {
      ObjectiveCircleState.complete => (
        theme.pangea.successFixedDim,
        theme.pangea.successFixedDim,
        theme.pangea.onSuccessFixed,
        l10n.objectiveCircleComplete(item.index),
      ),
      ObjectiveCircleState.current => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.outlineVariant,
        theme.colorScheme.onPrimaryContainer,
        l10n.objectiveCircleUpNext(item.index),
      ),
      ObjectiveCircleState.later => (
        Colors.transparent,
        theme.colorScheme.outlineVariant,
        theme.colorScheme.onSurfaceVariant,
        l10n.missionNofM(item.index, count),
      ),
    };
    final circle = Container(
      width: ObjectiveProgressCircles.diameter,
      height: ObjectiveProgressCircles.diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: item.selected ? theme.colorScheme.primary : ring,
          width: item.selected ? 2.5 : 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: item.state == ObjectiveCircleState.complete
          ? Icon(Icons.check, size: 18.0, color: ink)
          : Text(
              '${item.index}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    // The state is in the accessible name and the statement in the tooltip,
    // so neither the colour nor the number is the only carrier.
    return Semantics(
      label: '$label: ${item.statement}',
      selected: item.selected,
      button: onTap != null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.statement,
          child: onTap == null
              ? circle
              : InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: circle,
                ),
        ),
      ),
    );
  }
}

/// The circles for a course, read from its shared resolver: Missions with an
/// activity in plan order, complete when their XP is at the threshold, the
/// anchor ringed (the first Mission before progress resolves, like the
/// course page's section). Nothing while the plan is still loading.
class CourseObjectiveCircles extends StatelessWidget {
  final QuestObjectivesLoader objectivesProvider;
  final void Function(int index)? onTap;

  /// The Mission the course page shows, to ring; null rings the current one.
  final String? selectedMissionId;

  const CourseObjectiveCircles({
    required this.objectivesProvider,
    this.onTap,
    this.selectedMissionId,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      objectivesProvider.questLoader,
      objectivesProvider.progression,
    ]),
    builder: (context, _) {
      final groups = objectivesProvider.filteredObjectiveGroups;
      final currentId = objectivesProvider.currentObjectiveGroup?.objective.id;
      final shownId =
          objectivesProvider.objectiveGroup(selectedMissionId)?.objective.id ??
          currentId;
      return ObjectiveProgressCircles(
        onTap: onTap,
        items: [
          for (var i = 0; i < groups.length; i++)
            ObjectiveCircleData(
              index: i + 1,
              statement: groups[i].objective.objective,
              selected: groups[i].objective.id == shownId,
              state:
                  objectivesProvider
                          .missionProgress(groups[i].objective.id)
                          ?.satisfied ==
                      true
                  ? ObjectiveCircleState.complete
                  : groups[i].objective.id == currentId
                  ? ObjectiveCircleState.current
                  : ObjectiveCircleState.later,
            ),
        ],
      );
    },
  );
}
