// The EXECUTABLE half of the Phase B progression parity gate (spec B.1.0).
//
// `progression_parity_manifest_test.dart` proves this repo's vector bytes match
// the committed manifest — that both repos hold the SAME bytes. It says nothing
// about whether those bytes describe what the Dart resolver actually does. That
// blind spot is not hypothetical: the Python port and its vectors were authored
// together, agreed with each other, and both diverged from the real Dart (a
// threshold FLOOR the resolver has never had). Checksums, 95% coverage and 3349
// green tests all passed while the teacher dashboard disagreed with the
// learner's own app.
//
// So this file pins the fixtures by EXECUTION instead of by hand-trace: every
// vector is fed to the real resolver and the recorded expectation is asserted
// against the real output. Nothing here re-derives resolver logic — the test
// only marshals a vector's `input` into the types the production entry points
// already take, and compares against `expect`.
//
// Entry points under test:
//   rollup_vectors.json      → `resolveProgression(...)`, then the resolution's
//                              own `rollup`, `questStars(...)`, per-quest
//                              `anchorMissionId`, and `missionGradient({ref})`.
//   star_count_vectors.json  → a real `Room` carrying the real Matrix/CMS state
//                              events, read through `Room.ownCompletedGoals`,
//                              `Client.userStarsByActivity` and
//                              `ActivityPlanModel.earnableStars`.
//
// Falsification: change any recorded expectation (or any resolver behaviour it
// pins) and this test must fail. A vector the real Dart disagrees with is a
// genuine parity defect on one side or the other — it is reported, never
// papered over.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import 'package:fluffychat/features/activity_sessions/activity_media_enum.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/quests/lo_progression.dart';
import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

import 'pangea/get_test_client.dart';

Map<String, dynamic> _loadVectorFile(String basename) => jsonDecode(
      File(p.join('test', 'fixtures', 'parity', 'progression', basename))
          .readAsStringSync(),
    ) as Map<String, dynamic>;

/// One vector's `input.outlines` entry as the resolver's own input type. Pure
/// marshalling — every value is copied through verbatim.
CourseLoOutline _outlineFrom(Map<String, dynamic> json) => CourseLoOutline(
      orderedLoIds: List<String>.from(json['ordered_lo_ids'] as List),
      activityIdsByLo:
          (json['activity_ids_by_lo'] as Map<String, dynamic>).map(
        (loId, activityIds) => MapEntry(loId, Set<String>.from(
          activityIds as List,
        )),
      ),
      starsToUnlock: json['stars_to_unlock'] as int,
      earnableByActivity:
          Map<String, int>.from(json['earnable_by_activity'] as Map),
    );

/// A plan carrying the vector's CMS-authored role map. Everything except
/// `roles` is inert filler the plan model requires but no assertion reads.
ActivityPlanModel _planFrom(
  String activityId,
  Map<String, dynamic> planRoles,
) =>
    ActivityPlanModel(
      req: ActivityPlanRequest(
        topic: 'parity',
        mode: 'Roleplay',
        objective: 'parity',
        media: MediaEnum.nan,
        cefrLevel: LanguageLevelTypeEnum.a1,
        languageOfInstructions: 'en',
        targetLanguage: 'es',
        numberOfParticipants: 2,
      ),
      title: 'parity',
      learningObjective: 'lo',
      instructions: 'i',
      vocab: const [],
      activityId: activityId,
      // The real CMS role parser, fed the vector's role JSON unmodified.
      roles: planRoles.map(
        (roleId, role) => MapEntry(
          roleId,
          ActivityRole.fromJson(Map<String, dynamic>.from(role as Map)),
        ),
      ),
    );

