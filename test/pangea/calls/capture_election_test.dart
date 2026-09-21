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
    // Whole seconds, because that is all `Participant.joinedAt` ever carries:
    // livekit_client multiplies a whole-second protocol field by a thousand.
    final noon = DateTime.utc(2026, 8, 29, 12, 0, 0);
    final aSecondLater = noon.add(const Duration(seconds: 1));
    final muchLater = noon.add(const Duration(seconds: 5));

    const successor = CaptureCandidate('AAAA');

    /// What a device publishes while recording an uninterrupted run.
    String inRun(String run) => CaptureReport.published(run);

    /// A watch that saw the successor in one uninterrupted run all along.
    CaptureWatch watchedRecording([String run = '7']) =>
        CaptureWatch()..observe([CaptureReport.of('AAAA', inRun(run))]);

    bool discards({
      String? published,
      CaptureWatch? watch,
      DateTime? mine,
      DateTime? theirs,
      String reportedDevice = 'AAAA',
    }) => CaptureElection.discardsCapturedAudio(
      successor: successor,
      successorReport: CaptureReport.of(reportedDevice, published),
      watch: watch ?? watchedRecording(),
      myJoinedAt: mine,
      successorJoinedAt: theirs,
    );

    test('a successor recording since before we joined takes our tail', () {
      // The one shape that proves it. Its join stamp is a whole resolution step
      // earlier, so the second it names had ENDED before the second ours began
      // -- it was in the call first however the sub-second truth fell -- it
      // says of itself that audio is reaching its recorder, and it has been in
      // the same run for the whole of the stretch about to be dropped.
      expect(
        discards(published: inRun('7'), mine: aSecondLater, theirs: noon),
        isTrue,
      );
    });

    test('a successor that only says it CAN record keeps our tail', () {
      // Capability is true for silence by design, so a device whose tap
      // attached and then never produced a frame goes on advertising "able"
      // until its own watchdog fires fifteen seconds later. Nothing here may
      // read that as "it recorded": the successor holds nothing, and this tail
      // is the only copy of what the learner said.
      expect(
        discards(
          published: null,
          watch: CaptureWatch(),
          mine: aSecondLater,
          theirs: noon,
        ),
        isFalse,
      );
    });

    test('a successor that says it is NOT recording keeps our tail', () {
      expect(
        discards(
          published: CaptureReport.published(null),
          watch: CaptureWatch(),
          mine: aSecondLater,
          theirs: noon,
        ),
        isFalse,
      );
    });

    test('a value this build cannot read keeps our tail', () {
      // A device speaking a later dialect is not a device telling us anything.
      // It must not attest and it must not deny -- the second is what would
      // wrongly disqualify a sibling that is recording perfectly well.
      expect(
        discards(
          published: 'recording',
          watch: CaptureWatch(),
          mine: aSecondLater,
          theirs: noon,
        ),
        isFalse,
      );
      expect(
        CaptureReport.of('AAAA', 'recording').denies,
        isFalse,
        reason: 'it is silence, not a denial',
      );
    });

    test('a report about a different device keeps our tail', () {
      // Evidence about one sibling can never license destroying a stretch a
      // DIFFERENT sibling was supposed to be holding. Checked in the rule
      // rather than trusted to the call site, because a lookup against the
      // wrong device id is the kind of mistake that reads correctly.
      expect(
        discards(
          published: inRun('7'),
          reportedDevice: 'ZZZZ',
          mine: aSecondLater,
          theirs: noon,
        ),
        isFalse,
      );
    });

    test('two devices joining in the same second keep their tails', () {
      // A stamp of 12:00:00 means "somewhere in the second beginning at
      // 12:00:00", so two equal stamps order NOTHING. The rule this replaced
      // read equality as "the successor was here first": a device that joined
      // at 12:00:00.001 and recorded until a sibling joined at 12:00:00.900
      // threw away nine hundred milliseconds the sibling was never in the room
      // for.
      expect(
        discards(published: inRun('7'), mine: noon, theirs: noon),
        isFalse,
      );
    });

    test('a successor that arrived after us keeps our tail', () {
      expect(
        discards(published: inRun('7'), mine: noon, theirs: muchLater),
        isFalse,
      );
    });

    test('an unknown join time on either side delivers', () {
      // Discarding a learner's speech on the strength of a number nobody
      // stamped is the one outcome this must not produce.
      expect(
        discards(published: inRun('7'), mine: null, theirs: noon),
        isFalse,
      );
      expect(
        discards(published: inRun('7'), mine: aSecondLater, theirs: null),
        isFalse,
      );
    });
  });

  group('what a watcher makes of a stretch it watched', () {
    final noon = DateTime.utc(2026, 8, 29, 12, 0, 0);
    final aSecondLater = noon.add(const Duration(seconds: 1));
    const successor = CaptureCandidate('AAAA');

    CaptureReport says(String? published, [String device = 'AAAA']) =>
        CaptureReport.of(device, published);

    bool discardsWith(CaptureWatch watch, {String published = 'recording:7'}) =>
        CaptureElection.discardsCapturedAudio(
          successor: successor,
          successorReport: CaptureReport.of('AAAA', published),
          watch: watch,
          myJoinedAt: aSecondLater,
          successorJoinedAt: noon,
        );

    test('a run already running when we opened takes our tail', () {
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isTrue);
    });

    test('a run that began AFTER we opened keeps our tail', () {
      // THE CASE A TOKEN ALONE CANNOT ANSWER. A run token proves continuity
      // forward from the moment it was first seen and says nothing about the
      // time before it. The sibling was silent when this stretch opened -- its
      // `no` in flight, or overwritten by the run before we ever read it -- and
      // its first frame came later. It holds the second half of our stretch and
      // not the first, and destroying the whole tail destroys the first half
      // with it.
      final watch = CaptureWatch()
        ..observe([says(null)])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isFalse);
    });

    test('a sibling absent when we opened is never credited', () {
      // Same rule, the other way it happens. Nothing this device observed says
      // anything about what a sibling it could not see was doing, and an
      // earlier join stamp does not fill that in: being in the room is not
      // holding a copy.
      final watch = CaptureWatch()
        ..observe(const [])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isFalse);
    });

    test('a denial after we opened keeps our tail', () {
      // It was recording when we started and it is recording now, so both
      // instantaneous readings say discard. But it TOLD us, in between, that it
      // had stopped -- so its run has a hole in it, and a hole anywhere is
      // fatal because what is destroyed is the whole tail.
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says(CaptureReport.published(null))])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isFalse);
    });

    test('a run that changed after we opened keeps our tail', () {
      // Attribute writes are last-write-wins, so a sibling that stopped and
      // restarted can leave a watcher reading "recording" before and after with
      // the `no` between them never delivered. The token changing is the only
      // evidence the gap happened.
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says('recording:8')]);

      expect(discardsWith(watch, published: 'recording:8'), isFalse);
    });

    test('a run token that comes BACK does not restore standing', () {
      // A DEFENCE rather than a case. A behaving device only ever moves its
      // token forward, so the opening credit already refuses a run that has
      // changed. This is what stops a sibling whose token is not actually
      // monotonic -- a counter that reset, a token minted from something that
      // repeats -- handing itself back a stretch it has already broken.
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says('recording:8')])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isFalse);
    });

    test('silence after we opened is not a break', () {
      // A dropped attribute update, or a write that failed and has not been
      // re-asserted yet, is us not having heard -- not the sibling saying it
      // stopped. Latching that into a denial kept duplicates of stretches the
      // sibling really held.
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says(null)])
        ..observe([says('recording:7')]);

      expect(discardsWith(watch), isTrue);
    });

    test('the same run seen over and over is one uninterrupted stretch', () {
      final watch = CaptureWatch();
      for (var i = 0; i < 5; i++) {
        watch.observe([says('recording:7')]);
      }
      expect(discardsWith(watch), isTrue);
    });

    test('a break against one sibling says nothing about another', () {
      final watch = CaptureWatch()
        ..observe([says('recording:7'), says('recording:2', 'ZZZZ')])
        ..observe([
          says('recording:7'),
          says(CaptureReport.published(null), 'ZZZZ'),
        ]);

      expect(watch.heldThroughout('ZZZZ', '2'), isFalse);
      expect(discardsWith(watch), isTrue);
    });

    test('a new stretch forgets what the previous one watched', () {
      // What was watched while a DIFFERENT stretch was running says nothing
      // about this one -- in both directions. A sibling credited by the last
      // stretch has to earn it again, and one that broke during it is not
      // disqualified for the rest of the call.
      final watch = CaptureWatch()
        ..observe([says('recording:7')])
        ..observe([says(CaptureReport.published(null))]);
      expect(discardsWith(watch), isFalse);

      watch.restart();
      watch.observe([says('recording:7')]);

      expect(discardsWith(watch), isTrue);
    });
  });

  group('what a device is heard to say about its own recording', () {
    test('an affirmative run is read back as that run', () {
      final report = CaptureReport.of('AAAA', CaptureReport.published('42'));
      expect(report.run, '42');
      expect(report.denies, isFalse);
      expect(report.deviceId, 'AAAA');
    });

    test('an explicit no is a denial, not a silence', () {
      final report = CaptureReport.of('AAAA', CaptureReport.published(null));
      expect(report.run, isNull);
      expect(report.denies, isTrue);
    });

    test('silence is neither', () {
      // Three states, and this is the one the two bugs collapsed. An older
      // build publishes nothing; a device whose write is still on the wire has
      // published nothing YET. Neither is a sentence.
      for (final published in [null, '', 'recording', 'recording:', 'later']) {
        final report = CaptureReport.of('AAAA', published);
        expect(report.run, isNull, reason: 'not an attestation: $published');
        expect(report.denies, isFalse, reason: 'not a denial: $published');
      }
    });
  });
}
