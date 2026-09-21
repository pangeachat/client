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
    test('marks the account busy, so a second call is refused', () async {
      // Discovery no longer rings — a state change cannot wake a closed app, so
      // ringing rides an MSC4075 notification. Discovery's only job now is to
      // know a call exists.
      final delegate = PangeaVoipDelegate();
      expect(delegate.canHandleNewCall, isTrue);

      await delegate.handleNewGroupCall(FakeGroupCall('!dm:server'));
      expect(delegate.canHandleNewCall, isFalse);

      await delegate.handleGroupCallEnded(FakeGroupCall('!dm:server'));
      expect(delegate.canHandleNewCall, isTrue);
    });
  });
}