/// A session room carrying the three real state events a live activity session
/// holds: the plan (`pangea.activity_plan`), the role assignments
/// (`pangea.activity_roles`) and the orchestrator's awards
/// (`pangea.orchestrator_awarded_goals`).
Room _sessionRoom(
  Client client,
  int index,
  Map<String, dynamic> session,
) {
  final activityId = session['activity_id'] as String;
  final room = Room(id: '!parity-$index:fakeServer.notExisting', client: client);

  void state(String type, Map<String, dynamic> content) => room.setState(
        Event(
          type: type,
          content: content,
          senderId: '@parity:fakeServer.notExisting',
          eventId: '\$parity-$index-$type',
          originServerTs: DateTime.utc(2026, 7, 18),
          stateKey: '',
          room: room,
        ),
      );

  // The room type is authoritative for the activity id (activity_room_extension).
  state(EventTypes.RoomCreate, {
    'type': '${PangeaRoomTypes.activitySession}:$activityId',
  });
  state(
    PangeaEventTypes.activityPlan,
    _planFrom(activityId, session['plan_roles'] as Map<String, dynamic>)
        .toJson(),
  );
  state(PangeaEventTypes.activityRole, {'roles': session['roles']});
  state(
    PangeaEventTypes.orchestratorAwardedGoals,
    Map<String, dynamic>.from(session['awarded_goals'] as Map),
  );

  return room;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final rollupFile = _loadVectorFile('rollup_vectors.json');
  final starCountFile = _loadVectorFile('star_count_vectors.json');

  // The tolerance is the vector file's own declaration, never a locally chosen
  // (looser) one — a test that picks its own tolerance can hide real drift.
  final tolerance = (rollupFile['float_tolerance'] as num).toDouble();

  final rollupVectors =
      (rollupFile['vectors'] as List).cast<Map<String, dynamic>>();
  final starCountVectors =
      (starCountFile['vectors'] as List).cast<Map<String, dynamic>>();

  final executedRollup = <String>{};
  final executedStarCount = <String>{};

  group('progression parity vectors — rollup (executed against the resolver)',
      () {
    test('the resolver constants match the vector header', () {
      // The header's constants are the ones the Python port mirrors. If the
      // Dart moved, every expectation below is being compared against a
      // different resolver than the one the vectors describe.
      expect(kDefaultStarsToUnlockObjective,
          rollupFile['default_stars_to_unlock_objective']);
      expect(kBandFalloffMissions, rollupFile['band_falloff_missions']);
      expect(kBandCeiling, rollupFile['band_ceiling']);
      expect(tolerance, 1e-9);
    });

    for (final vector in rollupVectors) {
      final name = vector['name'] as String;
      executedRollup.add(name);

      test(name, () {
        final input = vector['input'] as Map<String, dynamic>;
        final expected = vector['expect'] as Map<String, dynamic>;
        final pins = (vector['pins'] as List).join('; ');

        final resolution = resolveProgression(
          outlines: (input['outlines'] as List)
              .cast<Map<String, dynamic>>()
              .map(_outlineFrom),
          starsByActivity:
              Map<String, int>.from(input['stars_by_activity'] as Map),
        );

        // --- rollup: stars / threshold / satisfied, per Mission -------------
        final expectedRollup = expected['rollup'] as Map<String, dynamic>;
        expect(
          resolution.rollup.keys.toSet(),
          expectedRollup.keys.toSet(),
          reason: '$name: the rollup covers different Missions than the '
              'vector records — $pins',
        );
        expectedRollup.forEach((missionId, raw) {
          final want = raw as Map<String, dynamic>;
          final got = resolution.rollup[missionId]!;
          expect(got.stars, want['stars'],
              reason: '$name / $missionId stars — $pins');
          expect(got.threshold, want['threshold'],
              reason: '$name / $missionId threshold — $pins');
          expect(got.satisfied, want['satisfied'],
              reason: '$name / $missionId satisfied — $pins');
        });

        // --- quest_stars: the earned/total the quest header renders ---------
        final wantStars = expected['quest_stars'] as Map<String, dynamic>;
        final gotStars = resolution.questStars(
          List<String>.from(input['quest_mission_ids'] as List),
        );
        expect(gotStars.earned, wantStars['earned'],
            reason: '$name quest stars earned — $pins');
        expect(gotStars.total, wantStars['total'],
            reason: '$name quest stars total — $pins');

        // --- anchor: string for one quest, list for several, null for none --
        final wantAnchor = expected['anchor'];
        final gotAnchors =
            resolution.quests.map((q) => q.anchorMissionId).toList();
        if (wantAnchor == null) {
          expect(resolution.quests, isEmpty,
              reason: '$name expects no resolved quest — $pins');
        } else if (wantAnchor is List) {
          expect(gotAnchors, List<String?>.from(wantAnchor),
              reason: '$name anchors — $pins');
        } else {
          expect(gotAnchors, [wantAnchor], reason: '$name anchor — $pins');
        }

        // --- mission_gradient: a SINGLE-ref probe per recorded Mission ------
        (expected['mission_gradient'] as Map<String, dynamic>).forEach(
          (missionId, want) {
            expect(
              resolution.missionGradient({missionId}),
              closeTo((want as num).toDouble(), tolerance),
              reason: '$name / $missionId gradient — $pins',
            );
          },
        );
      });
    }

    test('every rollup vector in the file was executed', () {
      expect(
        executedRollup,
        rollupVectors.map((v) => v['name'] as String).toSet(),
      );
      expect(executedRollup, isNotEmpty);
    });
  });

  group(
      'progression parity vectors — star count (executed against the real '
      'award path)', () {
    for (final vector in starCountVectors) {
      final name = vector['name'] as String;
      executedStarCount.add(name);

      test(name, () async {
        final input = vector['input'] as Map<String, dynamic>;
        final expected = vector['expect'] as Map<String, dynamic>;
        final pins = (vector['pins'] as List).join('; ');

        final client = await getTestClient();
        try {
          // The vectors name their own player; the client must BE that user,
          // because the own-role lookup keys on `client.userID`.
          client.setUserId(input['player'] as String);

          final sessions =
              (input['sessions'] as List).cast<Map<String, dynamic>>();
          final rooms = [
            for (var i = 0; i < sessions.length; i++)
              _sessionRoom(client, i, sessions[i]),
          ];
          client.rooms = rooms;

          // --- own stars per session: len(ownCompletedGoals) ---------------
          expect(
            [for (final room in rooms) room.ownCompletedGoals.length],
            List<int>.from(expected['own_stars_per_session'] as List),
            reason: '$name own stars per session — $pins',
          );

          // --- stars by activity: the MAX across sessions ------------------
          expect(
            client.userStarsByActivity,
            Map<String, int>.from(expected['stars_by_activity'] as Map),
            reason: '$name stars by activity — $pins',
          );

          // --- earnable stars: min(len(allGoals)) across the plan's roles --
          // Read the same getter `QuestRepo` reads when it builds an outline's
          // `earnableByActivity`, once per session room, so a disagreement
          // between two sessions of one activity cannot hide behind a
          // last-write-wins map.
          final wantEarnable =
              Map<String, int>.from(expected['earnable_by_activity'] as Map);
          expect(
            {for (final room in rooms) room.activityId},
            wantEarnable.keys.toSet(),
            reason: '$name resolves different activity ids — $pins',
          );
          for (final room in rooms) {
            expect(
              room.activityPlan!.earnableStars,
              wantEarnable[room.activityId],
              reason: '$name / ${room.activityId} earnable stars — $pins',
            );
          }
        } finally {
          await client.dispose();
        }
      });
    }

    test('every star-count vector in the file was executed', () {
      expect(
        executedStarCount,
        starCountVectors.map((v) => v['name'] as String).toSet(),
      );
      expect(executedStarCount, isNotEmpty);
    });
  });
}
