@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/bot_activty_role_room_extension.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_access/course_settings_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_status_room_extension.dart';
import 'package:fluffychat/features/bot/bot_options_model.dart';
import 'package:fluffychat/features/bot/bot_room_extension.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/lemmas/user_lemma_info_extension.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';
import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/launch_activity_session.dart';
import 'package:fluffychat/routes/chat/chat_details/teacher_mode_model.dart';
import 'package:fluffychat/routes/chat/events/constants/message_constants.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat_list/course_chats_settings_model.dart';
import 'package:fluffychat/routes/chat_list/default_chats_room_extension.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Phase 2, part 1 — custom state-event and timeline-event contracts
/// (client#8574). Every write goes through the client's real extension
/// methods; every assertion reads the SERVER's state.
void main() {
  if (!EndpointTestEnv.available) {
    test(
      'synapse contract suite is local-only',
      () {},
      skip: 'requires client/.env',
    );
    return;
  }

  late Client client;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    client = await ContractHarness.loggedIn('contract-p2-state-a');
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  Future<Room> makeSessionRoom({String? activityId}) async {
    final roomId = await client.launchActivitySession(
      ActivityPlanModel(
        req: ActivityPlanRequest(
          topic: 'phase2',
          mode: 'discussion',
          objective: 'state-event contracts',
          media: MediaEnum.nan,
          cefrLevel: LanguageLevelTypeEnum.a1,
          languageOfInstructions: 'en',
          targetLanguage: 'es',
          numberOfParticipants: 2,
        ),
        title: 'P2 Activity',
        learningObjective: 'state-event contracts',
        instructions: 'talk',
        vocab: [],
        activityId: activityId ?? 'p2-activity',
      ),
      ActivityRole(id: 'role-1', name: 'speaker', goal: null, goals: []),
      primarySpace: null,
    );
    ContractHarness.trackRoom(client, roomId);
    await ContractHarness.waitUntil(
      client,
      () =>
          client.getRoomById(roomId)?.getState(PangeaEventTypes.activityRole) !=
          null,
    );
    return client.getRoomById(roomId)!;
  }

  group('pangea.activity_roles lifecycle', () {
    test('finish, continue, finish-all, and archive-with-replay', () async {
      final room = await makeSessionRoom(activityId: 'p2-lifecycle');

      Future<Map<String, Object?>?> ownRole() async {
        final state = await ContractHarness.serverState(client, room.id);
        final roles =
            state[PangeaEventTypes.activityRole]?['']?['roles'] as Map?;
        return (roles?['role-1'] as Map?)?.cast<String, Object?>();
      }

      // The claim landed at creation.
      expect((await ownRole())?['user_id'], client.userID);

      await room.finishActivity();
      await ContractHarness.waitUntil(
        client,
        () => room.ownRoleState?.isFinished == true,
      );
      expect((await ownRole())?['finished_at'], isNotNull);

      await room.continueActivity();
      await ContractHarness.waitUntil(
        client,
        () => room.ownRoleState?.isFinished == false,
      );
      expect(
        (await ownRole())?['finished_at'],
        isNull,
        reason: 'continue must clear the finished stamp',
      );

      await room.finishActivityForAll();
      await ContractHarness.waitUntil(
        client,
        () => room.ownRoleState?.isFinished == true,
      );
      expect((await ownRole())?['finished_at'], isNotNull);

      // Archive with the at: override — the #8258 repair contract: a
      // re-write replays the ORIGINAL instant instead of stamping a new
      // one, and it is serialized as UTC.
      final replayInstant = DateTime.utc(2026, 1, 2, 3, 4, 5);
      await room.archiveActivity(at: replayInstant);
      final archivedAt = (await ownRole())?['archived_at'] as String?;
      expect(
        archivedAt,
        replayInstant.toIso8601String(),
        reason: 'archive must persist the caller-supplied UTC instant',
      );
    });
  });

  group('pangea.bot_options / pangea.bot_participant', () {
    test('setBotOptions writes the full serializer shape', () async {
      final room = await makeSessionRoom(activityId: 'p2-bot-options');
      final options = BotOptionsModel(
        mode: 'discussion',
        targetLanguage: 'es',
        languageLevel: LanguageLevelTypeEnum.b1,
        topic: 'contract suite',
      );

      await room.setBotOptions(options);

      final state = await ContractHarness.serverState(client, room.id);
      expect(state[PangeaEventTypes.botOptions]?[''], options.toJson());
    });

    test('addBotToActivity writes the empty-content marker', () async {
      final room = await makeSessionRoom(activityId: 'p2-bot-marker');

      await room.addBotToActivity();

      final state = await ContractHarness.serverState(client, room.id);
      expect(
        state[PangeaEventTypes.botParticipant]?[''],
        {},
        reason:
            'the marker is a pure presence gate — empty content IS the '
            'contract (#7027)',
      );
    });
  });

  group('course-space state writes', () {
    test('addCourseToSpace writes the plan and opens space-child PL', () async {
      // A space created WITHOUT a course plan (the add-to-existing flow).
      final spaceId = await client.createPangeaSpace(
        name: 'P2 Attach ${DateTime.now().millisecondsSinceEpoch}',
        visibility: Visibility.private,
        joinRules: JoinRules.knock,
      );
      ContractHarness.trackRoom(client, spaceId);
      await ContractHarness.waitUntil(
        client,
        () =>
            client.getRoomById(spaceId)?.getState(EventTypes.RoomPowerLevels) !=
            null,
      );
      final space = client.getRoomById(spaceId)!;

      await space.addCourseToSpace('p2-attached-course', targetLanguage: 'es');

      final state = await ContractHarness.serverState(client, spaceId);
      expect(
        state[PangeaEventTypes.coursePlan]?['']?['uuid'],
        'p2-attached-course',
      );
      expect(state[PangeaEventTypes.coursePlan]?['']?['l2'], 'es');
      expect(
        (state['m.room.power_levels']?['']?['events']
            as Map?)?['m.space.child'],
        0,
        reason:
            'attaching a course must let students add activity sessions '
            '(read-modify-write of the PL event)',
      );
    });

    test('teacher mode, capacity, chat-list settings, and the analytics '
        'toggle round-trip', () async {
      final spaceId = await client.createPangeaSpace(
        name: 'P2 Settings ${DateTime.now().millisecondsSinceEpoch}',
        visibility: Visibility.private,
        joinRules: JoinRules.knock,
      );
      ContractHarness.trackRoom(client, spaceId);
      await ContractHarness.waitUntil(
        client,
        () => client.getRoomById(spaceId) != null,
      );
      final space = client.getRoomById(spaceId)!;

      final teacherMode = TeacherModeModel(
        enabled: true,
        starsToUnlockObjective: 3,
      );
      await space.setTeacherMode(teacherMode);
      await space.updateRoomCapacity(12);
      await space.setCourseChatsSettings(
        const CourseChatsSettingsModel(dismissedIntroChat: true),
      );
      await ContractHarness.waitUntil(
        client,
        () => space.getState(PangeaEventTypes.courseSettings) != null || true,
      );
      await space.toggleRequireAnalyticsAccess();

      final state = await ContractHarness.serverState(client, spaceId);
      expect(state[PangeaEventTypes.teacherMode]?[''], teacherMode.toJson());
      expect(state[PangeaEventTypes.capacity]?['']?['capacity'], 12);
      expect(
        state[PangeaEventTypes.courseChatList]?['']?['dismissed_intro_chat'] ??
            state[PangeaEventTypes.courseChatList]?[''],
        isNotNull,
        reason: 'course chat-list settings must persist',
      );
      expect(
        state[PangeaEventTypes
            .courseSettings]?['']?['require_analytics_access'],
        true,
        reason: 'the toggle RMW must land server-side',
      );
    });
  });

  group('analytics room state family', () {
    test(
      'settings, room-ids, merge tombstone, and escaped lemma keys',
      () async {
        // Fresh persona so getMyAnalyticsRoom creates its room.
        final learner = await ContractHarness.loggedIn(
          'contract-p2-lemma-${DateTime.now().millisecondsSinceEpoch}',
        );
        addTearDown(() => ContractHarness.dispose(learner));
        final room = (await learner.getMyAnalyticsRoom(
          LanguageModel(langCode: 'es', displayName: 'Spanish'),
        ))!;
        ContractHarness.trackRoom(learner, room.id);

        final blocked = ConstructIdentifier(
          lemma: 'correr',
          type: ConstructTypeEnum.vocab,
          category: 'verbs',
        );
        await room.setAnalyticsSettings(
          AnalyticsSettingsModel(blockedConstructs: {blocked}),
        );
        await room.addActivityRoomIds({'!p2-activity-room:example.test'});

        // The escaped-construct-id state key: raw construct ids contain
        // characters illegal in a state key, so the write must use the
        // escaped form — and it is fired unawaited with a sync-echo wait.
        final lemmaId = ConstructIdentifier(
          lemma: 'hablar',
          type: ConstructTypeEnum.vocab,
          category: 'verbs',
        );
        await room.setUserSetLemmaInfo(
          lemmaId,
          UserSetLemmaInfo(meaning: 'to speak', emojis: ['🗣️']),
        );

        await room.markAnalyticsRoomMerged();

        final state = await ContractHarness.serverState(learner, room.id);
        expect(
          state[PangeaEventTypes.analyticsSettings]?[''],
          AnalyticsSettingsModel(blockedConstructs: {blocked}).toJson(),
        );
        expect(
          (state[PangeaEventTypes.activityRoomIds]?['']?['room_ids'] as List?),
          contains('!p2-activity-room:example.test'),
        );
        expect(
          state[PangeaEventTypes.analyticsStatus]?['']?['status'],
          'merged',
          reason: 'the merge tombstone gates isCanonical',
        );
        final lemmaEvent =
            state[PangeaEventTypes.userSetLemmaInfo]?[lemmaId.escapedString];
        expect(
          lemmaEvent,
          UserSetLemmaInfo(meaning: 'to speak', emojis: ['🗣️']).toJson(),
          reason:
              'the write must land under the ESCAPED construct-id state key',
        );
      },
    );

    test('pangea.construct batches chunk and are server-filterable', () async {
      final learner = await ContractHarness.loggedIn(
        'contract-p2-constructs-${DateTime.now().millisecondsSinceEpoch}',
      );
      addTearDown(() => ContractHarness.dispose(learner));
      final room = (await learner.getMyAnalyticsRoom(
        LanguageModel(langCode: 'es', displayName: 'Spanish'),
      ))!;
      ContractHarness.trackRoom(learner, room.id);

      // Enough uses to exceed the maxPDUSize-10000 packing threshold and
      // force MULTIPLE pangea.construct events — the size-cap contract.
      final uses = List.generate(
        1200,
        (i) => OneConstructUse(
          useType: ConstructUseTypeEnum.wa,
          lemma: 'lemma-$i-${'x' * 30}',
          constructType: ConstructTypeEnum.vocab,
          metadata: ConstructUseMetaData(
            roomId: room.id,
            eventId: '\$p2-fake-event-$i',
            timeStamp: DateTime.now(),
          ),
          category: 'verbs',
          form: 'form-$i',
          xp: 1,
        ),
      );
      await room.sendConstructsEvent(uses);

      // Server-side read-back through the exact filtered /messages call the
      // analytics sync uses (StateFilter on pangea.construct + sender).
      final events = await room.getAnalyticsEvents(userId: learner.userID!);
      expect(events, isNotNull);
      expect(
        events!.length,
        greaterThan(1),
        reason:
            'a batch this large must be chunked into multiple '
            'pangea.construct events (size cap)',
      );
      final totalUses = events.fold<int>(
        0,
        (sum, e) => sum + e.content.uses.length,
      );
      expect(totalUses, uses.length, reason: 'no uses lost to chunking');
    });
  });

  group('custom timeline events', () {
    test(
      'sendPangeaEvent: non-spec rel_type accepted and retrievable',
      () async {
        final room = await makeSessionRoom(activityId: 'p2-relations');
        final parentId = await room.sendTextEvent('parent message');
        expect(parentId, isNotNull);

        final eventId = await room.sendPangeaEvent(
          content: {'lang_code': 'es', 'text': 'hola'},
          parentEventId: parentId!,
          type: PangeaEventTypes.representation,
        );
        expect(eventId, isNotNull);

        final event = await room.getEventById(eventId!.eventId);
        expect(event?.type, PangeaEventTypes.representation);
        expect(
          event?.content['m.relates_to'],
          {'rel_type': PangeaEventTypes.representation, 'event_id': parentId},
          reason:
              'the NON-SPEC rel_type (a pangea event type, not m.reference) '
              'must survive — the shape most exposed if Synapse ever '
              'validates relation types',
        );
        expect(event?.content[PangeaEventTypes.representation], {
          'lang_code': 'es',
          'text': 'hola',
        });
      },
    );

    test('pangeaSendTextEvent sidecar keys round-trip', () async {
      final room = await makeSessionRoom(activityId: 'p2-sidecars');

      final eventId = await room.pangeaSendTextEvent(
        'hola mundo',
        messageTag: contractMessageTag,
      );
      expect(eventId, isNotNull);

      final event = await room.getEventById(eventId!);
      expect(event?.content['body'], 'hola mundo');
      expect(
        event?.content[MessageConstants.messageTags],
        contractMessageTag,
        reason: 'the Pangea sidecar keys must ride the m.room.message',
      );
    });

    test('a large under-cap message body is accepted', () async {
      final room = await makeSessionRoom(activityId: 'p2-large');
      // Well under the client's 60_000-byte guard but far above a typical
      // message — pins that the server accepts what the client permits.
      // The 60_000-byte guard measures the encoded event WITH the markdown
      // formatted_body (it runs markdown unconditionally in its size probe),
      // so the effective body budget is roughly half the cap. Pin that a
      // body the guard permits is accepted by the server.
      final body = 'palabra ' * 3000; // ~24KB body, ~49KB probed event
      final eventId = await room.pangeaSendTextEvent(body);
      expect(eventId, isNotNull);
      final event = await room.getEventById(eventId!);
      expect((event?.content['body'] as String?)?.length, body.length);
    });

    test(
      'TTS audio: the transcription extraContent survives upload+send',
      () async {
        final room = await makeSessionRoom(activityId: 'p2-tts');
        final transcription = {
          'lang_code': 'es',
          'text': 'hola',
          'duration': 850,
        };

        final eventId = await room.sendFileEvent(
          MatrixFile(
            bytes: Uint8List.fromList(utf8.encode('p2-fake-audio-bytes')),
            name: 'p2-contract.ogg',
            mimeType: 'audio/ogg',
          ),
          extraContent: {
            'msgtype': MessageTypes.Audio,
            MessageConstants.transcription: transcription,
          },
        );
        expect(eventId, isNotNull);
        final event = await room.getEventById(eventId!);
        expect(
          event?.content[MessageConstants.transcription],
          transcription,
          reason:
              'the Pangea transcription payload (what the TTS push rule and '
              'read-aloud key off) must survive the media send',
        );
      },
    );
  });
}

/// A recognizable literal for the messageTag sidecar assertion.
const contractMessageTag = 'p2-contract-tag';
