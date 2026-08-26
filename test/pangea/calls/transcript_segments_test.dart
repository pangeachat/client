import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/speech_to_text_response_model.dart';

/// Builds a response the way the provider actually hands one back, so these
/// tests exercise the same gates production does rather than a stand-in.
SpeechToTextResponseModel _response(
  String text, {
  List<(String word, int? start, int? end)>? timings,
}) => SpeechToTextResponseModel.fromJson({
  'results': [
    {
      'transcripts': [
        {
          'transcript': text,
          'confidence': 90,
          'stt_tokens': <dynamic>[],
          'lang_code': 'es-ES',
          'words_per_hr': null,
          if (timings != null)
            'word_timings': [
              for (final (word, start, end) in timings)
                {
                  'word': word,
                  'start_time_ms': start,
                  'end_time_ms': end,
                  'confidence': 90,
                },
            ],
        },
      ],
    },
  ],
});

/// Where the call's audio starts, as far as these tests are concerned. Any
/// plausible Unix millisecond will do; what matters is that a position is this
/// plus an offset into the chunk, so an assertion can name both.
const _chunkStart = 1700000000000;

/// One transcribed chunk, positioned in the call.
///
/// [durationMs] is the chunk's own length, which the positioning rule measures
/// word timings against. Generous by default, so a test that is not ABOUT the
/// ceiling does not have to think about it — a real chunk runs up to ninety
/// seconds.
TranscribedChunk _chunk(
  String text, {
  List<(String word, int? start, int? end)>? timings,
  int startedAtMs = _chunkStart,
  int durationMs = 90000,
}) => TranscribedChunk(
  result: _response(text, timings: timings),
  startedAtMs: startedAtMs,
  durationMs: durationMs,
);

/// A chunk the provider answered with nothing readable in.
final _emptyChunk = TranscribedChunk(
  result: SpeechToTextResponseModel.fromJson({'results': <dynamic>[]}),
  startedAtMs: _chunkStart,
  durationMs: 90000,
);

