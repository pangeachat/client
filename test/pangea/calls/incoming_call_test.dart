import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/incoming_call.dart';

/// A membership as the room reports it. Only the fields the decision reads.
class FakeMembership implements CallMembership {
  @override
  final String userId;
  @override
  final String deviceId;
  final bool expired;

  FakeMembership(this.userId, {this.deviceId = 'DEV', this.expired = false});

  @override
  bool get isExpired => expired;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const me = '@learner:server';
  const peer = '@teacher:server';

  IncomingCall call(List<CallMembership> memberships) =>
      IncomingCall(memberships: memberships, myUserId: me);

  group('IncomingCall', () {
    test('rings when someone else is in the call and we are not', () {
      final c = call([FakeMembership(peer)]);
      expect(c.shouldRing, isTrue);
      expect(c.callerId, peer);
    });

    test('does not ring for a call this account started', () {
      // The SDK reports our own call back to us. Ringing would mean an outgoing
      // call rings on the device placing it.
      expect(call([FakeMembership(me)]).shouldRing, isFalse);
    });

    test('does not ring once this account has answered', () {
      expect(
        call([FakeMembership(peer), FakeMembership(me)]).shouldRing,
        isFalse,
      );
    });

    test('answering on one device stops another ringing', () {
      // The other device learns from the membership appearing, not a message.
      final answered = call([
        FakeMembership(peer),
        FakeMembership(me, deviceId: 'PHONE'),
      ]);
      expect(answered.shouldRing, isFalse);
    });

    test('does not ring for a call everyone has left', () {
      expect(call(const []).shouldRing, isFalse);
      expect(call(const []).callerId, isNull);
    });

    test('an expired membership is not someone in the call', () {
      // A device that crashed stops renewing. Ringing for it would mean a call
      // nobody is on keeps ringing until the state ages out.
      expect(call([FakeMembership(peer, expired: true)]).shouldRing, isFalse);
    });

    test('our own expired membership does not suppress a real call', () {
      // A stale membership of ours from an earlier call must not make a genuine
      // incoming call silent.
      final c = call([FakeMembership(me, expired: true), FakeMembership(peer)]);
      expect(c.shouldRing, isTrue);
      expect(c.callerId, peer);
    });
  });
}
