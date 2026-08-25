import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_writer.dart';

const _callKey = '\$membership:example.com';
const _sender = '@alice:example.com';

/// Records what would have gone to the homeserver.
class _Sent {
  final List<Map<String, dynamic>> contents = [];
  final List<String> txnIds = [];

  Future<void> call(Map<String, dynamic> content, String txnId) async {
    contents.add(content);
    txnIds.add(txnId);
  }

  Map<String, dynamic> get only => contents.single;
  int get bytes => utf8.encode(jsonEncode(only)).length;
}

Future<bool> _write(
  _Sent sent, {
  List<String> texts = const ['hola', 'que tal'],
  String? callKey = _callKey,
  int chunksCaptured = 2,
  int chunksTranscribed = 2,
  int chunksLost = 0,
  bool drainComplete = true,
  bool encrypted = false,
  String? langCode = 'es',
  int maxBytes = kMaxHalfBytes,
}) => writeCallTranscript(
  send: sent.call,
  callKey: callKey,
  senderId: _sender,
  segments: [for (final t in texts) TranscriptSegment(t)],
  chunksCaptured: chunksCaptured,
  chunksTranscribed: chunksTranscribed,
  chunksLost: chunksLost,
  drainComplete: drainComplete,
  encrypted: encrypted,
  langCode: langCode,
  maxBytes: maxBytes,
);

