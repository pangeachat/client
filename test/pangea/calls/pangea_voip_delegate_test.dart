import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_presence.dart';
import 'package:fluffychat/routes/chat/calls/pangea_voip_delegate.dart';

/// Only the id is read on the discovery path.
class FakeGroupCall implements GroupCallSession {
  @override
  final String groupCallId;
  FakeGroupCall(this.groupCallId);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('CallPresence', () {
    test('a call announced twice is only live once', () {
      final presence = CallPresence();
      expect(presence.add('!room:server'), isTrue);
      expect(presence.add('!room:server'), isFalse);
      expect(presence.isBusy, isTrue);
    });

    test('busy until the last call ends', () {
      final presence = CallPresence();
      presence.add('a');
      presence.add('b');
      presence.remove('a');
      expect(presence.isBusy, isTrue);
      presence.remove('b');
      expect(presence.isBusy, isFalse);
    });
  });

  group('discovering a call', () {
    test('a second call in the same room is announced too', () async {
      // A call id is derived from the room, so every call in a conversation
      // shares one — and a declined call never reaches handleGroupCallEnded to
      // clear it. Suppressing repeats here meant declining once stopped that
      // conversation ever ringing again.
      final announced = <String>[];
      final delegate = PangeaVoipDelegate(
        onGroupCallDiscovered: (call) => announced.add(call.groupCallId),
      );

      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));
      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));
      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));

      expect(
        announced,
        ['!dm:server', '!dm:server', '!dm:server'],
        reason: 'whether to ring is decided from live membership, not novelty',
      );
    });

    test('a call that ended and started again is announced', () async {
      final announced = <String>[];
      final delegate = PangeaVoipDelegate(
        onGroupCallDiscovered: (call) => announced.add(call.groupCallId),
      );

      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));
      await delegate.handleGroupCallEnded(FakeGroupCall('!dm:server'));
      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));

      expect(announced, hasLength(2));
    });
  });
}