void main() {
  group('buildSegments', () {
    test('a chunk without word timings becomes one segment, not none', () {
      // The provider is documented as omitting timings, and they are never
      // fabricated. Dropping such a chunk would lose speech it did read.
      final segments = buildSegments([_chunk('hola que tal')]);

      expect(segments.map((s) => s.text), ['hola que tal']);
    });

    test('a pause longer than the threshold splits one chunk in two', () {
      final segments = buildSegments([
        _chunk(
          'hola que tal muy bien',
          timings: [
            ('hola', 0, 300),
            ('que', 350, 600),
            ('tal', 620, 900),
            // 1.4s of silence: a new utterance.
            ('muy', 2300, 2600),
            ('bien', 2650, 2900),
          ],
        ),
      ]);

      expect(segments.map((s) => s.text), ['hola que tal', 'muy bien']);
    });

    test('a gap shorter than the threshold does NOT split', () {
      // Guards the boundary from the other side: without this a hesitation
      // would start a new line and the transcript would read as stutter.
      final segments = buildSegments([
        _chunk(
          'hola que tal',
          timings: [('hola', 0, 300), ('que', 500, 700), ('tal', 900, 1100)],
        ),
      ]);

      expect(segments.map((s) => s.text), ['hola que tal']);
    });

    test('chunk order is preserved across chunks', () {
      // The sink hands responses over already sorted by PcmChunk.index; this
      // proves the builder does not reorder them.
      final segments = buildSegments([
        _chunk('primero'),
        _chunk('segundo'),
        _chunk('tercero'),
      ]);

      expect(segments.map((s) => s.text), ['primero', 'segundo', 'tercero']);
    });

    test('a chunk the provider could not read is skipped, not emitted', () {
      final segments = buildSegments([
        _chunk('antes'),
        _emptyChunk,
        _chunk('despues'),
      ]);

      expect(segments.map((s) => s.text), ['antes', 'despues']);
    });

    test('a word with no start time cannot open a gap', () {
      // Timestamps are nullable per the model's own contract. A null start
      // must not be read as 0 and split the utterance there.
      final segments = buildSegments([
        _chunk(
          'uno dos tres',
          timings: [('uno', 0, 300), ('dos', null, null), ('tres', 400, 700)],
        ),
      ]);

      expect(segments.map((s) => s.text), ['uno dos tres']);
    });

    test('a word with an unknown END cannot be measured from a stale one', () {
      // 'two' has no end time, so the gap before 'three' is unmeasurable and
      // must not be computed from 'one' end. Measuring it from the stale 300
      // split an utterance that had no pause in it.
      final segments = buildSegments([
        _chunk(
          'one two three',
          timings: [
            ('one', 0, 300),
            ('two', 2000, null),
            ('three', 2050, 2300),
          ],
        ),
      ]);

      expect(segments.map((s) => s.text), ['one', 'two three']);
    });

    test('timings that are all blank fall back to the chunk text', () {
      final segments = buildSegments([
        _chunk('texto real', timings: [('   ', 0, 100), ('', 200, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['texto real']);
    });

    test('a LATER chunk with all-blank timings still falls back', () {
      // The fallback used to ask whether any segment existed at all, so a
      // blank-timing chunk was dropped whenever an earlier chunk had produced
      // something -- losing speech, and only in calls long enough to have a
      // second chunk.
      final segments = buildSegments([
        _chunk('antes'),
        _chunk('texto real', timings: [('   ', 0, 100), ('', 200, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['antes', 'texto real']);
    });

    test('timings covering only part of the text lose to the full text', () {
      // "hello world" timed as ["hello"] must not become "hello". A partial
      // timing list is not a finer cut of the text, it is an incomplete one.
      final segments = buildSegments([
        _chunk('hello world', timings: [('hello', 0, 100)]),
      ]);

      expect(segments.map((s) => s.text), ['hello world']);
    });

    test('timings covering the text are still preferred', () {
      // The coverage floor must not fire on ordinary input, or word timings
      // would never be used and every chunk would be one wall of text.
      final segments = buildSegments([
        _chunk(
          'hola que tal muy bien',
          timings: [
            ('hola', 0, 300),
            ('que', 350, 600),
            ('tal', 620, 900),
            ('muy', 2300, 2600),
            ('bien', 2650, 2900),
          ],
        ),
      ]);

      expect(segments.map((s) => s.text), ['hola que tal', 'muy bien']);
    });

    test('a SHORT word dropped off a long one is still caught', () {
      // A character ratio could not see this: timings for the long word alone
      // cover well over 80% of the text, and 'bye' was quietly lost.
      final segments = buildSegments([
        _chunk(
          'supercalifragilisticexpialidocious bye',
          timings: [('supercalifragilisticexpialidocious', 0, 900)],
        ),
      ]);

      expect(segments.map((s) => s.text), [
        'supercalifragilisticexpialidocious bye',
      ]);
    });

    test('timings that REPLACE a word fall back rather than fabricate', () {
      // The worst failure this builder can have. Same word count, different
      // words: a count check passed these and the output became
      // "pay alice today" -- losing "bob" and inventing "alice". A learner is
      // read as having said something they did not.
      final segments = buildSegments([
        _chunk(
          'pay bob today',
          timings: [('pay', 0, 200), ('alice', 250, 500), ('today', 550, 800)],
        ),
      ]);

      expect(segments.map((s) => s.text), ['pay bob today']);
    });

    test('a substituted CJK word is caught, not normalised away', () {
      // `[^\w\s]` deleted every CJK character, so 猫 and 犬 both became the
      // empty string and compared EQUAL -- the fabrication guard passed a
      // substituted word straight through. This product teaches twenty-odd
      // languages; ASCII-shaped normalisation is not acceptable here.
      final segments = buildSegments([
        _chunk('猫', timings: [('犬', 0, 100)]),
      ]);

      expect(segments.map((s) => s.text), ['猫']);
    });

    test('matching CJK timings are still preferred', () {
      // The guard must not fire on correct non-Latin input either, or word
      // timings would be unusable for those languages.
      final segments = buildSegments([
        _chunk('猫 犬', timings: [('猫', 0, 100), ('犬', 150, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['猫 犬']);
    });

    test('punctuation INSIDE a word still distinguishes it', () {
      // Stripping punctuation everywhere made "he'll" and "hell" compare
      // equal, so the guard against a substituted word let that substitution
      // straight through. Only edge punctuation may be forgiven.
      final segments = buildSegments([
        _chunk("he'll go", timings: [('hell', 0, 100), ('go', 150, 300)]),
      ]);

      expect(segments.map((s) => s.text), ["he'll go"]);
    });

    test('a symbol that changes a word is not stripped away', () {
      final segments = buildSegments([
        _chunk('C++ rocks', timings: [('C', 0, 100), ('rocks', 150, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['C++ rocks']);
    });

    test('case alone does not trigger the fallback', () {
      final segments = buildSegments([
        _chunk(
          'Hola que tal',
          timings: [('hola', 0, 200), ('QUE', 250, 500), ('tal', 550, 800)],
        ),
      ]);

      expect(segments, hasLength(1));
      expect(segments.single.text, 'hola QUE tal');
    });

    test('punctuation the timings omit DOES trigger the fallback', () {
      // This test previously asserted the opposite -- that punctuation should
      // be forgiven, so that segmentation stayed usable. Every attempt to
      // forgive it let a real substitution through as well ("he'll" vs "hell",
      // "C++" vs "C"). Coarser segmentation is the price of never altering
      // what someone said.
      final segments = buildSegments([
        _chunk(
          'Hola, que tal?',
          timings: [('Hola', 0, 200), ('que', 250, 500), ('tal', 550, 800)],
        ),
      ]);

      expect(segments.map((s) => s.text), ['Hola, que tal?']);
    });

    test('no usable chunks yields no segments', () {
      expect(buildSegments([_emptyChunk]), isEmpty);
      expect(buildSegments([]), isEmpty);
    });

    test('the returned list cannot be mutated by a caller', () {
      final segments = buildSegments([_chunk('hola')]);

      expect(
        () => segments.add(const TranscriptSegment('injected')),
        throwsUnsupportedError,
      );
    });
  });

  group('where a segment sits', () {
    test(
      'a segment is positioned at its FIRST word, not the one that closed it',
      () {
        // At the cut the value in hand belongs to the segment being OPENED.
        // Recording it there stamps every segment with the start of the word that
        // ended the one before it.
        final segments = buildSegments([
          _chunk(
            'hola que tal muy bien',
            timings: [
              ('hola', 100, 300),
              ('que', 350, 600),
              ('tal', 620, 900),
              ('muy', 2300, 2600),
              ('bien', 2650, 2900),
            ],
          ),
        ]);

        expect(segments.map((s) => s.text), ['hola que tal', 'muy bien']);
        expect(segments.map((s) => s.atMs), [
          _chunkStart + 100,
          _chunkStart + 2300,
        ]);
      },
    );

    test('positioning changes neither the text nor the cut', () {
      // The same speech, once with a well-formed sequence and once with the
      // last word's end left out. The words and the boundary between them are
      // identical; only the claim to know WHEN differs.
      final positioned = buildSegments([
        _chunk(
          'hola que muy',
          timings: [('hola', 0, 300), ('que', 350, 600), ('muy', 2300, 2600)],
        ),
      ]);
      final unpositioned = buildSegments([
        _chunk(
          'hola que muy',
          timings: [('hola', 0, 300), ('que', 350, 600), ('muy', 2300, null)],
        ),
      ]);

      expect(positioned.map((s) => s.text), ['hola que', 'muy']);
      expect(
        unpositioned.map((s) => s.text),
        positioned.map((s) => s.text),
        reason: 'the cut is the same cut either way',
      );
      expect(positioned.map((s) => s.atMs), [_chunkStart, _chunkStart + 2300]);
      expect(unpositioned.map((s) => s.atMs), [null, null]);
    });

    test('a blank timing spanning a pause does not swallow it', () {
      // `hello` at 0-100, a blank at 100-3000 and `world` at 3000-3100 is a
      // perfectly ordered partition, so the positioning rule has nothing to say
      // about it. Measuring the pause from the previous TIMING made `world`'s
      // gap 3000 - 3000 = 0: no cut, and one segment stamped at 0 holding a
      // word spoken three seconds in.
      final segments = buildSegments([
        _chunk(
          'hello world',
          timings: [
            ('hello', 0, 100),
            ('   ', 100, 3000),
            ('world', 3000, 3100),
          ],
        ),
      ]);

      expect(segments.map((s) => s.text), ['hello', 'world']);
      expect(segments.map((s) => s.atMs), [_chunkStart, _chunkStart + 3000]);
    });

    test('no whole-chunk fallback is positioned', () {
      // Offset zero for a fallback is the CHUNK's position passed off as the
      // SPEECH's. A ninety-second chunk can open with silence, and interleaving
      // the other speaker against that would be confidently wrong.
      final none = buildSegments([_chunk('hola que tal')]);
      final blank = buildSegments([
        _chunk('texto real', timings: [('   ', 0, 100), ('', 200, 300)]),
      ]);
      // The one that proves this has to be its own rule rather than a
      // consequence of the sequence check: complete, ordered, in-range timings
      // that describe DIFFERENT WORDS than the transcript does.
      final substituted = buildSegments([
        _chunk(
          'pay bob today',
          timings: [('pay', 0, 200), ('alice', 250, 500), ('today', 550, 800)],
        ),
      ]);

      expect(none.single.text, 'hola que tal');
      expect(blank.single.text, 'texto real');
      expect(substituted.single.text, 'pay bob today');
      for (final fallback in [none, blank, substituted]) {
        expect(fallback.single.atMs, isNull);
      }
    });

    test('two speakers\' chunks interleave in the order they were spoken', () {
      // Each device cuts its OWN audio, so the only thing that puts the two
      // sides in order is the position on each segment.
      final alice = buildSegments([
        _chunk('hola', timings: [('hola', 0, 400)], startedAtMs: 1000),
        _chunk(
          'muy bien',
          timings: [('muy', 0, 300), ('bien', 350, 600)],
          startedAtMs: 9000,
        ),
      ]);
      final bob = buildSegments([
        _chunk(
          'que tal',
          timings: [('que', 0, 300), ('tal', 350, 600)],
          startedAtMs: 5000,
        ),
      ]);

      final turns = [...alice, ...bob]
        ..sort((a, b) => a.atMs!.compareTo(b.atMs!));
      expect(turns.map((s) => s.text), ['hola', 'que tal', 'muy bien']);
    });

    test('utterances inside ONE chunk interleave against the other speaker', () {
      // Both of Alice's utterances came from a single chunk. Positioning by the
      // chunk would stamp them the same and put Bob's reply after both.
      final alice = buildSegments([
        _chunk(
          'hola muy bien',
          timings: [
            ('hola', 0, 400),
            ('muy', 5000, 5300),
            ('bien', 5350, 5600),
          ],
          startedAtMs: 1000,
        ),
      ]);
      final bob = buildSegments([
        _chunk(
          'que tal',
          timings: [('que', 0, 300), ('tal', 350, 600)],
          startedAtMs: 3000,
        ),
      ]);

      final turns = [...alice, ...bob]
        ..sort((a, b) => a.atMs!.compareTo(b.atMs!));
      expect(turns.map((s) => s.text), ['hola', 'que tal', 'muy bien']);
    });
  });

  group('timings that are not a well-formed sequence', () {
    // Every one of these leaves the chunk unpositioned and the WORDS untouched.
    // Six review rounds each found one more shape the rule of the day did not
    // cover, which is why the rule now constrains the input completely rather
    // than describing it.
    final malformed = <String, List<(String, int?, int?)>>{
      'a missing start': [('hola', 0, 300), ('que', null, 600)],
      'a missing end': [('hola', 0, null), ('que', 350, 600)],
      'a start before the previous end': [('hola', 0, 300), ('que', 250, 600)],
      'an end before its own start': [('hola', 0, 300), ('que', 500, 400)],
      'words out of order': [('hola', 500, 600), ('que', 100, 200)],
      'a negative time': [('hola', -5, 300), ('que', 350, 600)],
      'an end past the chunk duration': [('hola', 0, 300), ('que', 350, 5000)],
      'a blank word missing a time': [
        ('hola', 0, 300),
        ('   ', 350, null),
        ('que', 400, 600),
      ],
    };

    malformed.forEach((what, timings) {
      test('$what leaves the chunk unpositioned, with its text intact', () {
        final text = timings
            .map((timing) => timing.$1)
            .where((word) => word.trim().isNotEmpty)
            .join(' ');
        final segments = buildSegments([
          _chunk(text, timings: timings, durationMs: 1000),
        ]);

        expect(segments.map((s) => s.text).join(' '), text);
        expect(segments.map((s) => s.atMs), everyElement(isNull));
      });
    });

    test('and the same words, well formed, ARE positioned', () {
      // The control. Without it every assertion above would still hold with
      // positioning removed altogether.
      final segments = buildSegments([
        _chunk(
          'hola que',
          timings: [('hola', 0, 300), ('que', 350, 600)],
          durationMs: 1000,
        ),
      ]);

      expect(segments.single.atMs, _chunkStart);
    });
  });

  group('TranscriptSegment json', () {
    test('round-trips', () {
      const segment = TranscriptSegment('hola que tal', atMs: 1700000000000);
      expect(TranscriptSegment.fromJson(segment.toJson()), segment);
    });

    test('carries one offset per segment and nothing per word', () {
      // What is persisted, spelled out. The timings that CHOSE these boundaries
      // are not stored, and a reader cannot recover a speaker's word rhythm
      // from what is.
      final segments = buildSegments([
        _chunk(
          'hola que tal muy bien',
          timings: [
            ('hola', 100, 300),
            ('que', 350, 600),
            ('tal', 620, 900),
            ('muy', 2300, 2600),
            ('bien', 2650, 2900),
          ],
        ),
      ]);

      expect(
        [for (final segment in segments) segment.toJson()],
        [
          {'text': 'hola que tal', 'at_ms': _chunkStart + 100},
          {'text': 'muy bien', 'at_ms': _chunkStart + 2300},
        ],
      );
    });

    test('rejects a malformed or empty entry rather than throwing', () {
      // Room content is untrusted: a bad entry is skipped, it does not take
      // the whole transcript view down with it.
      expect(TranscriptSegment.fromJson(null), isNull);
      expect(TranscriptSegment.fromJson('not a map'), isNull);
      expect(TranscriptSegment.fromJson({'text': 42}), isNull);
      expect(TranscriptSegment.fromJson({'text': '   '}), isNull);
      expect(TranscriptSegment.fromJson({}), isNull);
    });

    test('a bad position costs a position, never words', () {
      // Rejecting the segment would drop speech and mark the half shortened,
      // which is a reader-side lie about what the writer sent. Accepting a
      // loose number would let hostile content satisfy the render gate with a
      // fabricated position.
      final unusable = [
        {'text': 'hola', 'at_ms': 'soon'},
        {'text': 'hola', 'at_ms': -1},
        {'text': 'hola', 'at_ms': 1.5},
        {'text': 'hola', 'at_ms': TranscriptSegment.atMsCeiling},
        {'text': 'hola', 'at_ms': null},
        {'text': 'hola'},
      ];

      for (final raw in unusable) {
        final segment = TranscriptSegment.fromJson(raw);
        expect(segment, isNotNull, reason: '$raw must still carry its words');
        expect(segment!.text, 'hola');
        expect(segment.atMs, isNull, reason: '$raw is not a position');
      }
    });

    test('a sound position is kept', () {
      // The other side of the gate: it must not fire on what this writer sends.
      expect(TranscriptSegment.fromJson({'text': 'hola', 'at_ms': 0})?.atMs, 0);
      expect(
        TranscriptSegment.fromJson({
          'text': 'hola',
          'at_ms': TranscriptSegment.atMsCeiling - 1,
        })?.atMs,
        TranscriptSegment.atMsCeiling - 1,
      );
    });
  });
}
