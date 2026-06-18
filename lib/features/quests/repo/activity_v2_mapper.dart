import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

/// Maps an `activities-v2` CMS document to the client's [ActivityPlanModel].
///
/// v3 stores the plan under `res.plan` with snake_case fields and a different
/// roles/goals shape than the legacy choreo activity payload: roles carry a
/// logical `role_id`, and goals live in a plan-level `goals` array linked back
/// to roles by `role_ids`. v3 has no separate `instructions` field.
///
/// The stimulus media (`res.plan.media`) is the polymorphic block list carried
/// through verbatim; its `upload_id`s are raw (unresolved) here. The caller
/// resolves them to CDN URLs via `ActivityMediaRepo` before rendering —
/// `imageURL` shows a placeholder until then.
ActivityPlanModel activityPlanFromV2(Map<String, dynamic> doc) {
  final plan =
      ((doc['res'] as Map?)?['plan'] as Map?)?.cast<String, dynamic>() ??
      const {};
  final req = (doc['req'] as Map?)?.cast<String, dynamic>() ?? const {};

  // Plan-level goals, linked to roles by `role_ids`.
  final planGoals = (plan['goals'] as List? ?? const [])
      .map((g) => (g as Map).cast<String, dynamic>())
      .toList();

  final roles = <String, ActivityRole>{};
  for (final r in (plan['roles'] as List? ?? const [])) {
    final role = (r as Map).cast<String, dynamic>();
    final roleId = (role['role_id'] ?? role['id']) as String;
    final goals = planGoals
        .where(
          (g) => (g['role_ids'] as List? ?? const []).contains(roleId),
        )
        .map(
          (g) => ActivityRoleGoal(
            id: g['id'] as String,
            description: (g['goal'] ?? '') as String,
          ),
        )
        .toList();
    roles[roleId] = ActivityRole(
      id: roleId,
      name: (role['name'] ?? '') as String,
      goal: role['goal'] as String?,
      goals: goals,
      avatarUrl: role['avatar_url'] as String?,
    );
  }

  final vocab = (plan['vocab'] as List? ?? const [])
      .map(
        (v) => Vocab(
          lemma: ((v as Map)['lemma'] ?? '') as String,
          pos: (v['pos'] ?? '') as String,
        ),
      )
      .toList();

  final media = (plan['media'] as List? ?? const [])
      .whereType<Map>()
      .map((b) => ActivityMediaBlock.fromCmsBlock(b.cast<String, dynamic>()))
      .toList();

  final cefr = (plan['cefr_level'] ?? req['cefr_level']) as String?;
  final l2 = (plan['l2'] ?? req['target_language'] ?? '') as String;

  final request = ActivityPlanRequest(
    topic: (req['topic_id'] ?? plan['topic_id'] ?? '') as String,
    mode: (plan['mode'] ?? req['mode'] ?? '') as String,
    objective: (plan['learning_objective'] ?? '') as String,
    media: MediaEnum.nan,
    cefrLevel: cefr != null
        ? LanguageLevelTypeEnum.fromString(cefr)
        : LanguageLevelTypeEnum.a1,
    languageOfInstructions: (req['user_l1'] ?? 'en') as String,
    targetLanguage: l2,
    numberOfParticipants: roles.isNotEmpty ? roles.length : 2,
  );

  return ActivityPlanModel(
    activityId: (plan['activity_id'] ?? doc['id']) as String,
    req: request,
    title: (plan['title'] ?? '') as String,
    description: plan['description'] as String?,
    learningObjective: (plan['learning_objective'] ?? '') as String,
    instructions: '', // v3 activities carry no separate instructions field
    vocab: vocab,
    media: media,
    roles: roles.isEmpty ? null : roles,
  );
}
