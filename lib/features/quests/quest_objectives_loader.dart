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
///
/// The single home of "which Missions does the learner actually see": the
/// course panel's list and the "N modules" chip both count through it, so a
/// hidden Mission can never be listed by one and counted by the other (#7976).
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

  /// The course this loader is showing — its room id when the caller has one,
  /// matching the room-id-keyed resolution entries; the quest uuid otherwise
  /// (previews resolve nothing and fail soft). The shared resolution spans
  /// every joined course, so every progress read below scopes through it — a
  /// course panel must never show another course's star totals (#7771), and
  /// the quest uuid can't distinguish two courses built from one quest
  /// (#8087).
  String? _courseId;

  void dispose() {
    _questLoader.dispose();
    _progression.dispose();
    _disposed = true;
  }

  QuestLoader get questLoader => _questLoader;
  ValueNotifier<ProgressionResolution> get progression => _progression;

  /// The header's star summary, or null before this course's progress resolves
  /// (the bar then renders its muted empty state).
  ///
  /// Deliberately supplies no Mission list: the resolver owns which Missions
  /// count. Passing `quest.learningObjectiveIds` here used to disagree with the
  /// panel — which drops activity-less Missions (#7114) — so each hidden
  /// Mission silently added a default threshold to the denominator (#7663).
  QuestStarSummary? get questStars => progression.value.questStars(_courseId);

  /// This course's resolved quest, or null until the shared resolution lands
  /// (or when the course isn't joined) — the panel then shows no star display,
  /// per quests.instructions.md.
  QuestProgress? get _scopedQuest => progression.value.forCourse(_courseId);

  /// Whether this course's progress has resolved, so the panel knows to render
  /// the star display at all.
  bool get hasResolvedProgress => _scopedQuest != null;

  /// The "Up next" Mission — the shared resolver's anchor — or null until the
  /// resolution lands. Callers fall back to the first Mission in the outline.
  String? get anchorMissionId => _scopedQuest?.anchorMissionId;

  /// This course's rollup for [missionId]. Null means "not resolved", never
  /// "zero" — the caller renders no star display rather than a false 0.
  MissionProgress? missionProgress(String missionId) =>
      _scopedQuest?.rollup[missionId];

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
  /// [courseRoomId] (same callers) lets the outline include the quest owner's
  /// private activities — membership is verified server-side, so passing it
  /// for a non-member is harmless.
  Future<void> loadOutline(
    String? questId, {
    Map<String, List<String>>? pinnedActivitiesByObjective,
    String? courseRoomId,
  }) async {
    if (_disposed) return;

    _loadGeneration++;
    final loadGen = _loadGeneration;
    _courseId = courseRoomId ?? questId;
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
    final outlineResult = await QuestRepo.outline(
      questId,
      courseRoomId: courseRoomId,
    );
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
