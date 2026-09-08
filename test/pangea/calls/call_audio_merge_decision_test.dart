import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge_decision.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

const _callKey = '\$membership:example.com';
const _alice = '@alice:example.com';
const _bob = '@bob:example.com';
const _carol = '@carol:example.com';

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
}) {
  return CallAudioRecording(
    eventId: eventId ?? '\$${device ?? sender}_ev',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    content: CallAudioContent(
      callKey: _callKey,
      deviceId: device,
      url: 'mxc://example.com/audio',
      mimetype: 'audio/wav',
      size: 4096,
      durationMs: 30000,
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
        mergedExists: true,
      );
      expect(verdict, const AlreadyMerged());
    });

    test("TerminallyIneligible('not-a-dm') when isDmRoom is false", () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: false,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
      );
      expect(verdict, const TerminallyIneligible('not-a-dm'));
    });

    test('PendingIncomplete when isDmRoom is not yet known', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1')],
        isDmRoom: null,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
      );
      expect(verdict, const PendingIncomplete());
    });

    test("TerminallyIneligible('more-than-two-halves') for three halves", () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_bob, 'B1'), _half(_carol, 'C1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
      );
      expect(verdict, const TerminallyIneligible('more-than-two-halves'));
    });

    test("TerminallyIneligible('user-with-multiple-halves') for two halves "
        'from the same sender', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1'), _half(_alice, 'A2')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
      );
      expect(verdict, const TerminallyIneligible('user-with-multiple-halves'));
    });

    test('PendingIncomplete for one half (the peer has not posted yet)', () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
      );
      expect(verdict, const PendingIncomplete());
    });

    test("TerminallyIneligible('unplaceable-half') for a truncated half", () {
      final verdict = decideCallAudioMerge(
        halves: [_half(_alice, 'A1', truncated: true), _half(_bob, 'B1')],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
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
          mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
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
        mergedExists: false,
      );
      expect(
        verdict,
        isA<Mergeable>().having((v) => v.coverageEventIds, 'coverageEventIds', [
          '\$aaa_ev',
          '\$zzz_ev',
        ]),
      );
    });

    test('Mergeable: the other poster may have a null deviceId, substituted '
        'as the empty string only for the sort key', () {
      // Step 8 requires MY OWN half to name a device; the OTHER poster's
      // placeable half may still have none (it just never wrote one).
      final verdict = decideCallAudioMerge(
        halves: [
          _half(_alice, 'A1'),
          _half(_bob, null, eventId: '\$b_ev'),
        ],
        isDmRoom: true,
        myUserId: _alice,
        myDeviceId: 'A1',
        mergedExists: false,
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
        mergedExists: false,
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
  });
}
