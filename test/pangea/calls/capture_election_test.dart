import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/capture_election.dart';

void main() {
  bool records(String me, List<String> visible) => CaptureElection(
    myDeviceId: me,
    siblings: visible.map(CaptureCandidate.new),
  ).shouldRecord;

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

  group('ranking on capability', () {
    bool recordsAs(
      String me, {
      required bool able,
      required List<CaptureCandidate> visible,
    }) => CaptureElection(
      myDeviceId: me,
      siblings: visible,
      iCanCapture: able,
    ).shouldRecord;

    test('a device that concluded it has no tap point ranks last', () {
      // The whole reason capability is in the order. On device id alone the
      // learner's laptop, which has no working tap, wins every election and the
      // call goes untranscribed while their phone sits second in line and does
      // nothing.
      expect(
        recordsAs(
          'AAAA',
          able: false,
          visible: [const CaptureCandidate('ZZZZ')],
        ),
        isFalse,
        reason: 'a capable sibling out-ranks a lower id that cannot record',
      );
      expect(
        recordsAs(
          'ZZZZ',
          able: true,
          visible: [const CaptureCandidate('AAAA', canCapture: false)],
        ),
        isTrue,
      );
    });

    test('a device says nothing and is still ranked as able', () {
      // Silence reads as ABLE, and the default is load-bearing: an older build
      // publishes no attribute at all, and a sibling seen before its first
      // announcement lands has published none yet. Reading either as "cannot"
      // would have every device out-rank every sibling it had not yet heard
      // from, which at the start of a call is all of them.
      expect(
        recordsAs(
          'ZZZZ',
          able: true,
          visible: [const CaptureCandidate('AAAA')],
        ),
        isFalse,
      );
    });

    test('when no device can record, exactly one still elects itself', () {
      // Capability RANKS; it never vetoes. A fleet that all conclude they
      // cannot record must still pick one to try and report honestly, or a
      // transient that hit every device at once silences the call for good.
      const ids = ['MMMM', 'AAAA', 'ZZZZ'];
      final recorders = [
        for (final me in ids)
          if (recordsAs(
            me,
            able: false,
            visible: [
              for (final other in ids)
                if (other != me) CaptureCandidate(other, canCapture: false),
            ],
          ))
            me,
      ];
      expect(recorders, ['AAAA'], reason: 'exactly one, and all agree which');
    });

    test('every device reaches the same verdict with capability in play', () {
      // The order has to stay TOTAL across both keys, or two devices can
      // disagree about who is lower and both or neither will record.
      const fleet = [
        CaptureCandidate('MMMM'),
        CaptureCandidate('AAAA', canCapture: false),
        CaptureCandidate('ZZZZ'),
      ];
      final recorders = [
        for (final device in fleet)
          if (recordsAs(
            device.deviceId,
            able: device.canCapture,
            visible: [
              for (final other in fleet)
                if (other.deviceId != device.deviceId) other,
            ],
          ))
            device.deviceId,
      ];
      expect(recorders, ['MMMM']);
    });

    test('the successor is the highest-ranked sibling, capability first', () {
      // Named by the SAME order the election uses. Two rankings that could
      // disagree would have this device discard its tail on the strength of a
      // successor that never started recording.
      final election = CaptureElection(
        myDeviceId: 'MMMM',
        siblings: const [
          CaptureCandidate('AAAA', canCapture: false),
          CaptureCandidate('ZZZZ'),
        ],
      );
      expect(election.recordingSuccessor, const CaptureCandidate('ZZZZ'));
    });

    test('a device alone has no successor', () {
      const election = CaptureElection(myDeviceId: 'MMMM', siblings: []);
      expect(election.recordingSuccessor, isNull);
    });
  });

  group('deciding whether a displaced stretch is a duplicate', () {
    final earlier = DateTime.utc(2026, 8, 29, 12, 0, 0);
    final later = DateTime.utc(2026, 8, 29, 12, 0, 5);

    test('two devices joining in the same second discard the loser tail', () {
      // THE reported case. Both devices answer the same ring, each sees a
      // roster that momentarily lacks the other, and both record the opening
      // seconds. joinedAt is exposed in whole SECONDS, so the two stamps are
      // EQUAL -- a strictly-earlier rule would deliver exactly the duplicate
      // this exists to stop.
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: earlier,
          successorJoinedAt: earlier,
          successorRecordedTheSameStretch: true,
        ),
        isTrue,
      );
    });

    test('a successor that was here first discards too', () {
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: later,
          successorJoinedAt: earlier,
          successorRecordedTheSameStretch: true,
        ),
        isTrue,
      );
    });

    test('a successor that arrived after us gets our tail delivered', () {
      // It was not in the call while we were recording, so nobody else holds
      // those words. Discarding them would destroy the only copy.
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: earlier,
          successorJoinedAt: later,
          successorRecordedTheSameStretch: true,
        ),
        isFalse,
      );
    });

    test('a successor that was not recording keeps our tail', () {
      // A successor that had no tap during our stretch was not holding a copy
      // of it, whatever its join time says, so discarding throws away audio
      // nobody else has. The join times still SAY discard here, which is the
      // point: this term overrules them.
      //
      // The conclusion is handed in, because deriving it needs a whole call's
      // worth of capability history. Where it comes from is covered by the
      // active_call tests 'a successor whose microphone just arrived keeps our
      // tail' and 'a handover forced by capability keeps our tail'.
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: later,
          successorJoinedAt: earlier,
          successorRecordedTheSameStretch: false,
        ),
        isFalse,
      );
    });

    test('an unknown join time on either side delivers', () {
      // Discarding a learner's speech on the strength of a number nobody
      // stamped is the one outcome this must not produce.
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: null,
          successorJoinedAt: earlier,
          successorRecordedTheSameStretch: true,
        ),
        isFalse,
      );
      expect(
        CaptureElection.discardsCapturedAudio(
          myJoinedAt: earlier,
          successorJoinedAt: null,
          successorRecordedTheSameStretch: true,
        ),
        isFalse,
      );
    });
  });
}
