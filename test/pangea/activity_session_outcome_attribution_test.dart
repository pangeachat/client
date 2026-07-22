import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_auto_save_service.dart';
import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'get_test_client.dart';

/// The dosage session-outcome is attributed with data-minimized identifiers:
/// the PINNED course-space id (`source_course_id` on the session's
/// `pangea.activity_plan` state — the SPECIFIC launching course), and LO
/// REFERENCE IDS — never the free-form learning-objective display text, which
/// can carry authored content / PII once persisted server-side.
void main() {
  late Client client;

  const userId = '@test:fakeServer.notExisting';

  setUp(() async {
    client = await getTestClient();
  });
  tearDown(() async {
    await client.dispose();
  });

  ActivityPlanModel plan() => ActivityPlanModel(
    req: ActivityPlanRequest(
      topic: 'jobs',
      mode: 'Roleplay',
      objective: 'introduce yourself',
      media: MediaEnum.nan,
      cefrLevel: LanguageLevelTypeEnum.a1,
      languageOfInstructions: 'en',
      targetLanguage: 'de',
      numberOfParticipants: 2,
    ),
    title: 'Speed-Dating Interview',
    learningObjective: 'SENSITIVE authored objective text',
    instructions: 'i',
    vocab: const [],
    activityId: 'act-1',
    roles: const {},
  );

  // A session room whose activity_plan state carries the full plan inline (so
  // activityId resolves without hydration) plus the pinned source_course_id.
  Room sessionRoom({String? sourceCourseId = '!pinnedCourse:x'}) {
    final room = Room(id: '!session:fakeServer.notExisting', client: client);
    room.setState(
      Event(
        type: PangeaEventTypes.activityPlan,
        content: {
          ...plan().toJson(),
          ActivitySessionConstants.sourceCourseId: ?sourceCourseId,
        },
        senderId: userId,
        eventId: '\$plan',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    return room;
  }

  test('pinnedSourceCourseId reads the session-pinned course-space id', () {
    expect(sessionRoom().pinnedSourceCourseId, '!pinnedCourse:x');
    expect(sessionRoom(sourceCourseId: null).pinnedSourceCourseId, isNull);
  });

  test(
    'resolveSessionOutcome attributes the PINNED course and LO reference ids '
    '(never the display text)',
    () async {
      final room = sessionRoom();
      final archivedAt = DateTime.utc(2026, 1, 1, 12, 30);
      var resolverGot = '';

      final outcome = await ActivityAutoSaveService.resolveSessionOutcome(
        room: room,
        archivedAt: archivedAt,
        loRefsResolver: (activityId) async {
          resolverGot = activityId;
          return ['lo-ref-1', 'lo-ref-2'];
        },
      );

      expect(outcome, isNotNull);
      // The pinned course-space id, NOT an arbitrary course-plan parent's uuid.
      expect(outcome!.sourceCourseId, '!pinnedCourse:x');
      // LO reference IDS from the resolver — NOT the plan's display text.
      expect(outcome.loRefs, ['lo-ref-1', 'lo-ref-2']);
      expect(
        outcome.loRefs,
        isNot(contains('SENSITIVE authored objective text')),
        reason: 'the free-form learning objective must never ship as an lo_ref',
      );
      expect(
        resolverGot,
        'act-1',
        reason: 'the resolver is keyed by activity id',
      );
      expect(outcome.completedAt, archivedAt);
    },
  );

  test(
    'resolveSessionOutcome is null when the archive did not happen',
    () async {
      expect(
        await ActivityAutoSaveService.resolveSessionOutcome(
          room: sessionRoom(),
          archivedAt: null,
          loRefsResolver: (_) async => const ['lo-ref-1'],
        ),
        isNull,
      );
    },
  );
}
