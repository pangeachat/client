import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/routes/world/joined_objective_cache.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

typedef QuestLoader = ValueNotifier<AsyncState<QuestOutline>>;

/// The objective groups that should render: those with at least one activity.
/// An activity-less objective would otherwise show a header over a fixed-height
/// activity-card row that is all empty space, so it is dropped (#7114). Null
/// (still loading / no data) maps to an empty list.
///
/// The single home of "which Missions does the learner actually see": the
/// course panel's list and the info chips' activity count both read through
/// it, so a hidden Mission's activities can never be listed by one and counted
/// by the other (#7976).
List<QuestObjectiveGroup> objectiveGroupsWithActivities(
  List<QuestObjectiveGroup>? groups,
) => (groups ?? const <QuestObjectiveGroup>[])
    .where((g) => g.activities.isNotEmpty)
    .toList();

class QuestObjectivesLoader {
  final Client client;

  QuestObjectivesLoader({required this.client}) {
    // A star is awarded as room state on a session room, so the panel's star
    // numbers go stale the moment the learner earns one — the counts sat at
    // their load-time values until the page was left and re-entered (#8915).
    // Re-resolve on room sync, on the same rate-limited tick the world map
    // and the objectives list already recompute on, so the two surfaces can't
    // drift apart on the same award.
    _starsSub = client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .rateLimit(const Duration(seconds: 2))
        .listen((_) => _resolveProgression(_loadGeneration));
  }

  final QuestLoader _questLoader = QuestLoader(AsyncLoading());

  /// The shared progression, published by whichever loader resolved it last
  /// and read by every live one — the "resolve once, never per surface" rule
  /// of quests.instructions.md, made literal.
  ///
  /// Session-scoped rather than per-loader because the resolution spans every
  /// joined course and every read is scoped by course id ([forCourse]), so
  /// there is no course whose numbers a second loader could get wrong. What
  /// per-loader state cost was a flicker: the course card and the context bar
  /// are one surface swapping widgets (#8866), and each new instance started
  /// at [ProgressionResolution.empty], so collapsing or expanding the course
  /// panel blanked its progress bar for the frames the fresh loader took to
  /// re-resolve what the outgoing one already knew (#8938).
  static final ValueNotifier<ProgressionResolution> _progression =
      ValueNotifier(ProgressionResolution.empty);

  /// The learner's joined-course outlines. Rebuilt on each [loadOutline] (a
  /// few quest reads), then re-resolved from on every sync tick. Kept across
  /// ticks so a tick re-runs only the pure resolve: rebuilding it there would
  /// re-request every course whose outline failed, since failures are
  /// deliberately never cached ([QuestRepo.outline]).
  final JoinedObjectiveCache _objectiveCache = JoinedObjectiveCache();
  StreamSubscription? _starsSub;

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
    _starsSub?.cancel();
    _questLoader.dispose();
    // _progression is shared across loaders — never disposed with one of them.
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

  /// The next-Mission gradient (0..[kBandCeiling]) for an activity satisfying
  /// [missionRefs], scoped to THIS course — the relevance band the course
  /// page's Activities row ranks toward. Deliberately not the shared
  /// resolution's cross-quest sum: a course surface reads only its own course's
  /// progress (#7771). 0 until the resolution lands, so ranking degrades to
  /// plain live-session order rather than to a wall.
  double missionGradient(Set<String> missionRefs) =>
      (_scopedQuest?.missionGradient(missionRefs) ?? 0).clamp(
        0.0,
        kBandCeiling,
      );

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

  /// Re-resolve the shared progression from the cached outlines and the
  /// learner's current per-activity stars — the SAME inputs and resolver the
  /// world map uses, so the star numbers can never disagree
  /// (quests.instructions.md). Pure and cheap: no network, no reads beyond
  /// room state the client already holds.
  ///
  /// Publishes nothing before the first rebuild lands, so a course whose
  /// outlines aren't in yet keeps its muted empty bar rather than briefly
  /// showing a denominator resolved from another course's cache.
  void _resolveProgression(int loadGen) {
    if (_disposed || _objectiveCache.outlines.isEmpty) return;
    _updateProgression(
      _objectiveCache.resolution(client.userStarsByActivity),
      loadGen,
    );
  }

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

    await _objectiveCache.rebuildFromJoinedCourses(
      client,
      // The SAME reporter the world map's rebuild passes — one throttle key,
      // one severity rule, so this path and the map's can't disagree about a
      // failure only one of them will end up reporting (#8470).
      onError: reportCourseOutlineFailure,
    );
    _resolveProgression(loadGen);
  }
}
