import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef QuestLoader = ValueNotifier<AsyncState<QuestOutline>>;

class QuestObjectivesLoader {
  final Client client;
  QuestObjectivesLoader({required this.client});

  final QuestLoader _questLoader = QuestLoader(AsyncLoading());
  final ValueNotifier<ProgressionResolution> _progression = ValueNotifier(
    ProgressionResolution.empty,
  );

  void dispose() {
    _questLoader.dispose();
    _progression.dispose();
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

  Future<void> loadOutline(String? questId) async {
    _progression.value = ProgressionResolution.empty;

    // world_v2 → v3: the course space's coursePlan.uuid (or the previewed
    // plan's uuid) points at a quest-plans id. The outline (Missions + their
    // activities) comes from the v3 quest read layer; the v1
    // course-plans/topics fan-out is retired.
    if (questId == null) {
      _questLoader.value = AsyncError(MissingQuestException());
      return;
    }

    _questLoader.value = AsyncLoading();
    final outlineResult = await QuestRepo.outline(questId);
    final outline = outlineResult.result;

    if (outline == null) {
      _questLoader.value = AsyncError(
        outlineResult.error ?? MissingQuestException(),
      );
      return;
    }

    _questLoader.value = AsyncLoaded(outline);

    ProgressionResolution.resolveJoinedProgression(
      client,
    ).then((p) => _progression.value = p);
  }
}
