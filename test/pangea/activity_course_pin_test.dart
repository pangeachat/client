import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_missions_event.dart';
import 'package:fluffychat/features/quests/models/learning_objective_model.dart';
import 'package:fluffychat/features/quests/models/quest_plan_model.dart';
import 'package:fluffychat/routes/world/activity_course_resolver.dart';
import 'courses/course_missions_fixtures.dart';
import 'get_test_client.dart';

/// source_course_id must be a genuinely-pinned course, never an arbitrary pick.
/// When an activity is opened without a selected course, it is attributed to a
/// matching course only when the match is UNAMBIGUOUS (exactly one).
void main() {
  late Client client;

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  Room room(String id) => Room(id: id, client: client);

  test('pins only when exactly one course matches; a tie is unscoped', () {
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: const [],
        complete: true,
      )),
      isNull,
      reason: 'no match → unscoped',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org')],
        complete: true,
      )),
      '!c1:example.org',
      reason: 'exactly one match, set complete → that course',
    );
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org'), room('!c2:example.org')],
        complete: true,
      )),
      isNull,
      reason: 'ambiguous → unscoped, never an arbitrary firstOrNull pick',
    );
  });

  test('a lone match from an INCOMPLETE set is not pinned', () {
    // Another joined course failed to resolve its quest, so this single
    // surviving match might not actually be unique — do not pin it.
    expect(
      ActivityCourseResolver.unambiguousCourseId((
        matches: [room('!c1:example.org')],
        complete: false,
      )),
      isNull,
      reason:
          'a lone survivor of a batch with an unresolved course must stay '
          'unscoped — it could mis-attribute source_course_id',
    );
  });

  /// Eligibility reads the course's own list (content-studio): with a copy an
  /// activity belongs to the course only when a listed Can-Do it satisfies
  /// lists it; without one, today's quest-LO intersection.
  group('listsActivity', () {
    const quest = QuestPlan(
      id: 'q1',
      name: '',
      description: '',
      targetLanguage: 'es',
      sequence: [
        QuestObjectiveStep(
          objective: LearningObjective(id: 'lo-1', objective: ''),
          wasMinted: false,
        ),
        QuestObjectiveStep(
          objective: LearningObjective(id: 'lo-2', objective: ''),
          wasMinted: false,
        ),
      ],
    );
    CourseMissionsEvent copy(Map<String, List<String>> m) =>
        CourseMissionsEvent.tryParse(copyContent(m))!;

    test('no copy: any quest Mission the activity satisfies', () {
      expect(
        ActivityCourseResolver.listsActivity(
          quest,
          null,
          activityId: 'a1',
          activityRefs: {'lo-2'},
        ),
        isTrue,
      );
      expect(
        ActivityCourseResolver.listsActivity(
          quest,
          null,
          activityId: 'a1',
          activityRefs: {'lo-9'},
        ),
        isFalse,
      );
    });

    test('a copy lists it only under a kept Can-Do that names it', () {
      final c = copy({
        'lo-1': ['a1'],
      });
      expect(
        ActivityCourseResolver.listsActivity(
          quest,
          c,
          activityId: 'a1',
          activityRefs: {'lo-1'},
        ),
        isTrue,
      );
      // Its Can-Do was removed from the course.
      expect(
        ActivityCourseResolver.listsActivity(
          quest,
          c,
          activityId: 'b1',
          activityRefs: {'lo-2'},
        ),
        isFalse,
      );
      // Its Can-Do is kept but the activity was dropped from it.
      expect(
        ActivityCourseResolver.listsActivity(
          quest,
          c,
          activityId: 'a2',
          activityRefs: {'lo-1'},
        ),
        isFalse,
      );
    });
  });
}
