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
      // ...and the half says so. Dropping entries quietly and presenting the
      // rest as whole is the same lie as truncating quietly.
      expect(parsed.accounting.truncated, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
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
        ...const HalfAccounting(drainComplete: true).toJson(),
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
        ...const HalfAccounting(drainComplete: true).toJson(),
      })!;

      expect(parsed.accounting.incoherent, isFalse);
      expect(parsed.accounting.writerAdmitsGaps, isFalse);
    });
  });

  group('accounting that contradicts its own content', () {
    CallTranscriptContent parse({
      required List<Map<String, String>> segments,
      required int captured,
      required int transcribed,
      bool truncated = false,
      int omitted = 0,
    }) => CallTranscriptContent.fromJson({
      'call_key': _callKey,
      'segments': segments,
      ...HalfAccounting(
        chunksCaptured: captured,
        chunksTranscribed: transcribed,
        truncated: truncated,
        segmentsOmitted: omitted,
        drainComplete: true,
      ).toJson(),
    })!;

    test('a chunk transcribed with NO words is incoherent', () {
      // Otherwise this renders as a flat "they said nothing" -- a definite
      // claim about a person, contradicted by the same event's own numbers.
      final parsed = parse(segments: const [], captured: 2, transcribed: 1);

      expect(parsed.accounting.incoherent, isTrue);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('a TRUNCATED half with no words is not incoherent', () {
      // The legitimate way to be in that state: the segments were dropped to
      // fit, the half says so, and it already reads as incomplete. Flagging it
      // would make truncation look like corruption.
      final parsed = parse(
        segments: const [],
        captured: 2,
        transcribed: 1,
        truncated: true,
        omitted: 4,
      );

      expect(parsed.accounting.incoherent, isFalse);
      expect(parsed.accounting.writerAdmitsGaps, isTrue);
    });

    test('a half WE emptied is not accused of impossible numbers', () {
      // The writer sent one segment and one transcribed chunk. Those numbers
      // agree with each other perfectly. WE could not read the segment, so we
      // dropped it -- and the emptiness this test used to see as the writer's
      // contradiction is entirely our own doing.
      //
      // Getting this wrong costs the real diagnosis: `accountingImpossible`
      // outranks `contentUnreadable`, so a reader-side parse failure was
      // reported as the writer having sent numbers that cannot be true, and
      // whoever read that bug report would go looking on the wrong device.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': const [
          {'text': 42},
        ],
        ...const HalfAccounting(
          chunksCaptured: 1,
          chunksTranscribed: 1,
          drainComplete: true,
        ).toJson(),
      })!;

      expect(
        parsed.accounting.declared,
        isTrue,
        reason: 'the writer declared a complete accounting; the check runs',
      );

      expect(parsed.segments, isEmpty);
      expect(parsed.accounting.unreadableContent, isTrue);
      expect(
        parsed.accounting.incoherent,
        isFalse,
        reason: 'the reader emptied this half; the writer did not',
      );
      expect(
        TranscriptHalf(
          senderId: '@a:example.com',
          segments: parsed.segments,
          accounting: parsed.accounting,
          state: HalfState.incomplete,
          readWasCutShort: false,
          participantsWereAGuess: false,
          arrival: HalfArrival.placed,
        ).issue,
        HalfIssue.contentUnreadable,
      );
    });

    test('a refused microphone that dropped segments is impossible', () {
      // A microphone that never opened produced nothing -- and segments the
      // writer omitted TO FIT are produced text, as much as visible ones are.
      // The rule named chunks captured and visible segments and stopped
      // there, so this half was believed and diagnosed as a microphone
      // failure, which is a specific, confident, wrong answer.
      final parsed = CallTranscriptContent.fromJson({
        'call_key': _callKey,
        'segments': const <dynamic>[],
        ...const HalfAccounting(
          captureRefused: true,
          truncated: true,
          segmentsOmitted: 1,
          drainComplete: true,
        ).toJson(),
      })!;

      expect(parsed.accounting.declared, isTrue);
      expect(parsed.accounting.incoherent, isTrue);
      expect(
        TranscriptHalf(
          senderId: '@a:example.com',
          segments: parsed.segments,
          accounting: parsed.accounting,
          state: HalfState.incomplete,
          readWasCutShort: false,
          participantsWereAGuess: false,
          arrival: HalfArrival.placed,
        ).issue,
        HalfIssue.accountingImpossible,
      );
    });

    test('a genuinely silent half stays coherent', () {
      // Nothing captured, nothing transcribed, nothing said. The whole point
      // of the flag is that it does NOT fire here.
      final parsed = parse(segments: const [], captured: 0, transcribed: 0);

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

  group('claims the accounting cannot support', () {
    CallTranscriptContent parse(Map<String, dynamic> extra) =>
        CallTranscriptContent.fromJson({'call_key': _callKey, ...extra})!;

    test('a mic that never opened cannot also have captured audio', () {
      // The coherence check never learned about capture_refused when it was
      // added, so a half could claim the microphone never opened while
      // carrying real chunks and real words -- and the diagnosis then
      // reported a microphone failure for a half whose own numbers said
      // otherwise.
      final parsed = parse({
        'segments': [
          {'text': 'hola'},
        ],
        ...const HalfAccounting(
          chunksCaptured: 3,
          chunksTranscribed: 3,
          captureRefused: true,
          drainComplete: true,
        ).toJson(),
      });

      expect(parsed.accounting.incoherent, isTrue);
    });

    test('an honest refusal is still believed', () {
      // The counterweight: a real refusal carries no chunks and no words.
      final parsed = parse({
        'segments': <dynamic>[],
        ...const HalfAccounting(
          captureRefused: true,
          drainComplete: true,
        ).toJson(),
      });

      expect(parsed.accounting.incoherent, isFalse);
      expect(parsed.accounting.captureRefused, isTrue);
    });

    test('words with nothing that produced them are impossible', () {
      // Zero chunks transcribed means no chunk yielded usable text, so text
      // cannot exist. This shape reached the reader as PRESENT and clean, and
      // the diagnostic stayed silent on it -- the one failure it exists to
      // prevent.
      final parsed = parse({
        'segments': [
          {'text': 'hola'},
        ],
        ...const HalfAccounting(
          chunksCaptured: 1,
          chunksTranscribed: 0,
          drainComplete: true,
        ).toJson(),
      });

      expect(parsed.accounting.incoherent, isTrue);
    });

    test('a TRUNCATED half with words and no count is not impossible', () {
      // The legitimate version: the words that remain came from chunks the
      // count no longer describes.
      final parsed = parse({
        'segments': [
          {'text': 'hola'},
        ],
        ...const HalfAccounting(
          chunksCaptured: 1,
          chunksTranscribed: 0,
          truncated: true,
          segmentsOmitted: 4,
          drainComplete: true,
        ).toJson(),
      });

      expect(parsed.accounting.incoherent, isFalse);
    });

    test('an unreadable entry is not reported as a size problem', () {
      // Both shorten the half. Calling a corrupt entry "too long to send" is a
      // confident, specific, wrong answer to somebody working out what
      // happened.
      final parsed = parse({
        'segments': [
          {'text': 'hola'},
          {'text': 42},
        ],
        ...const HalfAccounting(
          chunksCaptured: 2,
          chunksTranscribed: 2,
          drainComplete: true,
        ).toJson(),
      });

      expect(parsed.accounting.unreadableContent, isTrue);
      expect(parsed.accounting.truncated, isTrue);

      // The flags are not the point -- what somebody READS is. Both a corrupt
      // entry and a writer that could not fit its half set `truncated`, so
      // checking flags alone leaves the wrong diagnosis free to come back.
      expect(
        TranscriptHalf(
          senderId: '@a:example.com',
          segments: parsed.segments,
          accounting: parsed.accounting,
          state: HalfState.incomplete,
          readWasCutShort: false,
          participantsWereAGuess: false,
          arrival: HalfArrival.placed,
        ).issue,
        HalfIssue.contentUnreadable,
      );
    });
  });

  group('a position on the wire', () {
    Map<String, dynamic> half(List<Map<String, dynamic>> segments) => {
      'call_key': _callKey,
      'segments': segments,
      'chunks_captured': 2,
      'chunks_transcribed': 2,
      'chunks_lost': 0,
      'capture_refused': false,
      'truncated': false,
      'segments_omitted': 0,
      'drain_complete': true,
    };

    test('a half written before positions existed still reads as declared', () {
      // Every half already in a room was written without one. A reader that
      // needed a position to accept a segment would drop all of that speech and
      // report those halves as shortened -- our own failure, blamed on them.
      final parsed = CallTranscriptContent.fromJson(
        half([
          {'text': 'hola'},
          {'text': 'que tal'},
        ]),
      )!;

      expect(parsed.segments.map((s) => s.text), ['hola', 'que tal']);
      expect(parsed.segments.map((s) => s.atMs), [null, null]);
      expect(parsed.accounting.declared, isTrue);
      expect(parsed.accounting.readerShortened, isFalse);
      expect(parsed.accounting.unreadableContent, isFalse);
    });

    test('a malformed position does not shorten the half', () {
      // A bad position costs a position. Rejecting the segment would drop
      // speech AND mark the half shortened, which is a reader-side lie about
      // what the writer sent.
      final parsed = CallTranscriptContent.fromJson(
        half([
          {'text': 'hola', 'at_ms': 'soon'},
          {'text': 'que tal', 'at_ms': -1},
        ]),
      )!;

      expect(parsed.segments.map((s) => s.text), ['hola', 'que tal']);
      expect(parsed.segments.map((s) => s.atMs), [null, null]);
      expect(parsed.accounting.truncated, isFalse);
      expect(parsed.accounting.readerShortened, isFalse);
      expect(parsed.accounting.unreadableContent, isFalse);
    });

    test('a sound position survives the round trip', () {
      final written = CallTranscriptContent(
        callKey: _callKey,
        segments: const [
          TranscriptSegment('hola', atMs: 1700000000000),
          TranscriptSegment('que tal', atMs: 1700000003000),
        ],
        accounting: const HalfAccounting(
          chunksCaptured: 1,
          chunksTranscribed: 1,
          declared: true,
        ),
      );

      final parsed = CallTranscriptContent.fromJson(written.toJson())!;
      expect(parsed.segments, written.segments);
    });
  });
}
