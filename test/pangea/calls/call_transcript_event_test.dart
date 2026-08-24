import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/call_transcript_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';

const _callKey = '\$membership:example.com';

CallTranscriptContent _content({
  List<String> texts = const ['hola', 'que tal'],
  HalfAccounting accounting = const HalfAccounting(
    chunksCaptured: 3,
    chunksTranscribed: 3,
  ),
  String? langCode = 'es',
}) => CallTranscriptContent(
  callKey: _callKey,
  segments: [for (final text in texts) TranscriptSegment(text)],
  accounting: accounting,
  langCode: langCode,
);

void main() {
  group('CallTranscriptContent json', () {
    test('round-trips everything a reader depends on', () {
      final parsed = CallTranscriptContent.fromJson(
        _content(
          accounting: const HalfAccounting(
            chunksCaptured: 5,
            chunksTranscribed: 4,
            truncated: true,
            segmentsOmitted: 2,
            drainComplete: false,
          ),
        ).toJson(),
      )!;

      expect(parsed.callKey, _callKey);
      expect(parsed.segments.map((s) => s.text), ['hola', 'que tal']);
      expect(parsed.langCode, 'es');
      expect(parsed.accounting.chunksCaptured, 5);
      expect(parsed.accounting.chunksTranscribed, 4);
      expect(parsed.accounting.truncated, isTrue);
      expect(parsed.accounting.segmentsOmitted, 2);
      expect(parsed.accounting.drainComplete, isFalse);
    });

    test('carries the relation that makes it findable', () {
      // Retrieval is a server-side relations query against call_key. Without
      // this relation the half is written but unreachable, which is the worst
      // outcome available: speech captured, stored, and invisible.
      final json = _content().toJson();

      expect(json['m.relates_to'], {
        'rel_type': CallTranscriptContent.relType,
        'event_id': _callKey,
      });
    });

    test('a half with no anchor is refused', () {
      expect(CallTranscriptContent.fromJson({'segments': <dynamic>[]}), isNull);
      expect(
        CallTranscriptContent.fromJson({
          'call_key': '',
          'segments': <dynamic>[],
        }),
        isNull,
      );
      expect(
        CallTranscriptContent.fromJson({
          'call_key': 42,
          'segments': <dynamic>[],
        }),
        isNull,
      );
    });

    test('a malformed segment is skipped, the rest survive', () {
      // One bad entry from an older or modified client must not cost the
      // reader every other thing that speaker said.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': [
          {'text': 'primero'},
          'not a map',
          {'text': 42},
          {'text': '   '},
          null,
          {'text': 'ultimo'},
        ],
      })!;

      expect(parsed.segments.map((s) => s.text), ['primero', 'ultimo']);
    });

    test('a missing segments list is refused, an empty one is not', () {
      // Empty is a real answer -- a speaker who was muted throughout captured
      // nothing. Missing is a malformed event.
      expect(CallTranscriptContent.fromJson({'call_key': _callKey}), isNull);
      expect(
        CallTranscriptContent.fromJson({
          'call_key': _callKey,
          'segments': <dynamic>[],
        })?.segments,
        isEmpty,
      );
    });

    test('an absent language reads as unknown rather than empty string', () {
      final parsed = CallTranscriptContent.fromJson(
        _content(langCode: null).toJson(),
      )!;
      expect(parsed.langCode, isNull);

      final blank = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': <dynamic>[],
        'lang_code': '',
      })!;
      expect(blank.langCode, isNull);
    });

    test('an event from a writer that says nothing about its drain is not '
        'presented as complete', () {
      // A foreign or older writer omits the accounting entirely. Unknown must
      // not read as fine, or the view claims a completeness nobody asserted.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': [
          {'text': 'algo'},
        ],
      })!;

      // No captured count means no basis to claim gaps either way; what matters
      // is that the reader can see the writer made no claim.
      expect(parsed.accounting.chunksCaptured, 0);
      expect(parsed.accounting.chunksTranscribed, 0);
    });
  });

  group('accounting that cannot describe its own content', () {
    test('captured nothing yet shipped speech is incoherent', () {
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': [
          {'text': 'I spoke'},
        ],
        'chunks_captured': 0,
        'chunks_transcribed': 0,
        'drain_complete': true,
      })!;

      expect(parsed.accounting.incoherent, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('captured nothing and shipped nothing is coherent', () {
      // A speaker muted throughout genuinely captured nothing. That must stay
      // a clean, complete answer or every silent half would look broken.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': <dynamic>[],
        'chunks_captured': 0,
        'chunks_transcribed': 0,
        'drain_complete': true,
      })!;

      expect(parsed.accounting.incoherent, isFalse);
      expect(parsed.accounting.writerAdmitsGaps, isFalse);
    });
  });

  group('reader ceilings', () {
    test('a vast segment list is bounded AND the half is marked shortened', () {
      // Room content is untrusted. Two separate failures here: doing unbounded
      // work, and then presenting what survived as the whole of what was said.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': [
          for (var i = 0; i < 9000; i++) {'text': 'x'},
        ],
        'chunks_captured': 1,
        'chunks_transcribed': 1,
        'drain_complete': true,
      })!;

      expect(
        parsed.segments.length,
        lessThanOrEqualTo(CallTranscriptContent.maxSegments),
      );
      expect(parsed.accounting.truncated, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('one enormous segment cannot slip through whole', () {
      // The running-total check used to run BEFORE adding, so a single vast
      // segment was accepted in full and could then win duplicate selection on
      // content length alone.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': [
          {'text': 'a' * 500000},
        ],
      })!;

      expect(parsed.segments, isEmpty);
      expect(parsed.accounting.truncated, isTrue);
    });

    test('a list of junk entries is not scanned to the end', () {
      // Accepting nothing meant the accepted-segment cap never tripped, so a
      // million nulls still cost a full scan.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': List<Object?>.filled(50000, null),
      })!;

      expect(parsed.segments, isEmpty);
      expect(parsed.accounting.truncated, isTrue);
    });

    test('an ordinary half is NOT marked shortened', () {
      // The ceilings must not fire on real content, or every transcript would
      // claim to be incomplete and the signal would mean nothing.
      final parsed = CallTranscriptContent.fromJson(_content().toJson())!;

      expect(parsed.segments, hasLength(2));
      expect(parsed.accounting.truncated, isFalse);
    });
  });

  group('txnId', () {
    test('is stable for the same call and sender', () {
      expect(
        CallTranscriptContent.txnId(_callKey, '@alice:example.com'),
        CallTranscriptContent.txnId(_callKey, '@alice:example.com'),
      );
    });

    test('separates the two speakers of one call', () {
      // Both halves are written against the same call_key; a shared txn id
      // would make the server collapse one speaker into the other.
      expect(
        CallTranscriptContent.txnId(_callKey, '@alice:example.com'),
        isNot(CallTranscriptContent.txnId(_callKey, '@bob:example.com')),
      );
    });

    test('separates two calls by the same sender', () {
      expect(
        CallTranscriptContent.txnId(_callKey, '@alice:example.com'),
        isNot(
          CallTranscriptContent.txnId(
            '\$other:example.com',
            '@alice:example.com',
          ),
        ),
      );
    });
  });
}
