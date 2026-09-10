import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';

/// The owner MXID has to survive every read path, because it is the only thing
/// standing between a teacher's work and a PangeaChat credit over it. Each read
/// path carries the owner verbatim — nothing resolves a name for us — and an
/// owner that was never recorded stays null rather than defaulting to anything.
void main() {
  const owner = '@profeceniza02:pangea.chat';

  Map<String, dynamic> planJson({String? userId}) => {
    'activity_id': 'act-1',
    'req': {
      'topic': 'jobs',
      'mode': 'Roleplay',
      'objective': 'introduce yourself',
      'media': 'nan',
      'activity_cefr_level': 'A1',
      'language_of_instructions': 'en',
      'target_language': 'de',
      'count': 3,
      'number_of_participants': 2,
    },
    'title': 'Speed-Dating Interview',
    'learning_objective': 'introduce yourself',
    'instructions': 'take turns',
    'vocab': const [],
    'user_id': ?userId,
  };

  Map<String, dynamic> v2Doc({String? userId}) => {
    'id': 'row-1',
    'req': {'target_language': 'de', 'user_l1': 'en'},
    'res': {
      'plan': {
        'activity_id': 'act-1',
        'title': 'Speed-Dating Interview',
        'learning_objective': 'introduce yourself',
        'cefr_level': 'A1',
        'l2': 'de',
        'roles': const [
          {'role_id': 'r1', 'name': 'Interviewer'},
        ],
        'user_id': ?userId,
      },
    },
  };

  Map<String, dynamic> questJson({String? ownerMxid}) => {
    'id': 'quest-1',
    'req': {'target_language': 'de', 'target_l1': 'en', 'target_cefr': 'A1'},
    'res': {
      'name': 'Plan it like a pro',
      'description': 'Plan a trip.',
      'learning_objective_sequence': const [],
    },
    'owner_mxid': ?ownerMxid,
  };

  group('ActivityPlanModel owner', () {
    test('reads the plan\'s user_id', () {
      expect(
        ActivityPlanModel.fromJson(planJson(userId: owner)).ownerId,
        owner,
      );
      expect(
        ActivityPlanModel.fromJson(
          planJson(userId: '@system:pangea.chat'),
        ).ownerId,
        '@system:pangea.chat',
      );
    });

    test('a plan with no owner recorded parses to null, not a default', () {
      expect(ActivityPlanModel.fromJson(planJson()).ownerId, isNull);
    });

    test('survives a room-state round trip', () {
      final plan = ActivityPlanModel.fromJson(planJson(userId: owner));
      expect(ActivityPlanModel.fromJson(plan.toJson()).ownerId, owner);
      // An unknown owner writes no key at all, and still reads back unknown.
      final anonymous = ActivityPlanModel.fromJson(planJson());
      expect(anonymous.toJson().containsKey('user_id'), isFalse);
      expect(ActivityPlanModel.fromJson(anonymous.toJson()).ownerId, isNull);
    });

    test('survives withMedia', () {
      final plan = ActivityPlanModel.fromJson(planJson(userId: owner));
      expect(plan.withMedia(const []).ownerId, owner);
    });
  });

  group('activityPlanFromV2 owner', () {
    test('maps res.plan.user_id', () {
      expect(activityPlanFromV2(v2Doc(userId: owner)).ownerId, owner);
    });

    test('a v2 row with no owner maps to null', () {
      expect(activityPlanFromV2(v2Doc()).ownerId, isNull);
    });
  });

  group('QuestPlan owner', () {
    test('reads the row\'s owner_mxid', () {
      expect(QuestPlan.fromJson(questJson(ownerMxid: owner)).ownerId, owner);
    });

    test('a quest with no owner recorded parses to null', () {
      expect(QuestPlan.fromJson(questJson()).ownerId, isNull);
    });
  });

  group('CoursePlanModel owner', () {
    Map<String, dynamic> courseJson({String? ownerMxid}) => {
      'uuid': 'quest-1',
      'title': 'Elementary German I',
      'description': 'STEM and professional life.',
      'target_language': 'de',
      'language_of_instructions': 'en',
      'cefr_level': 'A1',
      'topic_ids': const <String>[],
      'media_ids': const <String>[],
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'owner_mxid': ?ownerMxid,
    };

    test('reads the quest row\'s owner_mxid', () {
      expect(
        CoursePlanModel.fromJson(courseJson(ownerMxid: owner)).ownerId,
        owner,
      );
    });

    test('a course plan with no owner recorded parses to null', () {
      // Null is NOT "@system": the create-course page credits nobody rather
      // than putting Pangea's name over a course it may not have made.
      expect(CoursePlanModel.fromJson(courseJson()).ownerId, isNull);
    });

    test('the owner survives a serialize round trip', () {
      final plan = CoursePlanModel.fromJson(courseJson(ownerMxid: owner));
      expect(CoursePlanModel.fromJson(plan.toJson()).ownerId, owner);
    });

    test('an unowned plan serializes no owner key at all', () {
      final plan = CoursePlanModel.fromJson(courseJson());
      expect(plan.toJson().containsKey('owner_mxid'), isFalse);
      expect(CoursePlanModel.fromJson(plan.toJson()).ownerId, isNull);
    });
  });
}
