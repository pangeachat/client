import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_ownership.dart';
import 'package:fluffychat/routes/chat/calls/call_predecessor.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

void main() {
  const join = 1000000;
  final window =
      (CallPredecessor.ringLifetime + CallPredecessor.margin).inMilliseconds;

  group('the latest the ring can have gone out', () {
    int? bound({
      int? anchor = join,
      bool placed = false,
      bool glare = false,
      bool rejoined = false,
      int? ringReturned,
      int? peerRing,
    }) => CallPredecessor.ringUpperSfuMs(
      anchorSfuMs: anchor,
      placed: placed,
      peerAlsoPlaced: glare,
      rejoined: rejoined,
      ringReturnedAfterConnectStartMs: ringReturned,
      peerRingArrivedAfterConnectStartMs: peerRing,
    );

    test('a device that was rung, or joined one under way: its own join', () {
      expect(bound(), join);
    });

    test('the placer: when its ring returned', () {
      expect(bound(placed: true, ringReturned: 4000), join + 4000);
      expect(
        bound(placed: true),
        isNull,
        reason: 'a ring that never returned bounds nothing',
      );
    });

    test('glare: the later of the two rings', () {
      expect(
        bound(placed: true, glare: true, ringReturned: 4000, peerRing: 9000),
        join + 9000,
      );
      expect(
        bound(placed: true, glare: true, ringReturned: 4000, peerRing: -500),
        join + 4000,
      );
      expect(bound(glare: true, peerRing: 1200), join + 1200);
      expect(
        bound(glare: true, peerRing: -500),
        join - 500,
        reason: 'their ring reached us before we began connecting',
      );
      expect(bound(glare: true), isNull);
    });

    test('no anchor, or a rejoin, bounds nothing', () {
      expect(bound(anchor: null), isNull);
      expect(bound(rejoined: true), isNull);
    });
  });

  group('the predecessor rule', () {
    bool rule({
      bool talked = true,
      List<int> siblings = const [],
      int? ring = join,
    }) => CallPredecessor.isPredecessor(
      talkedBeforeFirstSibling: talked,
      siblingFirstJoinSfuMs: siblings,
      ringUpperSfuMs: ring,
    );

    test('a sibling past the ring window, after a conversation, is a move', () {
      expect(rule(siblings: [join + window + 1]), isTrue);
    });

    test('inside the window it is an answer race', () {
      expect(rule(siblings: [join + window]), isFalse);
      expect(rule(siblings: [join + 5000]), isFalse);
    });

    test('the EARLIEST sibling decides', () {
      expect(rule(siblings: [join + window + 1, join + 5000]), isFalse);
    });

    test('no conversation first, no ring bound, or no sibling: not a move', () {
      expect(rule(talked: false, siblings: [join + window + 1]), isFalse);
      expect(rule(ring: null, siblings: [join + window + 1]), isFalse);
      expect(rule(), isFalse);
    });
  });

  group('what the arbiter latches for it', () {
    test(
      "a sibling's first join is kept through its leaving and rejoining",
      () {
        final o = CallOwnership();
        o.noteSiblings(joinSfuById: {'SIB': 5000}, talking: true);
        o.noteSiblings(joinSfuById: {}, talking: true);
        o.noteSiblings(joinSfuById: {'SIB': 99000}, talking: true);
        expect(o.siblingFirstJoinSfuMs, [5000]);
      },
    );

    test('a join the SFU had not stated yet is taken when it is', () {
      final o = CallOwnership();
      o.noteSiblings(joinSfuById: {'SIB': null}, talking: false);
      o.noteSiblings(joinSfuById: {'SIB': 7000}, talking: true);
      expect(o.siblingFirstJoinSfuMs, [7000]);
    });

    test('whether a conversation came first is read at the FIRST sighting', () {
      final o = CallOwnership();
      expect(o.sawSibling, isFalse);
      o.noteSiblings(joinSfuById: {}, talking: true);
      expect(o.sawSibling, isFalse, reason: 'no sibling yet');
      o.noteSiblings(joinSfuById: {'SIB': 1}, talking: false);
      o.noteSiblings(joinSfuById: {'SIB': 1}, talking: true);
      expect(o.talkedBeforeFirstSibling, isFalse);
      expect(o.sawSibling, isTrue);
    });

    test('a fresh call forgets all of it', () {
      final o = CallOwnership();
      o.noteSiblings(joinSfuById: {'SIB': 1}, talking: true);
      o.reset();
      expect(o.siblingFirstJoinSfuMs, isEmpty);
      expect(o.sawSibling, isFalse);
      expect(o.talkedBeforeFirstSibling, isFalse);
    });
  });

  group('the links on the wire', () {
    test('a transcript half carries both links and reads them back', () {
      final json = const CallTranscriptContent(
        callKey: r'$k',
        segments: [],
        accounting: HalfAccounting(),
        deviceId: 'LAPTOP',
        continuedFrom: 'PHONE',
        handedOverTo: 'TABLET',
      ).toJson();
      expect(json['continued_from'], 'PHONE');
      expect(json['handed_over_to'], 'TABLET');
      final back = CallTranscriptContent.fromJson(json)!;
      expect(back.continuedFrom, 'PHONE');
      expect(back.handedOverTo, 'TABLET');
    });

    test('an audio half carries both links and reads them back', () {
      final json = const CallAudioContent(
        callKey: r'$k',
        deviceId: 'LAPTOP',
        continuedFrom: 'PHONE',
        handedOverTo: 'TABLET',
        url: 'mxc://s/a',
        mimetype: 'audio/wav',
        size: 10,
        durationMs: 10,
        sampleRate: 16000,
        channels: 1,
        codec: 'pcm16',
      ).toJson();
      final back = CallAudioContent.fromJson(json)!;
      expect(back.continuedFrom, 'PHONE');
      expect(back.handedOverTo, 'TABLET');
    });

    test('no move, no keys; a malformed link reads as none', () {
      final json = const CallTranscriptContent(
        callKey: r'$k',
        segments: [],
        accounting: HalfAccounting(),
      ).toJson();
      expect(json.containsKey('continued_from'), isFalse);
      expect(json.containsKey('handed_over_to'), isFalse);
      final back = CallTranscriptContent.fromJson({
        ...json,
        'continued_from': 7,
        'handed_over_to': '',
      })!;
      expect(back.continuedFrom, isNull);
      expect(back.handedOverTo, isNull);
    });
  });
}
