import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/features/navigation/token_params/objective_token.dart';
import 'package:fluffychat/features/quests/activity_family.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'courses/course_missions_fixtures.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// Which Mission page of the Learning Objectives page lists a saved session
/// (#9418). The page's own list and the end card's saved line both read it,
/// so the line opens the page the session is actually on.
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
    // No target language set: a course with a language recorded is in
    // another one, a course with none counts.
    MatrixState.pangeaController = FakePangeaController();
  });

  tearDown(() => client.dispose());

  QuestObjectiveGroup mission(String id, List<String> activityIds) =>
      QuestObjectiveGroup(
        objective: LearningObjective(id: id, objective: id),
        activities: [
          for (final activityId in activityIds)
            QuestActivity(
              activityId: activityId,
              plan: ActivityPlanModel(
                req: ActivityPlanRequest(
                  topic: '',
                  mode: '',
                  objective: '',
                  media: MediaEnum.nan,
                  cefrLevel: LanguageLevelTypeEnum.a1,
                  languageOfInstructions: 'en',
                  targetLanguage: 'es',
                  numberOfParticipants: 1,
                ),
                title: activityId,
                learningObjective: '',
                instructions: '',
                vocab: const [],
                activityId: activityId,
                roles: const {},
              ),
            ),
        ],
      );

  CourseMissions course(
    String id,
    List<QuestObjectiveGroup> groups, {
    String? language,
  }) {
    final room = Room(id: id, client: client, membership: Membership.join);
    putState(
      room,
      PangeaEventTypes.coursePlan,
      CoursePlanEvent(uuid: 'quest-$id', l2: language).toJson(),
    );
    return CourseMissions(room: room, groups: groups);
  }

  ObjectiveTokenParam? pageFor(List<CourseMissions> courses, String id) =>
      CourseMissions.missionPageFor(CourseMissions.listed(courses), id);

  test('the first Mission in the page\'s order that lists the activity', () {
    final courses = [
      course('!a:x', [
        mission('lo-1', ['other']),
        mission('lo-2', ['a1']),
      ]),
      course('!b:x', [
        mission('lo-3', ['a1']),
      ]),
    ];

    expect(
      pageFor(courses, 'a1'),
      const ObjectiveTokenParam(missionId: 'lo-2', courseId: '!a:x'),
    );
  });

  test('a Mission two courses share is read from the first course, so a '
      'session only the second lists it under stays under "Other '
      'activities"', () {
    final courses = [
      course('!a:x', [
        mission('lo-1', ['other']),
      ]),
      course('!b:x', [
        mission('lo-1', ['a1']),
      ]),
    ];

    expect(CourseMissions.listed(courses).last.groups, isEmpty);
    expect(pageFor(courses, 'a1'), isNull);
  });

  test('a course in another language is not on the page', () {
    final courses = [
      course('!fr:x', [
        mission('lo-1', ['a1']),
      ], language: 'fr'),
      course('!b:x', [
        mission('lo-2', ['a1']),
      ]),
    ];

    expect(
      pageFor(courses, 'a1'),
      const ObjectiveTokenParam(missionId: 'lo-2', courseId: '!b:x'),
    );
  });

  test('a session of an activity the course shows a copy of is on the '
      'Mission that shows the copy', () {
    final copy = mission('lo-1', ['a1-copy']);
    final courses = [
      course('!a:x', [
        QuestObjectiveGroup(
          objective: copy.objective,
          activities: copy.activities,
          credit: const CourseCredit(
            family: {'a1': 'a1-copy', 'a1-copy': 'a1-copy'},
          ),
        ),
      ]),
    ];

    expect(
      pageFor(courses, 'a1'),
      const ObjectiveTokenParam(missionId: 'lo-1', courseId: '!a:x'),
    );
  });

  test('an activity no listed Mission carries has no Mission page', () {
    final courses = [
      course('!a:x', [
        mission('lo-1', ['other']),
      ]),
    ];

    expect(pageFor(courses, 'a1'), isNull);
  });
}
