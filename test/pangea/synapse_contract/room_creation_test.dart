import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/client_spaces_extension.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Tier 1 — room-creation contract tests (client#8565).
///
/// Each test drives the client's real creation extension against the live
/// Synapse at `SYNAPSE_URL`, then asserts the server-side state read-back:
/// the custom request shape must not only be accepted, it must survive the
/// server round-trip unchanged. This is the layer that broke in the last
/// Synapse upgrade attempt.
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
    EndpointTestEnv.load();
    client = await ContractHarness.loggedIn(ContractHarness.learnerA);
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  group('createPangeaSpace (course space)', () {
    test('the launched-course shape round-trips through Synapse', () async {
      // Mirrors selected_course_page.dart's "Launch course": public
      // visibility, knock join rules, members may add space children,
      // course plan + settings as initial state.
      final name = 'Contract Course ${DateTime.now().millisecondsSinceEpoch}';
      final roomId = await client.createPangeaSpace(
        name: name,
        topic: 'synapse-contract-suite fixture',
        visibility: Visibility.public,
        joinRules: JoinRules.knock,
        spaceChild: 0,
        initialState: [
          StateEvent(
            type: 'pangea.course_plan',
            content: {'uuid': 'contract-course-uuid', 'l2': 'es'},
          ),
          StateEvent(
            type: 'pangea.course_settings',
            content: {'require_analytics_access': true},
          ),
        ],
      );
      expect(roomId, isNotEmpty);

      final state = await ContractHarness.serverState(client, roomId);

      // m.room.create carries the space type from creationContent.
      expect(state['m.room.create']?['']?['type'], 'm.space');

      // The custom join-rules content: knock, with the non-spec access_code
      // key intact. A server that starts validating join_rules content
      // strictly (or a module regression) breaks course join codes here.
      final joinRules = state['m.room.join_rules']?[''];
      expect(joinRules, isNotNull, reason: 'join_rules initial state missing');
      expect(joinRules?['join_rule'], 'knock');
      expect(
        joinRules?['access_code'],
        isA<String>().having((c) => c.isNotEmpty, 'non-empty', true),
        reason: 'non-spec access_code must survive the server round-trip',
      );

      // power_level_content_override is a SHALLOW merge server-side: the
      // override's top-level keys replace Synapse's generated content, and
      // the untouched generated users map must still hold the creator at 100.
      final powerLevels = state['m.room.power_levels']?[''];
      expect(powerLevels, isNotNull);
      expect((powerLevels?['users'] as Map?)?[client.userID], 100);
      final eventLevels = powerLevels?['events'] as Map?;
      expect(
        eventLevels?['m.space.child'],
        0,
        reason: 'spaceChild: 0 lets course members attach activity sessions',
      );
      expect(eventLevels?['m.room.power_levels'], 100);
      expect(eventLevels?['m.room.join_rules'], 100);
      expect(powerLevels?['state_default'], 50);

      // Custom initial-state events landed as sent.
      expect(state['pangea.course_plan']?[''], {
        'uuid': 'contract-course-uuid',
        'l2': 'es',
      });
      expect(state['pangea.course_settings']?[''], {
        'require_analytics_access': true,
      });

      // Name and topic round-trip (trimmed by the extension, not the server).
      expect(state['m.room.name']?['']?['name'], name);
      expect(
        state['m.room.topic']?['']?['topic'],
        'synapse-contract-suite fixture',
      );
    });
  });
}
