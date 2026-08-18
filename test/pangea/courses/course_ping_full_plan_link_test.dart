import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/chat/activity_sessions/course_ping_badge.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// #8454: on the flattened course page only the Up-next Mission renders, so a
/// ping for an activity in another Mission has to badge the "See full course
/// plan" link instead of a (not-shown) card.
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

  QuestObjectiveGroup mission(String id, List<String> activityIds) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: 'obj-$id'),
        activities: [
          for (final a in activityIds)
            QuestActivity(activityId: a, plan: plan(a)),
        ],
      );

  const courseId = '!course:server';
  final upNext = mission('m1', ['a1', 'a2']);
  final later = mission('m2', ['a3', 'a4']);
  final planGroups = [upNext, later];

  CoursePingBadgeData ping(String activityId, {String course = courseId}) => (
    courseId: course,
    activityId: activityId,
    sessionRoomId: '!session:server',
  );

  group('coursePingLeadsToFullPlan', () {
    test('badges the link when the pinged activity is in a later Mission', () {
      expect(
        coursePingLeadsToFullPlan(
          ping: ping('a3'),
          courseId: courseId,
          planGroups: planGroups,
          upNextGroup: upNext,
        ),
        isTrue,
      );
    });

    test('does not badge the link when the Up-next card already shows the '
        'ping', () {
      expect(
        coursePingLeadsToFullPlan(
          ping: ping('a2'),
          courseId: courseId,
          planGroups: planGroups,
          upNextGroup: upNext,
        ),
        isFalse,
      );
    });

    test('a ping for an activity no longer in the plan badges nothing', () {
      expect(
        coursePingLeadsToFullPlan(
          ping: ping('gone'),
          courseId: courseId,
          planGroups: planGroups,
          upNextGroup: upNext,
        ),
        isFalse,
      );
    });

    test("another course's ping never badges this course's link", () {
      expect(
        coursePingLeadsToFullPlan(
          ping: ping('a3', course: '!other:server'),
          courseId: courseId,
          planGroups: planGroups,
          upNextGroup: upNext,
        ),
        isFalse,
      );
    });

    test('no ping, no badge', () {
      expect(
        coursePingLeadsToFullPlan(
          ping: null,
          courseId: courseId,
          planGroups: planGroups,
          upNextGroup: upNext,
        ),
        isFalse,
      );
    });

    test('an unloaded plan (no Up-next yet) badges nothing', () {
      expect(
        coursePingLeadsToFullPlan(
          ping: ping('a3'),
          courseId: courseId,
          planGroups: const [],
          upNextGroup: null,
        ),
        isFalse,
      );
    });
  });
}
