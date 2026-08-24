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

/// A response the provider answered with nothing readable in.
final _empty = SpeechToTextResponseModel.fromJson({'results': <dynamic>[]});

void main() {
  group('buildSegments', () {
    test('a chunk without word timings becomes one segment, not none', () {
      // The provider is documented as omitting timings, and they are never
      // fabricated. Dropping such a chunk would lose speech it did read.
      final segments = buildSegments([_response('hola que tal')]);

      expect(segments.map((s) => s.text), ['hola que tal']);
    });

    test('a pause longer than the threshold splits one chunk in two', () {
      final segments = buildSegments([
        _response(
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
        _response(
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
        _response('primero'),
        _response('segundo'),
        _response('tercero'),
      ]);

      expect(segments.map((s) => s.text), ['primero', 'segundo', 'tercero']);
    });

    test('a chunk the provider could not read is skipped, not emitted', () {
      final segments = buildSegments([
        _response('antes'),
        _empty,
        _response('despues'),
      ]);

      expect(segments.map((s) => s.text), ['antes', 'despues']);
    });

    test('a word with no start time cannot open a gap', () {
      // Timestamps are nullable per the model's own contract. A null start
      // must not be read as 0 and split the utterance there.
      final segments = buildSegments([
        _response(
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
        _response(
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
        _response('texto real', timings: [('   ', 0, 100), ('', 200, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['texto real']);
    });

    test('a LATER chunk with all-blank timings still falls back', () {
      // The fallback used to ask whether any segment existed at all, so a
      // blank-timing chunk was dropped whenever an earlier chunk had produced
      // something -- losing speech, and only in calls long enough to have a
      // second chunk.
      final segments = buildSegments([
        _response('antes'),
        _response('texto real', timings: [('   ', 0, 100), ('', 200, 300)]),
      ]);

      expect(segments.map((s) => s.text), ['antes', 'texto real']);
    });

    test('timings covering only part of the text lose to the full text', () {
      // "hello world" timed as ["hello"] must not become "hello". A partial
      // timing list is not a finer cut of the text, it is an incomplete one.
      final segments = buildSegments([
        _response('hello world', timings: [('hello', 0, 100)]),
      ]);

      expect(segments.map((s) => s.text), ['hello world']);
    });

    test('timings covering the text are still preferred', () {
      // The coverage floor must not fire on ordinary input, or word timings
      // would never be used and every chunk would be one wall of text.
      final segments = buildSegments([
        _response(
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
        _response(
          'supercalifragilisticexpialidocious bye',
          timings: [('supercalifragilisticexpialidocious', 0, 900)],
        ),
      ]);

      expect(segments.map((s) => s.text), [
        'supercalifragilisticexpialidocious bye',
      ]);
    });

    test('no usable chunks yields no segments', () {
      expect(buildSegments([_empty]), isEmpty);
      expect(buildSegments([]), isEmpty);
    });

    test('the returned list cannot be mutated by a caller', () {
      final segments = buildSegments([_response('hola')]);

      expect(
        () => segments.add(const TranscriptSegment('injected')),
        throwsUnsupportedError,
      );
    });
  });

  group('TranscriptSegment json', () {
    test('round-trips', () {
      const segment = TranscriptSegment('hola que tal');
      expect(TranscriptSegment.fromJson(segment.toJson()), segment);
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
  });
}
