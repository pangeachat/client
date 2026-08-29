@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/common/constants/default_power_level.dart';
import '../endpoint_test_env.dart';
import 'contract_harness.dart';

/// Room-v12 canaries (client#8565 §4).
///
/// default_power_level.dart documents that re-listing the room CREATOR in
/// power_level_content_override.users is forbidden by room v12 / MSC4289.
/// Our homeservers pin default_room_version "11", so nothing hits this today —
/// these canaries pre-enumerate the breakage for the day the pin moves.
///
/// They self-skip on a server that cannot create v12 rooms at all
/// (Synapse 1.124), and run on 1.159+, where they assert the documented
/// incompatibility is REAL: if a canary ever fails, either Synapse changed
/// behavior or the limitation note is stale — both worth knowing immediately.
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
  late bool v12Supported;

  setUpAll(() async {
    await ContractHarness.initTestEnvironment();
    client = await ContractHarness.loggedIn('contract-canary-a');
    v12Supported = await ContractHarness.roomVersionSupported(client, '12');
  });

  tearDownAll(() async {
    await ContractHarness.dispose(client);
  });

  test('v12 creation works without a users map (control)', () async {
    if (!v12Supported) {
      markTestSkipped('homeserver cannot create v12 rooms');
      return;
    }
    // Control FIRST: if v12 creation is broken generally (or rate-limited),
    // this is the test that says so, instead of the canary "passing" on an
    // unrelated rejection.
    final roomId = await client.createRoom(
      roomVersion: '12',
      visibility: Visibility.private,
      name: 'Contract v12 control',
      powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(),
    );
    ContractHarness.trackRoom(client, roomId);
    final state = await ContractHarness.serverState(client, roomId);
    expect(state['m.room.create']?['']?['room_version'], '12');
  });

  test('creator re-listed in the PL override is rejected on v12', () async {
    if (!v12Supported) {
      markTestSkipped('homeserver cannot create v12 rooms');
      return;
    }
    // The users-map override every Pangea chat/session creation sends. The
    // matcher pins the rejection CLASS: a schema/param refusal, explicitly
    // not a rate limit and not "v12 unsupported" (those would make the
    // canary lie about what it proved). Tighten to the exact errcode on the
    // first 1.159 run.
    await expectLater(
      client.createRoom(
        roomVersion: '12',
        visibility: Visibility.private,
        name: 'Contract v12 canary',
        powerLevelContentOverride: RoomDefaults.defaultPowerLevelsContent(
          ownUserId: client.userID!,
          botUserId: BotName.byEnvironment,
        ),
      ),
      throwsA(
        isA<MatrixException>().having(
          (e) => e.error,
          'errcode',
          anyOf(
            MatrixError.M_BAD_JSON,
            MatrixError.M_INVALID_PARAM,
            MatrixError.M_FORBIDDEN,
            MatrixError.M_UNKNOWN,
          ),
        ),
      ),
      reason:
          'default_power_level.dart documents this shape as forbidden on '
          'v12 — if it now succeeds (or fails as a rate limit), the '
          'limitation note and the planned version-conditional users map '
          'need revisiting',
    );
  });
}
