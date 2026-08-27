import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_presence.dart';

/// The two rules here are relied on by the SDK, undocumented by it, and produce
/// confusing symptoms when wrong — duplicated call UI, or a client that silently
/// refuses every incoming call.
void main() {
  group('CallPresence', () {
    test('starts idle', () {
      final p = CallPresence();
      expect(p.isBusy, isFalse);
      expect(p.liveCount, 0);
    });

    test('announces a call once, however many times the SDK reports it', () {
      final p = CallPresence();
      // handleNewGroupCall fires on remote discovery AND on our own enter(), so the
      // same call is reported at least twice in an ordinary two-person call.
      expect(p.add('!call:pangea.localhost'), isTrue, reason: 'first sighting');
      expect(
        p.add('!call:pangea.localhost'),
        isFalse,
        reason: 'do not announce twice',
      );
      expect(p.liveCount, 1);
    });

    test('stays busy until the last call ends, not the first', () {
      final p = CallPresence();
      p.add('!a');
      p.add('!b');
      expect(p.isBusy, isTrue);

      p.remove('!a');
      expect(
        p.isBusy,
        isTrue,
        reason: 'clearing busy here would let a new call interrupt a live one',
      );

      p.remove('!b');
      expect(p.isBusy, isFalse);
      expect(p.liveCount, 0);
    });

    test('ending an unknown call is a no-op, not an error', () {
      // Duplicate or late end callbacks are normal; they must not underflow the
      // busy state and make the client appear free while a call is up.
      final p = CallPresence();
      p.add('!a');
      expect(p.remove('!never-seen'), isFalse);
      expect(p.isBusy, isTrue);
      expect(p.liveCount, 1);
    });
  });
}
