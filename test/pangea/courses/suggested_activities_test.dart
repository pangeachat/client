import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/courses/course_objectives/suggested_activities.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/world/world_map_ranking.dart';

/// Coverage for #8741: the course page's Activities row ranks the
/// course plan's activities by the world map's Priority matrix, drops the
/// sessions the learner is already in, and caps to a shortlist.
void main() {
  ActivityPlanModel plan(String id) => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: '',
      mode: '',
      objective: '',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a2,
      languageOfInstructions: 'en',
      targetLanguage: 'es',
      numberOfParticipants: 2,
    ),
    title: '',
    learningObjective: '',
    instructions: '',
    vocab: const [],
    activityId: id,
  );

  QuestObjectiveGroup objGroup(String missionId, List<String> ids) =>
      QuestObjectiveGroup(
        objective: LearningObjective(
          id: missionId,
          objective: 'obj-$missionId',
        ),
        activities: [
          for (final id in ids) QuestActivity(activityId: id, plan: plan(id)),
        ],
      );

  /// No relevance signal at all — every activity bands at 0, so ordering is
  /// decided by live state alone.
  double flatBand(Set<String> _) => 0;

  PinSignals plain(String _) => const PinSignals();

  List<String> idsOf(List<SuggestedActivity> suggestions) => [
    for (final s in suggestions) s.activityId,
  ];

  group('rankSuggestedActivities', () {
    test('an open session outranks a pinged one, which outranks a plain '
        'activity', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['plain', 'open', 'pinged']),
        ],
        missionGradient: flatBand,
        signalsFor: (id) => switch (id) {
          'open' => const PinSignals(state: ActivityPinState.joinable),
          'pinged' => const PinSignals(pinged: true),
          _ => const PinSignals(),
        },
      );

      expect(idsOf(ranked), ['open', 'pinged', 'plain']);
    });

    test('a pinged open session outranks an unpinged one', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['open', 'pingedOpen']),
        ],
        missionGradient: flatBand,
        signalsFor: (id) => PinSignals(
          state: ActivityPinState.joinable,
          pinged: id == 'pingedOpen',
        ),
      );

      expect(idsOf(ranked), ['pingedOpen', 'open']);
    });

    test('sessions the learner already holds a role in are dropped, not '
        'ranked', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['ongoingActive', 'ongoingPending', 'plain']),
        ],
        missionGradient: flatBand,
        signalsFor: (id) => switch (id) {
          'ongoingActive' => const PinSignals(
            state: ActivityPinState.ongoingActive,
          ),
          'ongoingPending' => const PinSignals(
            state: ActivityPinState.ongoingPending,
          ),
          _ => const PinSignals(),
        },
      );

      expect(idsOf(ranked), ['plain']);
    });

    test("with nothing live, the course's next Mission decides the order", () {
      // The band stands in for the resolver: the anchor Mission's activity
      // scores highest, one Mission further along less, a satisfied one zero.
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('anchor', ['atAnchor']),
          objGroup('later', ['later']),
          objGroup('done', ['done']),
        ],
        missionGradient: (refs) => switch (refs.first) {
          'anchor' => 1.0,
          'later' => 0.67,
          _ => 0.0,
        },
        signalsFor: plain,
      );

      expect(idsOf(ranked), ['atAnchor', 'later', 'done']);
    });

    test('a finished activity is demoted but still suggested', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['finished', 'fresh']),
        ],
        missionGradient: flatBand,
        signalsFor: (id) =>
            PinSignals(completionFraction: id == 'finished' ? 1.0 : 0.0),
      );

      expect(idsOf(ranked), ['fresh', 'finished']);
    });

    test('an activity under two Missions is listed once, banded on both', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['shared', 'other']),
          objGroup('m2', ['shared']),
        ],
        // Only the second Mission carries the frontier, so an activity listed
        // under both must pick it up from the union of its Missions.
        missionGradient: (refs) => refs.contains('m2') ? 1.0 : 0.0,
        signalsFor: plain,
      );

      expect(idsOf(ranked), ['shared', 'other']);
    });

    test('caps to a shortlist, keeping the highest scorers', () {
      final ranked = rankSuggestedActivities(
        groups: [
          objGroup('m1', ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7']),
        ],
        missionGradient: flatBand,
        signalsFor: (id) => PinSignals(
          state: id == 'a7'
              ? ActivityPinState.joinable
              : ActivityPinState.available,
        ),
      );

      expect(ranked, hasLength(kSuggestedActivitiesCap));
      expect(ranked.first.activityId, 'a7');
    });

    test('equal scores order by activity id, so a rebuild does not reshuffle '
        'the row', () {
      List<String> rank(List<String> ids) => idsOf(
        rankSuggestedActivities(
          groups: [objGroup('m1', ids)],
          missionGradient: flatBand,
          signalsFor: plain,
          cap: 10,
        ),
      );

      expect(rank(['c', 'a', 'b']), ['a', 'b', 'c']);
      expect(rank(['b', 'c', 'a']), ['a', 'b', 'c']);
    });

    test('an empty plan suggests nothing', () {
      expect(
        rankSuggestedActivities(
          groups: const [],
          missionGradient: flatBand,
          signalsFor: plain,
        ),
        isEmpty,
      );
    });
  });
}
