import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef QuestLoader = ValueNotifier<AsyncState<QuestOutline>>;

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

class QuestObjectivesLoader {
  final Client client;
  QuestObjectivesLoader({required this.client});

  final QuestLoader _questLoader = QuestLoader(AsyncLoading());
  final ValueNotifier<ProgressionResolution> _progression = ValueNotifier(
    ProgressionResolution.empty,
  );

  int _loadGeneration = 0;
  bool _disposed = false;

  void dispose() {
    _questLoader.dispose();
    _progression.dispose();
    _disposed = true;
  }

  QuestLoader get questLoader => _questLoader;
  ValueNotifier<ProgressionResolution> get progression => _progression;

  QuestStarSummary get questStars {
    final List<String> objectiveIds = switch (_questLoader.value) {
      AsyncLoaded(value: final value) => value.quest.learningObjectiveIds,
      _ => const [],
    };
    return progression.value.questStars(objectiveIds);
  }

  List<QuestObjectiveGroup> get filteredObjectiveGroups =>
      switch (_questLoader.value) {
        AsyncLoaded(value: final outline) => objectiveGroupsWithActivities(
          outline.groups,
        ),
        _ => const [],
      };

  void _updateProgression(ProgressionResolution value, int loadGen) {
    if (!_disposed && loadGen == _loadGeneration) {
      _progression.value = value;
    }
  }

  void _updateQuest(AsyncState<QuestOutline> value, int loadGen) {
    if (!_disposed && loadGen == _loadGeneration) {
      _questLoader.value = value;
    }
  }

  /// [pinnedActivitiesByObjective] is the course's per-Mission activity pin
  /// (room.teacherMode) — passed by callers with a joined course room in hand;
  /// null (previews, no room) means unrestricted, the fail-open default.
  /// Applied as a pure copy so the shared quest-outline cache is untouched.
  Future<void> loadOutline(
    String? questId, {
    Map<String, List<String>>? pinnedActivitiesByObjective,
  }) async {
    if (_disposed) return;

    _loadGeneration++;
    final loadGen = _loadGeneration;
    _updateProgression(ProgressionResolution.empty, loadGen);

    // world_v2 → v3: the course space's coursePlan.uuid (or the previewed
    // plan's uuid) points at a quest-plans id. The outline (Missions + their
    // activities) comes from the v3 quest read layer; the v1
    // course-plans/topics fan-out is retired.
    if (questId == null) {
      if (!_disposed && loadGen == _loadGeneration) {
        _updateQuest(AsyncError(MissingQuestException()), loadGen);
      }
      return;
    }

    _updateQuest(AsyncLoading(), loadGen);
    final outlineResult = await QuestRepo.outline(questId);
    final outline = outlineResult.result?.restrictedTo(
      pinnedActivitiesByObjective,
    );

    if (_disposed) return;

    if (outline == null) {
      _updateQuest(
        AsyncError(outlineResult.error ?? MissingQuestException()),
        loadGen,
      );
      return;
    }

    _updateQuest(AsyncLoaded(outline), loadGen);

    ProgressionResolution.resolveJoinedProgression(
      client,
    ).then((p) => _updateProgression(p, loadGen));
  }
}
