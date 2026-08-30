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
      // Asserting the text alone let the real regression through: the chunk
      // could be ACCEPTED and cut at a word the transcript never contained.
      // Refused, it is ONE segment carrying the chunk's own start -- coarse,
      // not absent, so the rest of the call still draws.
      expect(segments, hasLength(1));
      expect(segments.single.atMs, _chunkStart);
    });

    test('a symbol that changes a word is not stripped away', () {
      final segments = buildSegments([
        _chunk('C++ rocks', timings: [('C', 0, 100), ('rocks', 150, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['C++ rocks']);
      expect(segments, hasLength(1));
      expect(segments.single.atMs, _chunkStart);
    });

    test('a word-forming mark is kept whatever Unicode calls it', () {
      // `#` is Unicode punctuation, so every category-based rule accepted
      // "C#" as "C". It is part of the WORD, not decoration the transcript put
      // around it, which is why membership is an explicit set rather than a
      // category. Same defect class as C++ and he'll, found a round later.
      for (final word in ['C#', r'C$', 'C%', 'C&', 'C@', 'C_', 'C*', 'C/']) {
        final segments = buildSegments([
          _chunk('$word rocks', timings: [('C', 0, 100), ('rocks', 150, 300)]),
        ]);

        expect(segments.map((s) => s.text), [
          '$word rocks',
        ], reason: '$word must not align with C');
        expect(
          segments,
          hasLength(1),
          reason: '$word aligned with C and was cut at its words',
        );
        expect(segments.single.atMs, _chunkStart);
      }
    });

    test('an apostrophe at the EDGE is the same word, and aligns', () {
      // Deliberate, and the distinction this file turns on. An apostrophe at a
      // word's edge is elision, possession or a quote mark: "'em" is "em",
      // "dogs'" is "dogs". The same character INSIDE a word forms a different
      // one -- "he'll" is not "hell" -- and that case is refused above.
      //
      // Dropping edge apostrophes from the set would refuse every quoted or
      // elided word and send those calls to the per-speaker view, to prevent a
      // substitution that cannot be constructed: X' and X are always the same
      // lexeme.
      for (final (text, first) in [
        ("'em go", 'em'),
        ("'til then", 'til'),
        ("dogs' bark", 'dogs'),
      ]) {
        final second = text.split(' ')[1];
        final segments = buildSegments([
          _chunk(text, timings: [(first, 0, 100), (second, 150, 300)]),
        ]);

        expect(segments.single.text, text);
        expect(
          segments.single.atMs,
          _chunkStart,
          reason: '$text should align: the edge mark does not change the word',
        );
      }
    });

    test('sentence marks from other scripts are forgiven at the edges', () {
      // The set has to cover the scripts learners actually speak, not just
      // Latin. These are the shapes the captures on disk contain.
      for (final (text, first, second) in [
        ('¿Cómo estás?', 'cómo', 'estás'),
        ('داخليًا، نعم', 'داخليًا', 'نعم'),
        ('नमस्ते। हाँ', 'नमस्ते', 'हाँ'),
      ]) {
        final segments = buildSegments([
          _chunk(text, timings: [(first, 0, 100), (second, 150, 300)]),
        ]);

        expect(
          segments.single.atMs,
          _chunkStart,
          reason: '$text should align and carry a position',
        );
        expect(segments.single.text, text);
      }
    });

    test('a script without word spacing falls back, and is not faked', () {
      // KNOWN LIMITATION, asserted so it is visible rather than discovered.
      // Alignment pairs the provider's words with the transcript's
      // WHITESPACE-separated ones, and Chinese and Japanese do not separate
      // words that way: "你好。是" is one token against two provider words, so
      // the counts never match and the chunk falls back to the per-speaker
      // view. Splitting CJK on sentence marks instead would be a different
      // design; guessing at boundaries to fill the gap would put words in a
      // learner's mouth, which is the one thing this file never does.
      final segments = buildSegments([
        _chunk('你好。是', timings: [('你好', 0, 100), ('是', 150, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['你好。是']);
      expect(segments, hasLength(1));
      expect(segments.single.atMs, _chunkStart);
    });

    test('case alone does not trigger the fallback', () {
      final segments = buildSegments([
        _chunk(
          'Hola que tal',
          timings: [('hola', 0, 200), ('QUE', 250, 500), ('tal', 550, 800)],
        ),
      ]);

      expect(segments, hasLength(1));
      // The TRANSCRIPT's casing, not the provider word list's. The words are
      // the same words; only their spelling differs, and the transcript is the
      // authoritative rendering of what was said.
      expect(segments.single.text, 'Hola que tal');
    });

    test('punctuation the timings omit no longer costs the position', () {
      // This is the case that kept every real call unpositioned: providers
      // return a punctuation-free word list beside a punctuated transcript, so
      // the old exact rule refused 14 of 14 captured chunks, and one refused
      // chunk drops the whole call to the per-speaker view.
      //
      // Forgiving punctuation at the EDGES of a word is what makes this safe
      // without reopening the substitution hole: "he'll" and "C++" differ
      // INSIDE the word and are still refused, as the two tests above assert.
      final segments = buildSegments([
        _chunk(
          'Hola, que tal?',
          timings: [('Hola', 0, 200), ('que', 250, 500), ('tal', 550, 800)],
        ),
      ]);

      expect(segments.map((s) => s.text), ['Hola, que tal?']);
      expect(
        segments.single.atMs,
        _chunkStart,
        reason: 'the chunk aligns, so it must carry a position',
      );
    });

    test('the punctuation a learner reads comes from the transcript', () {
      // Real shape, from a capture on disk: Deepgram is asked for smart_format
      // + punctuate, so its transcript is punctuated while its word list is
      // not. Assembling display text from the word list could never show the
      // punctuation; taking it from the transcript does.
      final segments = buildSegments([
        _chunk(
          'Hello, how are you?',
          timings: [
            ('hello', 0, 100),
            ('how', 2000, 2100),
            ('are', 2150, 2250),
            ('you', 2300, 2400),
          ],
        ),
      ]);

      expect(segments.map((s) => s.text), ['Hello,', 'how are you?']);
      expect(segments.first.atMs, _chunkStart);
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
      // Both segments now sit at the chunk's own start: the cut is the same,
      // and the claim narrows from "at this word" to "during this chunk"
      // rather than vanishing.
      expect(unpositioned.map((s) => s.atMs), [_chunkStart, _chunkStart]);
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
        expect(fallback.single.atMs, _chunkStart);
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
      // Inside the jitter allowance measured against the previous END, and
      // still backwards: the second word BEGINS before the first one did.
      // That is not two estimates disagreeing about a boundary, it is the
      // sequence saying the later word was spoken first -- and it used to be
      // accepted AND reported as an exact time, so the interleave could put
      // the other speaker in the middle of a phrase.
      'a start before the previous START, within the jitter': [
        ('hola', 100, 120),
        ('que', 90, 130),
      ],
      'a negative time': [('hola', -5, 300), ('que', 350, 600)],
      'an end past the chunk duration': [('hola', 0, 300), ('que', 350, 5000)],
      'a blank word missing a time': [
        ('hola', 0, 300),
        ('   ', 350, null),
        ('que', 400, 600),
      ],
    };

    malformed.forEach((what, timings) {
      test('$what costs the chunk its precision, not its text', () {
        final text = timings
            .map((timing) => timing.$1)
            .where((word) => word.trim().isNotEmpty)
            .join(' ');
        final segments = buildSegments([
          _chunk(text, timings: timings, durationMs: 1000),
        ]);

        expect(segments.map((s) => s.text).join(' '), text);

        // Never null: one mangled chunk must not hide the good turns around
        // it. And never merely the chunk's start either, when the timings
        // still say when speech began -- a chunk runs to 45 seconds, so a
        // segment parked at the chunk's start can sort a whole chunk ahead of
        // the other speaker's correctly placed turns. Refusing a word list is
        // a judgement about WORDS; the earliest start is a separate claim and
        // survives it.
        // The earliest moment the chunk has ANY evidence of speech, from
        // either end of any word, bounded to the chunk's own length. Starts
        // alone read a word whose start was omitted as no evidence, which put
        // the segment after that word had already finished. Later than the
        // first listed is the misordering this guards against; outside the
        // chunk is a claim about audio that does not exist.
        final marks = timings
            .where((t) => t.$1.trim().isNotEmpty)
            .expand((t) => [t.$2, t.$3])
            .whereType<int>()
            .where((v) => v >= 0 && v <= 1000);
        final firstStart = marks.isEmpty
            ? null
            : marks.reduce((a, b) => a < b ? a : b);
        expect(
          segments.map((s) => s.atMs),
          everyElement(_chunkStart + (firstStart ?? 0)),
          reason:
              '$what should sit where speech began, not where the chunk did',
        );
      });
    });

    test('an omitted start still uses the word its END proves', () {
      // Taking only starts answered 350 here, which is AFTER hola finished at
      // 300. An end is evidence sound existed just as much as a start is.
      final segments = buildSegments([
        _chunk(
          'hola que',
          timings: [('hola', null, 300), ('que', 350, 600)],
          durationMs: 1000,
        ),
      ]);

      expect(segments.map((s) => s.atMs), everyElement(_chunkStart + 300));
    });

    test('a time past the chunk is not evidence of anything', () {
      // _isWellFormedSequence already rejects out-of-chunk timings; the
      // fallback must not then adopt one and place the turn after the audio it
      // describes has ended.
      final segments = buildSegments([
        _chunk(
          'hola que',
          timings: [('hola', 5000, 6000), ('que', 400, 700)],
          durationMs: 1000,
        ),
      ]);

      expect(segments.map((s) => s.atMs), everyElement(_chunkStart + 400));
    });

    test('a few ms of boundary jitter does NOT cost the chunk its cut', () {
      // From a real two-person call: 44 words, ONE overlap of 20ms, and the
      // whole chunk was refused. Every segment then shared one timestamp, so
      // three of that speaker's sentences collapsed onto a single moment and
      // the conversation read out of order against the other speaker.
      final segments = buildSegments([
        _chunk(
          'hola que tal',
          timings: [
            ('hola', 0, 300),
            ('que', 280, 600), // starts 20ms before 'hola' ended
            ('tal', 2000, 2400),
          ],
          durationMs: 3000,
        ),
      ]);

      expect(segments.map((s) => s.text), ['hola que', 'tal']);
      expect(
        segments.map((s) => s.atMs),
        [_chunkStart, _chunkStart + 2000],
        reason: 'jitter must not collapse the chunk onto one moment',
      );
    });

    test('an overlap too large to be jitter still refuses the chunk', () {
      // The guard this tolerance must not dissolve: a word claiming a moment
      // well before the previous one ended is disorder, not measurement noise.
      final segments = buildSegments([
        _chunk(
          'hola que tal',
          timings: [
            ('hola', 0, 2000),
            ('que', 500, 2200), // 1500ms early: real disorder
            ('tal', 2300, 2400),
          ],
          durationMs: 3000,
        ),
      ]);

      expect(
        segments.map((s) => s.atMs).toSet().length,
        1,
        reason: 'a disordered sequence still falls back to one moment',
      );
    });

    test('tolerated overlaps do not accumulate backwards', () {
      // Ten words each 40ms early must not walk the sequence half a second
      // back. The scan reads forward from the later of the two ends.
      final timings = <(String, int?, int?)>[];
      for (var i = 0; i < 10; i++) {
        timings.add(('w$i', i * 100 - 40, i * 100 + 100));
      }
      final segments = buildSegments([
        _chunk(
          List.generate(10, (i) => 'w$i').join(' '),
          timings: [('w0', 0, 100), ...timings.skip(1)],
          durationMs: 3000,
        ),
      ]);

      expect(segments.single.atMs, _chunkStart);
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

  group('how tightly a position is known', () {
    // A chunk short enough that its end is a distinctive number, so an
    // assertion names the window rather than a coincidence.
    const durationMs = 45000;
    const chunkEnd = _chunkStart + durationMs;

    test('a chunk cut by trusted timings claims a WORD, and says so', () {
      // The control for everything below. Without it every assertion in this
      // group would still hold with the exactness claim removed altogether.
      final segments = buildSegments([
        _chunk(
          'hola que',
          timings: [('hola', 0, 300), ('que', 350, 600)],
          durationMs: durationMs,
        ),
      ]);

      expect(segments.single.spanMs, isNull);
      expect(segments.single.positionIsApproximate, isFalse);
      expect(segments.single.orderKeyMs, _chunkStart);
    });

    // Every route by which a chunk fails to be cut word by word. Each one used
    // to stamp a position indistinguishable from the one above.
    final coarse = <String, TranscribedChunk>{
      'no timings at all': _chunk('hola que tal', durationMs: durationMs),
      'a word list that does not match its transcript': _chunk(
        'pay bob today',
        timings: [('pay', 0, 200), ('alice', 250, 500), ('today', 550, 800)],
        durationMs: durationMs,
      ),
      'timings that are not a well-formed sequence': _chunk(
        'hola que',
        timings: [('hola', 0, 300), ('que', null, 600)],
        durationMs: durationMs,
      ),
      'timings that are all blank': _chunk(
        'texto real',
        timings: [('   ', 0, 100), ('', 200, 300)],
        durationMs: durationMs,
      ),
    };

    coarse.forEach((what, chunk) {
      test('$what is bounded to the chunk it came from', () {
        final segments = buildSegments([chunk]);

        expect(segments, isNotEmpty, reason: 'the words must still be here');
        for (final segment in segments) {
          expect(
            segment.positionIsApproximate,
            isTrue,
            reason: '$what cannot know which word it was',
          );
          // The END of the chunk's audio, whatever the estimate inside it was.
          // That bound is the only thing here that is PROVEN: no word in a
          // chunk began after its audio stopped.
          expect(segment.orderKeyMs, chunkEnd, reason: what);
          expect(
            segment.atMs! + segment.spanMs!,
            chunkEnd,
            reason: 'the span runs from the estimate to the proven end',
          );
        }
      });
    });

    test('every segment of one malformed chunk shares its window', () {
      // The shape of the real failure: three sentences cut from a chunk whose
      // timings were refused. They share a moment, and they must share the
      // BOUND as well -- an order key that differed between them would sort
      // one of the speaker's own sentences against the other on nothing.
      final segments = buildSegments([
        _chunk(
          'hola que tal',
          timings: [('hola', 500, 600), ('que', 100, 200), ('tal', 700, 800)],
          durationMs: durationMs,
        ),
      ]);

      expect(segments.length, greaterThan(0));
      expect(segments.map((s) => s.orderKeyMs).toSet(), {chunkEnd});
    });

    test('a chunk keeps the ESTIMATE it always had, alongside the bound', () {
      // The span is added beside `atMs`, not in place of it. A reader that
      // knows nothing about spans still gets the earliest evidence of speech
      // rather than the chunk's start, which is what that estimate was for.
      final segments = buildSegments([
        _chunk(
          'hola que',
          timings: [('hola', 5000, 6000), ('que', 400, 700)],
          durationMs: durationMs,
        ),
      ]);

      expect(segments.single.atMs, _chunkStart + 400);
      expect(segments.single.orderKeyMs, chunkEnd);
    });

    test('positions and their bounds both run forwards across chunks', () {
      // What `segmentsArePlaceable` is entitled to assume of this writer. A
      // chunk's window ends before the next chunk's begins, so neither the
      // estimates nor the moments they are placed at can go backwards -- and a
      // half whose own turns rendered out of order is the failure that rule
      // exists to refuse.
      final segments = buildSegments([
        _chunk('primero', durationMs: 10000, startedAtMs: 1000),
        _chunk(
          'segundo',
          timings: [('segundo', 100, 400)],
          durationMs: 10000,
          startedAtMs: 11000,
        ),
        _chunk('tercero', durationMs: 10000, startedAtMs: 21000),
      ]);

      final ats = [for (final s in segments) s.atMs!];
      final keys = [for (final s in segments) s.orderKeyMs!];
      expect(ats, orderedEquals([...ats]..sort()));
      expect(keys, orderedEquals([...keys]..sort()));
    });
  });

  group('TranscriptSegment json', () {
    test('round-trips', () {
      const segment = TranscriptSegment('hola que tal', atMs: 1700000000000);
      expect(TranscriptSegment.fromJson(segment.toJson()), segment);
    });

    test('a bounded position round-trips, span and all', () {
      const segment = TranscriptSegment(
        'hola que tal',
        atMs: 1700000000000,
        spanMs: 45000,
      );
      final parsed = TranscriptSegment.fromJson(segment.toJson())!;

      expect(parsed, segment);
      expect(parsed.spanMs, 45000);
      expect(parsed.positionIsApproximate, isTrue);
    });

    test('a span of ZERO still marks the position as bounded', () {
      // Presence is the marker, not a positive value. A chunk whose audio
      // window collapsed to an instant, and an estimate landing on its own
      // chunk's end, both produce zero -- and neither can support the claim
      // that its first word was spoken exactly then.
      const segment = TranscriptSegment('hola', atMs: 1700000000000, spanMs: 0);
      final json = segment.toJson();

      expect(json['at_span_ms'], 0);
      expect(TranscriptSegment.fromJson(json)!.positionIsApproximate, isTrue);
    });

    test('an EXACT segment writes no span at all', () {
      // The other side of it, and what keeps the wire cost on the segments
      // that need it. A key on every segment would be paid by every call.
      const segment = TranscriptSegment('hola', atMs: 1700000000000);
      expect(segment.toJson().containsKey('at_span_ms'), isFalse);
      expect(TranscriptSegment.fromJson(segment.toJson())!.spanMs, isNull);
    });

    test('a segment written before spans existed reads as exact', () {
      final parsed = TranscriptSegment.fromJson({
        'text': 'hola',
        'at_ms': 1700000000000,
      })!;

      expect(parsed.spanMs, isNull);
      expect(parsed.positionIsApproximate, isFalse);
    });

    test('a bad span costs neither the words NOR the position', () {
      // Deliberately unlike a bad `at_ms`, which costs the position. Whether a
      // span is honoured is a question about this segment; what an unusable one
      // MEANS is a question about the half's claim, and destroying a sound
      // position over the second would drop a whole call to the per-speaker
      // view for one corrupt byte. `CallTranscriptContent` takes the half's
      // claim away instead.
      final unusable = [
        {'text': 'hola', 'at_ms': 1000, 'at_span_ms': 'soon'},
        {'text': 'hola', 'at_ms': 1000, 'at_span_ms': -1},
        {'text': 'hola', 'at_ms': 1000, 'at_span_ms': 1.5},
        {'text': 'hola', 'at_ms': 1000, 'at_span_ms': null},
        {
          'text': 'hola',
          'at_ms': 1000,
          'at_span_ms': TranscriptSegment.atMsCeiling,
        },
      ];

      for (final raw in unusable) {
        final segment = TranscriptSegment.fromJson(raw)!;
        expect(segment.text, 'hola', reason: '$raw must keep its words');
        expect(segment.atMs, 1000, reason: '$raw must keep its position');
        expect(segment.spanMs, isNull, reason: '$raw is not a bound');
        expect(
          TranscriptSegment.spanOf(raw, 1000).declaredButUnusable,
          isTrue,
          reason: '$raw declared a span and must be reported as such',
        );
      }
    });

    test('a span beside an unusable position is neither honoured nor held '
        'against the half', () {
      // There is no position for it to bound, and the segment is already
      // unplaceable on its own account. Counting it against the half would
      // punish a writer for a field that could not have meant anything.
      const raw = {'text': 'hola', 'at_ms': 'soon', 'at_span_ms': 500};

      expect(TranscriptSegment.fromJson(raw)!.atMs, isNull);
      expect(TranscriptSegment.spanOf(raw, null).declaredButUnusable, isFalse);
    });

    test('a sound span is honoured', () {
      // The gate must not fire on what this writer sends.
      expect(TranscriptSegment.spanOf({'at_span_ms': 0}, 1000).spanMs, 0);
      expect(
        TranscriptSegment.spanOf({'at_span_ms': 45000}, 1000).spanMs,
        45000,
      );
      expect(TranscriptSegment.spanOf({}, 1000).spanMs, isNull);
      expect(TranscriptSegment.spanOf({}, 1000).declaredButUnusable, isFalse);
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