void main() {
  group('writeCallTranscript', () {
    test('writes one half, anchored so it can be found again', () async {
      final sent = _Sent();
      expect(await _write(sent), isTrue);

      expect(sent.contents, hasLength(1));
      expect(sent.only['call_key'], _callKey);
      expect(sent.only['m.relates_to'], {
        'rel_type': CallTranscriptContent.relType,
        'event_id': _callKey,
      });
      expect(
        sent.txnIds.single,
        CallTranscriptContent.txnId(_callKey, _sender),
      );
    });

    test('round-trips through the reader', () async {
      final sent = _Sent();
      await _write(sent, texts: ['uno', 'dos']);

      final parsed = CallTranscriptContent.fromJson(sent.only)!;
      expect(parsed.segments.map((s) => s.text), ['uno', 'dos']);
      expect(parsed.accounting.declared, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isFalse);
    });

    test('writes NOTHING when there is no anchor', () async {
      // A half nobody can query is worse than none: it looks like the feature
      // worked while the words are unreachable for good.
      final sent = _Sent();
      expect(await _write(sent, callKey: null), isFalse);
      expect(await _write(sent, callKey: ''), isFalse);
      expect(sent.contents, isEmpty);
    });

    test('a speaker who said nothing still writes an empty half', () async {
      // "They were silent" and "we have no half for them" are different
      // answers, and the reader can only tell them apart if silence is stated.
      final sent = _Sent();
      expect(
        await _write(
          sent,
          texts: const [],
          chunksCaptured: 0,
          chunksTranscribed: 0,
        ),
        isTrue,
      );

      final parsed = CallTranscriptContent.fromJson(sent.only)!;
      expect(parsed.segments, isEmpty);
      expect(parsed.accounting.declared, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isFalse);
    });

    test('an abandoned drain is declared, not hidden', () async {
      final sent = _Sent();
      await _write(sent, drainComplete: false);

      final parsed = CallTranscriptContent.fromJson(sent.only)!;
      expect(parsed.accounting.drainComplete, isFalse);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('a chunk the writer LOST is declared as a gap', () async {
      final sent = _Sent();
      await _write(
        sent,
        chunksCaptured: 5,
        chunksTranscribed: 3,
        chunksLost: 2,
      );

      final parsed = CallTranscriptContent.fromJson(sent.only)!;
      expect(parsed.accounting.chunksLost, 2);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('captured-but-silent chunks are NOT declared as a gap', () async {
      // The ordinary shape of a real call: five chunks captured, three with
      // speech in them. Reading the difference as loss marked essentially
      // every transcript incomplete, which left the flag meaning nothing.
      final sent = _Sent();
      await _write(sent, chunksCaptured: 5, chunksTranscribed: 3);

      final parsed = CallTranscriptContent.fromJson(sent.only)!;
      expect(parsed.accounting.writerAdmitsGaps, isFalse);
    });

    group('packing', () {
      test('a half over the ceiling is truncated AND says so', () async {
        final sent = _Sent();
        await _write(
          sent,
          texts: [
            for (var i = 0; i < 400; i++) 'segmento numero $i de relleno',
          ],
          maxBytes: 2000,
        );

        final parsed = CallTranscriptContent.fromJson(sent.only)!;
        expect(parsed.segments.length, lessThan(400));
        expect(parsed.accounting.truncated, isTrue);
        expect(parsed.accounting.segmentsOmitted, greaterThan(0));
        expect(parsed.accounting.writerAdmitsGaps, isTrue);
      });

      test('what is written actually fits under the ceiling', () async {
        // The point of the cap is that the event is accepted by the server. A
        // half that is marked truncated and still too large has failed twice.
        final sent = _Sent();
        await _write(
          sent,
          texts: [
            for (var i = 0; i < 400; i++) 'segmento numero $i de relleno',
          ],
          maxBytes: 2000,
        );

        expect(sent.bytes, lessThanOrEqualTo(2000));
      });

      test('the START of the conversation is what survives', () async {
        // Dropping from the tail: the beginning is what a reader needs to make
        // sense of the rest.
        final sent = _Sent();
        await _write(
          sent,
          texts: ['primero', for (var i = 0; i < 400; i++) 'relleno $i'],
          maxBytes: 1000,
        );

        final parsed = CallTranscriptContent.fromJson(sent.only)!;
        expect(parsed.segments.first.text, 'primero');
      });

      test('a fitting half is NOT marked truncated', () async {
        // The flag must not fire on ordinary content, or every transcript
        // would claim to be short and the signal would mean nothing.
        final sent = _Sent();
        await _write(sent);

        final parsed = CallTranscriptContent.fromJson(sent.only)!;
        expect(parsed.accounting.truncated, isFalse);
        expect(parsed.accounting.segmentsOmitted, 0);
      });

      test('JSON escaping cannot push the half over the limit', () async {
        // The event goes on the wire as JSON, where a quote costs two bytes, a
        // newline two, and a control character six. Adding up plain UTF-8
        // lengths undercounted all of those, so a half could be packed,
        // believed to fit, and still be rejected -- losing the WHOLE half
        // rather than its tail.
        final sent = _Sent();
        await _write(
          sent,
          texts: [
            for (var i = 0; i < 300; i++) 'dijo "hola"\n\ty \u0000 luego $i',
          ],
          maxBytes: 2000,
        );

        expect(sent.bytes, lessThanOrEqualTo(2000));
      });

      test('re-labelling as truncated cannot cross the line', () async {
        // The accounting grows when segments_omitted goes from 0 to a large
        // number. Packing against a half that claimed nothing was omitted and
        // then re-labelling it would add those digits after the check.
        final sent = _Sent();
        await _write(
          sent,
          texts: [for (var i = 0; i < 5000; i++) 'relleno $i'],
          maxBytes: 1200,
        );

        expect(sent.bytes, lessThanOrEqualTo(1200));
      });

      test(
        'an ENCRYPTED half is packed well under the plaintext ceiling',
        () async {
          // The room inflates what the writer hands it, and the server's limit
          // applies to the inflated event. Packing to the plaintext ceiling gets
          // the WHOLE half rejected, and a retry re-packs to the same wrong
          // budget, so the loss never recovers.
          final plain = _Sent();
          await _write(
            plain,
            texts: [for (var i = 0; i < 400; i++) 'segmento numero \$i'],
            maxBytes: 4000,
          );

          final sealed = _Sent();
          await _write(
            sealed,
            texts: [for (var i = 0; i < 400; i++) 'segmento numero \$i'],
            maxBytes: 4000,
            encrypted: true,
          );

          expect(
            sealed.bytes * kEncryptedOverheadFactor,
            lessThanOrEqualTo(4000),
            reason: 'the inflated event still fits the ceiling',
          );
          expect(
            sealed.bytes,
            lessThan(plain.bytes),
            reason: 'the encrypted budget is genuinely tighter',
          );
        },
      );

      test('non-Latin text is measured in BYTES, not characters', () async {
        // Counting characters would size a CJK transcript at a third of its
        // real weight and blow the ceiling it was checked against.
        final sent = _Sent();
        await _write(
          sent,
          texts: [for (var i = 0; i < 300; i++) '猫が犬と話しています'],
          maxBytes: 1500,
        );

        expect(sent.bytes, lessThanOrEqualTo(1500));
      });
    });
  });
}
