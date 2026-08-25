@Timeout(Duration(minutes: 4))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/analytics_access/grant_analytics_access_extension.dart';
import 'package:fluffychat/features/analytics_access/join_room_analytics_access_extension.dart';
import 'package:fluffychat/features/authentication/delete_account_action_enum.dart';
import 'package:fluffychat/features/authentication/delete_account_extension.dart';
import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/room_summaries/activity_session_previews_extension.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/extensions/create_room_extension.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/launch_activity_session.dart';
import 'package:fluffychat/routes/chat/chat_details/delete_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/home/signup/request_token_client_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Tier 2 — Pangea Synapse module endpoint contracts (client#8565).
///
/// Every call goes through the client's real extension methods (raw
/// module-endpoint requests), and every response must parse into the
/// client's own model classes — the models ARE the contract.
void main() {
  if (!EndpointTestEnv.available) {
    test(
      'synapse contract suite is local-only',
      () {},
      skip: 'requires client/.env',
    );
    return;
  }

  late Client clientA;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    clientA = await ContractHarness.loggedIn(ContractHarness.learnerA);
  });

  tearDownAll(() async {
    await ContractHarness.dispose(clientA);
  });

  group('delete_room', () {
    test('the highest-PL member deletes a room via the module', () async {
      final roomId = await clientA.createPangeaGroupChat('Contract delete-me');
      final room = clientA.getRoomById(roomId);
      expect(room, isNotNull);

      await room!.delete();

      // The purge is deliberately deferred (delete_room_purge_delay_seconds,
      // default 7 days) so the leave events survive long enough to sync. The
      // IMMEDIATE contract is: every local member self-leaves with the
      // pangea.room_deleted marker — the exact content key space_gone_gate
      // uses to tell deletion apart from a voluntary leave.
      await ContractHarness.waitUntil(clientA, () {
        final r = clientA.getRoomById(roomId);
        return r == null || r.membership == Membership.leave;
      });
      // A former member may read the room state as of their leave — the
      // server-authoritative view of the self-leave the module wrote.
      final state = await ContractHarness.serverState(clientA, roomId);
      final ownLeave = state['m.room.member']?[clientA.userID];
      expect(ownLeave?['membership'], 'leave');
      expect(
        ownLeave?['pangea.room_deleted'],
        true,
        reason: 'the deletion marker clients key off must ride the leave',
      );
    });
  });

  group('public_courses catalog', () {
    test('a published course appears in the language-filtered catalog and '
        'disappears when unpublished', () async {
      // Public visibility publishes to the room directory at creation —
      // the surface the Synapse 1.126 publish-rule default flip kills
      // without an explicit room_list_publication_rules. This test is the
      // course-discovery canary.
      final courseId = await clientA.createPangeaSpace(
        name: 'Contract Catalog ${DateTime.now().millisecondsSinceEpoch}',
        visibility: Visibility.public,
        joinRules: JoinRules.knock,
        initialState: [
          StateEvent(
            type: 'pangea.course_plan',
            content: {'uuid': 'contract-catalog-uuid', 'l2': 'es'},
          ),
        ],
      );

      Future<bool> catalogContains(String roomId) async {
        String? since;
        for (var page = 0; page < 30; page++) {
          final resp = await clientA.getPublicCourses(
            limit: 50,
            since: since,
            targetLanguage: 'es',
          );
          if (resp.chunk.any((c) => c.roomId == roomId)) return true;
          since = resp.nextBatch;
          if (since == null) return false;
        }
        fail('catalog paging did not terminate within 30 pages');
      }

      expect(
        await catalogContains(courseId),
        true,
        reason:
            'a published es-course must appear in the targetLanguage '
            'filtered catalog (course discovery)',
      );

      await clientA.setRoomVisibilityOnDirectory(
        courseId,
        visibility: Visibility.private,
      );
      expect(
        await catalogContains(courseId),
        false,
        reason: 'unpublishing must remove the course from the catalog',
      );

      // Keep the shared local directory tidy across runs.
      await clientA.getRoomById(courseId)?.delete();
    });
  });

  group('room_preview', () {
    test('batched previews parse and tolerate an unknown room', () async {
      final courseId = await clientA.createPangeaSpace(
        name: 'Contract Preview ${DateTime.now().millisecondsSinceEpoch}',
        visibility: Visibility.private,
        joinRules: JoinRules.knock,
        initialState: [
          StateEvent(
            type: 'pangea.course_plan',
            content: {'uuid': 'contract-preview-uuid', 'l2': 'es'},
          ),
        ],
      );
      final chatId = await clientA.createPangeaGroupChat('Contract preview');
      final bogus = '!contract-bogus:${clientA.userID!.split(':').last}';

      final resp = await clientA.getRoomSummaries([
        courseId,
        chatId,
        bogus,
      ], l1Code: 'en');

      expect(resp.summaries.containsKey(courseId), true);
      expect(resp.summaries.containsKey(chatId), true);
      expect(
        resp.summaries.containsKey(bogus),
        false,
        reason: 'an unknown room must be dropped, not reject the batch',
      );
      expect(resp.summaries[courseId]?.coursePlan?.uuid, isNotNull);
      expect(resp.summaries[courseId]?.joinRule, JoinRules.knock);
    });
  });

  group('activity_session_previews', () {
    test('space-scoped previews surface a launched session', () async {
      final courseId = await clientA.createPangeaSpace(
        name: 'Contract ASP ${DateTime.now().millisecondsSinceEpoch}',
        visibility: Visibility.private,
        joinRules: JoinRules.knock,
      );
      final space = clientA.getRoomById(courseId);
      final sessionId = await clientA.launchActivitySession(
        ActivityPlanModel(
          req: ActivityPlanRequest(
            topic: 'contract',
            mode: 'discussion',
            objective: 'preview surfacing',
            media: MediaEnum.nan,
            cefrLevel: LanguageLevelTypeEnum.a1,
            languageOfInstructions: 'en',
            targetLanguage: 'es',
            numberOfParticipants: 2,
          ),
          title: 'Contract ASP Activity',
          learningObjective: 'preview surfacing',
          instructions: 'talk',
          vocab: [],
          activityId: 'contract-asp-activity',
        ),
        null,
        primarySpace: space,
      );

      final resp = await clientA.getActivitySessionPreviews([
        courseId,
      ], l1Code: 'en');
      expect(
        resp.summaries.containsKey(sessionId),
        true,
        reason:
            'the module must enumerate the space children and return the '
            'activity session (#7982)',
      );
      expect(resp.summaries[sessionId]?.activityId, 'contract-asp-activity');
    });
  });

  group('grant_instructor_analytics_access', () {
    test('the course instructor is invited into the analytics room', () async {
      // Fresh personas per run: the grant issues invites, and Synapse's
      // per-target invite budget accrues across runs on reused accounts.
      final runId = DateTime.now().millisecondsSinceEpoch;
      final teacher = await ContractHarness.loggedIn('contract-t-$runId');
      final learner = await ContractHarness.loggedIn('contract-l-$runId');
      addTearDown(() async {
        await ContractHarness.dispose(teacher);
        await ContractHarness.dispose(learner);
      });

      // Teacher owns the course; the learner joins via code.
      // The grant is gated on the course requiring analytics access
      // (grant-instructor-analytics-access.instructions.md → 403 otherwise).
      final courseId = await teacher.createPangeaSpace(
        name: 'Contract Grant $runId',
        visibility: Visibility.private,
        joinRules: JoinRules.knock,
        initialState: [
          StateEvent(
            type: 'pangea.course_settings',
            content: {'require_analytics_access': true},
          ),
        ],
      );
      final courseState = await ContractHarness.serverState(teacher, courseId);
      final code =
          courseState['m.room.join_rules']?['']?['access_code'] as String;
      await learner.knockWithCode(code); // server-side invite
      await learner.joinRoomByIdWithAccessCheck(courseId);

      // The learner's analytics room (the mirrored p.analytics shape).
      final analyticsRoomId = await learner.createRoom(
        creationContent: {
          'type': PangeaRoomTypes.analytics,
          ModelKey.langCode: 'es',
        },
        name: '${learner.userID} es Analytics',
        preset: CreateRoomPreset.publicChat,
        visibility: Visibility.private,
        initialState: [
          StateEvent(
            type: EventTypes.RoomJoinRules,
            content: {ModelKey.joinRule: JoinRules.knock.name},
          ),
        ],
      );

      await learner.grantInstructorAnalyticsAccess(courseId, analyticsRoomId);

      // The module force-joins server-side; poll the analytics room's
      // server state until the instructor lands.
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (true) {
        final state = await ContractHarness.serverState(
          learner,
          analyticsRoomId,
        );
        final membership =
            state['m.room.member']?[teacher.userID]?['membership'];
        // The module admin-FORCE-JOINS instructors (not an invite the
        // teacher must accept) — the design's whole point.
        if (membership == 'join') break;
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'instructor not force-joined into the analytics room within '
            '15s (membership: $membership)',
          );
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    });
  });

  group('delete_user', () {
    test('schedule, status, and cancel round-trip on a throwaway', () async {
      final throwaway = await ContractHarness.loggedIn(
        'contract-del-${DateTime.now().millisecondsSinceEpoch}',
      );

      final scheduled = await throwaway.deleteAccount(
        action: DeleteAccountAction.schedule,
      );
      expect(scheduled.action, DeleteAccountAction.schedule);
      expect(
        scheduled.executeAtMs,
        isNotNull,
        reason: 'a scheduled deletion must carry its execution time',
      );

      final canceled = await throwaway.deleteAccount(
        action: DeleteAccountAction.cancel,
      );
      expect(canceled.canceled, true);

      await ContractHarness.dispose(throwaway);
    });
  });

  group('register/email/requestToken', () {
    test(
      'the module route is registered and accepts the username field',
      () async {
        // Local stacks have no SMTP relay, so a successful send is not the
        // contract here. What IS the contract: the custom route exists (an
        // M_UNRECOGNIZED would mean the module route vanished) and accepts the
        // non-spec `username` field the client sends.
        final unique = DateTime.now().millisecondsSinceEpoch;
        try {
          await clientA.requestTokenToRegister(
            'contract-secret-$unique',
            'contract-$unique@example.com',
            'contract-reg-$unique',
            1,
          );
        } on MatrixException catch (e) {
          expect(
            e.error,
            isNot(MatrixError.M_UNRECOGNIZED),
            reason: 'the pangea register/email/requestToken route must exist',
          );
        }
      },
    );
  });
}
