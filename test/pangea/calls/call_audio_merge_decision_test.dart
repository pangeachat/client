import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge_decision.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

const _callKey = '\$membership:example.com';
const _alice = '@alice:example.com';
const _bob = '@bob:example.com';
const _carol = '@carol:example.com';

/// The direct chat's two members.
const _dm = {_alice, _bob};

/// A trusted merge of the plain call `[_half(_alice, 'A1'), _half(_bob, 'B1')]`.
CallAudioMergedRecording _wholeMerge({
  List<String> sources = const ['\$A1_ev', '\$B1_ev'],
  bool? complete = true,
}) => CallAudioMergedRecording(
  eventId: '\$merged',
  senderId: _alice,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  content: CallAudioMergedContent(
    callKey: _callKey,
    url: 'mxc://example.com/merged',
    mimetype: 'audio/wav',
    size: 4096,
    durationMs: 30000,
    sampleRate: 16000,
    channels: 1,
    codec: kCallAudioCodec,
    mergedStartSfuMs: 1000,
    sourceEventIds: sources,
    complete: complete,
  ),
);

/// Builds one placeable-by-default `pangea.call_audio` half. Every
/// decision-tree test starts from a half that would pass step 7 on its own
/// and overrides only the field it means to break.
CallAudioRecording _half(
  String sender,
  String? device, {
  bool truncated = false,
  int? fileStartSfuMs = 1000,
  String codec = kCallAudioCodec,
  int channels = 1,
  String? eventId,
  String? from,
  String? to,
  int durationMs = 30000,
}) {
  return CallAudioRecording(
    eventId: eventId ?? '\$${device ?? sender}_ev',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    content: CallAudioContent(
      callKey: _callKey,
      deviceId: device,
      continuedFrom: from,
      handedOverTo: to,
      url: 'mxc://example.com/audio',
      mimetype: 'audio/wav',
      size: 4096,
      durationMs: durationMs,
      sampleRate: 16000,
      channels: channels,
      codec: codec,
      clockAnchor: fileStartSfuMs == null
          ? null
          : ClockAnchor(sfuMs: fileStartSfuMs, deviceMs: fileStartSfuMs),
      recordingStartedOffsetFromDeviceJoinMs: fileStartSfuMs == null ? null : 0,
      truncated: truncated,
    ),
  );
}

