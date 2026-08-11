import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/spaces/space_gone_gate.dart';

void main() {
  group('SpaceGoneGate.classify', () {
    test('deleted marker on leave means deleted', () {
      expect(
        SpaceGoneGate.classify(
          membership: Membership.leave,
          hasDeletedMarker: true,
          senderIsSelf: true,
        ),
        SpaceGoneReason.deleted,
      );
    });

    test('leave sent by someone else means removed', () {
      expect(
        SpaceGoneGate.classify(
          membership: Membership.leave,
          hasDeletedMarker: false,
          senderIsSelf: false,
        ),
        SpaceGoneReason.removed,
      );
    });

    test('ban means removed', () {
      expect(
        SpaceGoneGate.classify(
          membership: Membership.ban,
          hasDeletedMarker: false,
          senderIsSelf: false,
        ),
        SpaceGoneReason.removed,
      );
    });

    test('voluntary self-leave is not flagged', () {
      expect(
        SpaceGoneGate.classify(
          membership: Membership.leave,
          hasDeletedMarker: false,
          senderIsSelf: true,
        ),
        isNull,
      );
    });

    test('joined room is not flagged, even with stale marker', () {
      expect(
        SpaceGoneGate.classify(
          membership: Membership.join,
          hasDeletedMarker: true,
          senderIsSelf: true,
        ),
        isNull,
      );
    });
  });
}
