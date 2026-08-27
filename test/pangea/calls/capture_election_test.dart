import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/capture_election.dart';

void main() {
  bool records(String me, List<String> visible) =>
      CaptureElection(myDeviceId: me, siblingDeviceIds: visible).shouldRecord;

  group('CaptureElection', () {
    test('a lone device records', () {
      // The case that matters most, and it depends on nothing: whatever sync is
      // doing, a device that sees no siblings is the lowest of one.
      expect(records('ZZZZ', const []), isTrue);
    });

    test('the lowest device id records', () {
      expect(records('AAAA', ['ZZZZ']), isTrue);
      expect(records('ZZZZ', ['AAAA']), isFalse);
    });

    test('ordering is by code unit, not case-insensitive collation', () {
      // Device ids are opaque server-issued strings. Comparing them any way but
      // exactly would let two devices disagree about who is lower, and both or
      // neither would record.
      expect(records('ABC', ['abc']), isTrue);
      expect(records('abc', ['ABC']), isFalse);
    });

    test('every device reaches the same verdict', () {
      const ids = ['MMMM', 'AAAA', 'ZZZZ', 'BBBB'];
      final recorders = [
        for (final me in ids)
          if (records(me, ids.where((d) => d != me).toList())) me,
      ];
      expect(recorders, ['AAAA'], reason: 'exactly one, and all agree which');
    });

    test('a device seeing itself listed does not out-rank itself', () {
      // Room state includes this device's own membership, so the caller may or
      // may not have filtered it. Either way the answer is the same.
      expect(records('AAAA', ['AAAA', 'ZZZZ']), isTrue);
      expect(records('ZZZZ', ['AAAA', 'ZZZZ']), isFalse);
    });

    test('a device always counts itself, even when it cannot see itself', () {
      // Losing its own membership write must not make a device conclude it is
      // absent and stop. It ranks itself against what it can see, always.
      expect(records('AAAA', ['ZZZZ']), isTrue);
      expect(records('ZZZZ', const []), isTrue);
    });

    test('seeing more devices can stop recording; seeing fewer never can', () {
      // The one-directional property the whole design rests on.
      const me = 'MMMM';
      expect(records(me, const []), isTrue);
      expect(records(me, ['ZZZZ']), isTrue);
      expect(
        records(me, ['AAAA']),
        isFalse,
        reason: 'a lower sibling appeared',
      );
      expect(
        records(me, const []),
        isTrue,
        reason: 'and it resumes when that sibling goes',
      );
    });

    test('an empty device id is still ranked rather than ignored', () {
      expect(records('', ['AAAA']), isTrue);
      expect(records('AAAA', ['']), isFalse);
    });
  });
}