void main() {
  group('decideCallAudioMerge', () {
    test('AlreadyMerged when mergedExists, even with two good halves', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: [_wholeMerge()],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const AlreadyMerged());
    });

    test("TerminallyIneligible('not-a-dm') when isDmRoom is false", () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: false,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('not-a-dm'));
    });

    test('PendingIncomplete when isDmRoom is not yet known', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: null,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const PendingIncomplete());
    });

    // client#9173: a call is the halves of its two participants; a half from
    // anyone else is not part of it and neither blocks nor joins the merge.
    test('a half from someone outside the chat is not part of the call', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1'), _half(_carol, 'C1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        const Mergeable(
          myRank: 0,
          coverageEventIds: ['\$A1_ev', '\$B1_ev'],
          mergedStartSfuMs: 1000,
        ),
      );
    });

    // client#9173: two halves from one speaker that are not chained -- two of
    // their devices that both carried on -- can never be one whole call.
    test("TerminallyIneligible('unlinked-same-sender') for two unlinked halves "
        'from the same sender', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_alice, 'A2')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unlinked-same-sender'));
    });

    test('PendingIncomplete for one half (the peer has not posted yet)', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const PendingIncomplete());
    });

    test("TerminallyIneligible('unplaceable-half') for a truncated half", () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1', truncated: true), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unplaceable-half'));
    });

    test("TerminallyIneligible('unplaceable-half') for a null fileStartSfuMs "
        'half', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1', fileStartSfuMs: null), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unplaceable-half'));
    });

    // The two tests below isolate EACH of fileStartSfuMs's own two
    // prerequisites in turn (see CallAudioContent.fileStartSfuMs: "BOTH
    // facts or neither"), rather than clearing both at once as the test
    // above does -- so a half with only ONE of the two present is proven
    // unplaceable too, not just a half missing both.
    test("TerminallyIneligible('unplaceable-half') for a half with a clock "
        'anchor but no recording-start offset', () {
      final noOffset = CallAudioRecording(
        eventId: '\$no_offset_ev',
        senderId: _alice,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
        content: const CallAudioContent(
          callKey: _callKey,
          deviceId: 'A1',
          url: 'mxc://example.com/audio',
          mimetype: 'audio/wav',
          size: 4096,
          durationMs: 30000,
          sampleRate: 16000,
          channels: 1,
          codec: kCallAudioCodec,
          clockAnchor: ClockAnchor(sfuMs: 1000, deviceMs: 1000),
          recordingStartedOffsetFromDeviceJoinMs: null,
        ),
      );
      final verdict = decideCallAudioMerge(
        halves: [noOffset, _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unplaceable-half'));
    });

    test("TerminallyIneligible('unplaceable-half') for a half with a "
        'recording-start offset but no clock anchor', () {
      final noAnchor = CallAudioRecording(
        eventId: '\$no_anchor_ev',
        senderId: _alice,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
        content: const CallAudioContent(
          callKey: _callKey,
          deviceId: 'A1',
          url: 'mxc://example.com/audio',
          mimetype: 'audio/wav',
          size: 4096,
          durationMs: 30000,
          sampleRate: 16000,
          channels: 1,
          codec: kCallAudioCodec,
          clockAnchor: null,
          recordingStartedOffsetFromDeviceJoinMs: 0,
        ),
      );
      final verdict = decideCallAudioMerge(
        halves: [noAnchor, _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unplaceable-half'));
    });

    test(
      "TerminallyIneligible('unplaceable-half') for a non-pcm16 codec half",
      () {
        final verdict = decideCallAudioMerge(
          halves: [
            _half(_alice, 'A1', codec: 'opus'),
            _half(_bob, 'B1'),
          ],
          isDmRoom: true,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('unplaceable-half'));
      },
    );

    test("TerminallyIneligible('unplaceable-half') for a non-mono "
        '(channels != 1) half', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1', channels: 2), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const TerminallyIneligible('unplaceable-half'));
    });

    test('NotCandidate for a complete, placeable call this device posted '
        'neither half of', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _carol,
        myDeviceId: 'C1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const NotCandidate());
    });

    // The next two tests deliberately ANTI-correlate eventId and
    // fileStartSfuMs against senderId order: bob (the alphabetically LATER
    // sender) gets the alphabetically EARLIER eventId and the EARLIER start
    // time. If myRank, or coverageEventIds, were computed from eventId or
    // fileStartSfuMs instead of from (senderId, deviceId) -- e.g. an
    // implementation that sorted candidates by eventId, or that assigned
    // myRank by arrival/start order -- these would disagree with the
    // asserted values below even though the earlier, correlated fixtures
    // would have let such a bug pass unnoticed.
    test('Mergeable: myRank is 0 when this device sorts before the other '
        'poster, independent of eventId/start-time order', () {
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_bob, 'B1', eventId: '\$aaa_ev', fileStartSfuMs: 100),
          _half(_alice, 'A1', eventId: '\$zzz_ev', fileStartSfuMs: 9000),
        ],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        const Mergeable(
          myRank: 0,
          coverageEventIds: ['\$aaa_ev', '\$zzz_ev'],
          mergedStartSfuMs: 100,
        ),
      );
    });

    test('Mergeable: myRank is 1 when this device sorts after the other '
        'poster (same pair of halves, roles swapped)', () {
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_bob, 'B1', eventId: '\$aaa_ev', fileStartSfuMs: 100),
          _half(_alice, 'A1', eventId: '\$zzz_ev', fileStartSfuMs: 9000),
        ],
        isDmRoom: true,
        myUserId: _bob,
        myDeviceId: 'B1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        const Mergeable(
          myRank: 1,
          coverageEventIds: ['\$aaa_ev', '\$zzz_ev'],
          mergedStartSfuMs: 100,
        ),
      );
    });

    test('Mergeable: coverageEventIds is sorted ascending regardless of '
        'input order or sender order', () {
      // bob's eventId sorts BEFORE alice's here -- the opposite of their
      // senderId order -- so a coverage list that merely echoed sender or
      // rank order (rather than independently sorting eventIds) would fail.
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_alice, 'A1', eventId: '\$zzz_ev'),
          _half(_bob, 'B1', eventId: '\$aaa_ev'),
        ],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        isA<Mergeable>().having((v) => v.coverageEventIds, 'coverageEventIds', [
          '\$aaa_ev',
          '\$zzz_ev',
        ]),
      );
    });

    test('Mergeable: the other poster may have a null deviceId and the call '
        'is still mergeable with the right rank and coverage', () {
      // Step 8 requires MY OWN half to name a device; the OTHER poster's
      // placeable half may still have none (it just never wrote one). This
      // pins the OBSERVABLE property only: a null other-deviceId neither
      // crashes nor changes my rank or the coverage. How the impl represents
      // that null in its private sort key is NOT asserted here, and could not
      // be -- two distinct senders always decide the order on senderId, so the
      // deviceId tie-break is never reached for a real mergeable pair.
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_alice, 'A1'),
          _half(_bob, null, eventId: '\$b_ev'),
        ],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        const Mergeable(
          myRank: 0,
          coverageEventIds: ['\$A1_ev', '\$b_ev'],
          mergedStartSfuMs: 1000,
        ),
      );
    });

    test('Mergeable: mergedStartSfuMs is the minimum of the two halves', () {
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_alice, 'A1', fileStartSfuMs: 5000),
          _half(_bob, 'B1', fileStartSfuMs: 1500),
        ],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(
        verdict,
        isA<Mergeable>().having(
          (v) => v.mergedStartSfuMs,
          'mergedStartSfuMs',
          1500,
        ),
      );
    });

    test(
      'PendingIncomplete for zero halves (the < 2 boundary, not just one)',
      () {
        final verdict = decideCallAudioMerge(
          halves: const [],
          isDmRoom: true,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const PendingIncomplete());
      },
    );

    test('NotCandidate when this device is the right USER but the wrong DEVICE '
        'of a poster', () {
      // Both halves are placeable and one is alice's, but THIS device is
      // alice on a DIFFERENT device (A9, not the A1 that recorded). Matching
      // on senderId alone would wrongly call this Mergeable; the device id
      // must match too.
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A9',
        merged: const [],
        participants: _dm,
        callKey: _callKey,
      );
      expect(verdict, const NotCandidate());
    });

    // Precedence tests: the tree's ORDER is load-bearing (an earlier verdict
    // must win when two conditions co-occur). Each fixture below activates TWO
    // rules at once and asserts the EARLIER one wins -- so reordering the tree
    // flips exactly one of these RED, which the single-condition fixtures above
    // cannot catch.
    group('precedence (the earlier rule wins when conditions overlap)', () {
      // client#9173: DM-ness is decided first; a merge no longer short-cuts it.
      test('not-a-dm over a trusted merge -> not-a-dm', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
          isDmRoom: false,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: [_wholeMerge()],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('not-a-dm'));
      });

      test('rule 2 over 4: not-a-dm AND three halves -> not-a-dm', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1'), _half(_bob, 'B1'), _half(_carol, 'C1')],
          isDmRoom: false,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('not-a-dm'));
      });

      test('two unchained halves from one sender beside the peer -> '
          'unlinked-same-sender, whatever the third half is', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1'), _half(_alice, 'A2'), _half(_bob, 'B1')],
          isDmRoom: true,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('unlinked-same-sender'));
      });

      test('closure over placeability: two halves from one sender, one '
          'truncated -> unlinked-same-sender (not unplaceable-half)', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1', truncated: true), _half(_alice, 'A2')],
          isDmRoom: true,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('unlinked-same-sender'));
      });

      test('rule 7 over 8: an unplaceable half in a call this device did not '
          'post -> unplaceable-half (not NotCandidate)', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1', truncated: true), _half(_bob, 'B1')],
          isDmRoom: true,
          myUserId: _carol,
          myDeviceId: 'C1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const TerminallyIneligible('unplaceable-half'));
      });

      test('rule 3 over 4: DM-ness unknown AND three halves -> '
          'PendingIncomplete (not more-than-two-halves)', () {
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1'), _half(_bob, 'B1'), _half(_carol, 'C1')],
          isDmRoom: null,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const PendingIncomplete());
      });

      test('rule 6 over 7: a single unplaceable half -> PendingIncomplete '
          '(wait for the peer, not prematurely unplaceable-half)', () {
        // Only my (truncated) half is in yet. The peer may still post, so this
        // is PENDING at the <2-halves check -- placeability is not judged until
        // both halves are present.
        final verdict = decideCallAudioMerge(
          halves: [_half(_alice, 'A1', truncated: true)],
          isDmRoom: true,
          myUserId: _alice,
          myDeviceId: 'A1',
          merged: const [],
          participants: _dm,
          callKey: _callKey,
        );
        expect(verdict, const PendingIncomplete());
      });
    });
  });

  group('a call the learner moved between devices (client#9173)', () {
    // Alice moved from A1 to A2 at 5000; Bob stayed on B1.
    final a1 = _half(_alice, 'A1', to: 'A2', fileStartSfuMs: 1000);
    final a2 = _half(_alice, 'A2', from: 'A1', fileStartSfuMs: 5000);
    final b1 = _half(_bob, 'B1', fileStartSfuMs: 1200);

    CallAudioMergeVerdict decide(
      List<CallAudioRecording> halves, {
      String me = _alice,
      String device = 'A2',
      List<CallAudioMergedRecording> merged = const [],
    }) => decideCallAudioMerge(
      halves: halves,
      merged: merged,
      isDmRoom: true,
      participants: _dm,
      callKey: _callKey,
      myUserId: me,
      myDeviceId: device,
    );

    CallAudioMergedRecording merge(
      List<String> sources, {
      bool? complete = true,
      int start = 1000,
      int durationMs = 34000,
      String id = '\$m',
    }) => CallAudioMergedRecording(
      eventId: id,
      senderId: _bob,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
      content: CallAudioMergedContent(
        callKey: _callKey,
        url: 'mxc://example.com/merged',
        mimetype: 'audio/wav',
        size: 4096,
        durationMs: durationMs,
        sampleRate: 16000,
        channels: 1,
        codec: kCallAudioCodec,
        mergedStartSfuMs: start,
        sourceEventIds: sources,
        complete: complete,
      ),
    );

    final all = ['\$A1_ev', '\$A2_ev', '\$B1_ev'];

    test('a closed chain is merged whole, the moved-from half cut where its '
        'successor began', () {
      final verdict = decide([a1, a2, b1]);
      expect(verdict, isA<Mergeable>());
      final m = verdict as Mergeable;
      expect(m.coverageEventIds, all);
      expect(m.mergedStartSfuMs, 1000);
      expect(m.trimEndSfuMs, {'\$A1_ev': 5000});
      expect(m.myRank, 0, reason: 'A2 and B1 mix; A1 does not');
    });

    test('one side of a link is enough to chain', () {
      final a2Unlinked = _half(_alice, 'A2', fileStartSfuMs: 5000);
      expect(decide([a1, a2Unlinked, b1]), isA<Mergeable>());
    });

    test('the device the call moved FROM never mixes', () {
      expect(decide([a1, a2, b1], device: 'A1'), const NotCandidate());
    });

    test('a link to a half not yet in the room waits', () {
      expect(decide([a1, b1]), const PendingIncomplete());
      expect(decide([a2, b1]), const PendingIncomplete());
    });

    test('a chain longer than four devices is never merged', () {
      final chain = [
        _half(_alice, 'A1', to: 'A2'),
        _half(_alice, 'A2', to: 'A3'),
        _half(_alice, 'A3', to: 'A4'),
        _half(_alice, 'A4', to: 'A5'),
        _half(_alice, 'A5'),
      ];
      expect(
        decide([...chain, b1], device: 'A5'),
        const TerminallyIneligible('chain-too-long'),
      );
    });

    test('links that disagree are never merged', () {
      final a3 = _half(_alice, 'A3', from: 'A1', fileStartSfuMs: 7000);
      expect(
        decide([a1, a2, a3, b1]),
        const TerminallyIneligible('inconsistent-links'),
      );
    });

    test('only a trusted merge of the WHOLE call retires it', () {
      expect(decide([a1, a2, b1], merged: [merge(all)]), const AlreadyMerged());
      // Covering part of the call, claiming incompleteness, starting in the
      // wrong place, or too short to hold the call retires nothing.
      for (final m in [
        merge(['\$A2_ev', '\$B1_ev']),
        merge(all, complete: false),
        merge(all, start: 1200),
        merge(all, durationMs: 2000),
      ]) {
        expect(decide([a1, a2, b1], merged: [m]), isA<Mergeable>());
      }
    });

    test('a merge without `complete` is trusted only for a plain call', () {
      expect(
        decideCallAudioMerge(
          halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
          merged: [_wholeMerge(complete: null)],
          isDmRoom: true,
          participants: _dm,
          callKey: _callKey,
          myUserId: _alice,
          myDeviceId: 'A1',
        ),
        const AlreadyMerged(),
      );
      expect(
        decide([a1, a2, b1], merged: [merge(all, complete: null)]),
        isA<Mergeable>(),
      );
    });

    // @a moved twice (A1 -> A2 -> A3): four halves, fifteen possible parts.
    final c1 = _half(_alice, 'A1', to: 'A2', fileStartSfuMs: 1000);
    final c2 = _half(_alice, 'A2', from: 'A1', to: 'A3', fileStartSfuMs: 5000);
    final c3 = _half(_alice, 'A3', from: 'A2', fileStartSfuMs: 9000);
    final four = [c1, c2, c3, b1];
    List<CallAudioMergedRecording> earlier(int n) {
      const ids = ['\$A1_ev', '\$A2_ev', '\$A3_ev', '\$B1_ev'];
      final out = <CallAudioMergedRecording>[];
      for (var mask = 1; out.length < n; mask++) {
        out.add(
          merge(
            [
              for (var i = 0; i < 4; i++)
                if (mask & (1 << i) != 0) ids[i],
            ],
            id: '\$m$mask',
            complete: false,
          ),
        );
      }
      return out;
    }

    test('a call may be superseded up to eight times', () {
      expect(
        decide(four, device: 'A3', merged: earlier(7)),
        isA<Mergeable>(),
        reason: 'seven distinct earlier coverages: one more is allowed',
      );
    });

    test('no more merges once a call has been superseded eight times', () {
      expect(
        decide(four, device: 'A3', merged: earlier(8)),
        const TerminallyIneligible('supersession-cap'),
      );
    });

    test('a merge of all of H that is not trusted is not a supersession', () {
      expect(
        decide(
          four,
          device: 'A3',
          merged: [
            ...earlier(7),
            merge(
              ['\$A1_ev', '\$A2_ev', '\$A3_ev', '\$B1_ev'],
              id: '\$whole-but-short',
              durationMs: 1,
            ),
          ],
        ),
        isA<Mergeable>(),
      );
    });

    test('merges naming halves outside the call do not use up the cap', () {
      expect(
        decide(
          [a1, a2, b1],
          merged: [
            for (var i = 0; i < 8; i++) merge(['\$x$i'], id: '\$x$i'),
          ],
        ),
        isA<Mergeable>(),
      );
    });
  });
}
