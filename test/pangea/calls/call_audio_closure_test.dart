import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_closure.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';

const _key = r'$call';
const _a = '@a:s';
const _b = '@b:s';
const _dm = {_a, _b};

CallAudioRecording _half(
  String sender,
  String device, {
  int start = 1000,
  int durationMs = 10000,
  String? from,
  String? to,
}) => CallAudioRecording(
  eventId: '\$$device',
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  content: CallAudioContent(
    callKey: _key,
    deviceId: device,
    continuedFrom: from,
    handedOverTo: to,
    url: 'mxc://s/$device',
    mimetype: 'audio/wav',
    size: 10,
    durationMs: durationMs,
    sampleRate: 16000,
    channels: 1,
    codec: kCallAudioCodec,
    clockAnchor: ClockAnchor(sfuMs: start, deviceMs: start),
    recordingStartedOffsetFromDeviceJoinMs: 0,
  ),
);

CallAudioMergedRecording _merge(
  List<String> sources, {
  String sender = _a,
  String callKey = _key,
  int start = 1000,
  int durationMs = 20000,
  bool? complete = true,
  String id = r'$m',
}) => CallAudioMergedRecording(
  eventId: id,
  senderId: sender,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  content: CallAudioMergedContent(
    callKey: callKey,
    url: 'mxc://s/m',
    mimetype: 'audio/wav',
    size: 10,
    durationMs: durationMs,
    sampleRate: 16000,
    channels: 1,
    codec: kCallAudioCodec,
    mergedStartSfuMs: start,
    sourceEventIds: sources,
    complete: complete,
  ),
);

void main() {
  // @a moved from A1 to A2 at 6000; @b stayed on B1.
  final a1 = _half(_a, 'A1', to: 'A2');
  final a2 = _half(_a, 'A2', from: 'A1', start: 6000, durationMs: 15000);
  final b1 = _half(_b, 'B1', durationMs: 20000);

  group('closing a call', () {
    test(
      'a moved speaker chains in call order, whatever order they come in',
      () {
        final closed = closeCall([a2, b1, a1], _dm) as ClosedCall;
        expect(closed.chains[_a]!.map((h) => h.eventId), [r'$A1', r'$A2']);
        expect(closed.trimEndSfuMs, {r'$A1': 6000});
        expect(closed.startSfuMs, 1000);
        // A1 cut at 6000; A2 runs to 21000; B1 to 21000: 20000 from 1000.
        expect(closed.trimmedSpanMs, 20000);
        expect(closed.isPlain, isFalse);
      },
    );

    test('a half from outside the chat is not part of the call', () {
      final closed =
          closeCall([_half(_a, 'A1'), b1, _half('@c:s', 'C1')], _dm)
              as ClosedCall;
      expect(closed.halves, hasLength(2));
      expect(closed.isPlain, isTrue);
    });

    test('one speaker so far is open; one that can never chain is broken '
        'even so', () {
      expect(closeCall([_half(_a, 'A1')], _dm), isA<OpenCall>());
      expect(
        (closeCall([_half(_a, 'A1'), _half(_a, 'A2')], _dm) as BrokenCall)
            .reason,
        'unlinked-same-sender',
      );
    });

    test('a link to a half not in the room keeps the call open', () {
      expect(closeCall([a1, b1], _dm), isA<OpenCall>());
    });

    test('unknown participants keep the call open', () {
      expect(closeCall([a1, a2, b1], const {_a}), isA<OpenCall>());
    });
  });

  group('the one trust test', () {
    final closed = closeCall([a1, a2, b1], _dm) as ClosedCall;
    final all = [r'$A1', r'$A2', r'$B1'];

    bool trusted(CallAudioMergedRecording m) => isTrustedWholeMerge(
      merged: m,
      closed: closed,
      participants: _dm,
      callKey: _key,
    );

    test('a complete merge of exactly the whole call is trusted', () {
      expect(trusted(_merge(all)), isTrue);
    });

    test('anything less, more or other is not', () {
      expect(trusted(_merge(all, sender: '@c:s')), isFalse);
      expect(trusted(_merge(all, callKey: r'$other')), isFalse);
      expect(trusted(_merge([r'$A2', r'$B1'])), isFalse);
      expect(trusted(_merge([...all, r'$X'])), isFalse);
      expect(trusted(_merge(all, start: 1200)), isFalse);
      expect(trusted(_merge(all, durationMs: 18999)), isFalse);
      expect(trusted(_merge(all, durationMs: 19000)), isTrue);
      expect(trusted(_merge(all, complete: false)), isFalse);
    });

    test('a merge without `complete` is trusted only for a plain call', () {
      expect(trusted(_merge(all, complete: null)), isFalse);
      final plain = closeCall([_half(_a, 'A1'), b1], _dm) as ClosedCall;
      expect(
        isTrustedWholeMerge(
          merged: _merge([r'$A1', r'$B1'], complete: null),
          closed: plain,
          participants: _dm,
          callKey: _key,
        ),
        isTrue,
      );
    });

    test('every reader settles on the same trusted merge', () {
      final chosen = selectTrustedMerge(
        merged: [
          _merge(all, id: r'$m2'),
          _merge([r'$A2', r'$B1'], id: r'$m0'),
          _merge(all, id: r'$m1'),
        ],
        closed: closed,
        participants: _dm,
        callKey: _key,
      );
      expect(chosen?.eventId, r'$m1');
    });
  });
}
