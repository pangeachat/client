import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/streaming_stt/streamed_stt_embed.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_partial_model.dart';
import 'package:fluffychat/routes/chat/events/streaming_stt/stt_provenance.dart';

void main() {
  group('sttEditDistance (Levenshtein, grapheme-level)', () {
    test('identical strings -> 0', () {
      expect(sttEditDistance('hola mundo', 'hola mundo'), 0);
      expect(sttEditDistance('', ''), 0);
    });

    test('empty vs non-empty -> length of the non-empty', () {
      expect(sttEditDistance('', 'abc'), 3);
      expect(sttEditDistance('abc', ''), 3);
    });

    test('single substitution -> 1', () {
      // Teeth: a no-op distance (always 0) makes this RED.
      expect(sttEditDistance('cat', 'car'), 1);
    });

    test('single insertion -> 1, single deletion -> 1', () {
      expect(sttEditDistance('car', 'cart'), 1);
      expect(sttEditDistance('cart', 'car'), 1);
    });

    test('symmetric', () {
      expect(
        sttEditDistance('kitten', 'sitting'),
        sttEditDistance('sitting', 'kitten'),
      );
      // The classic kitten<->sitting distance is 3.
      expect(sttEditDistance('kitten', 'sitting'), 3);
    });

    test('unicode: an accented char is ONE substitution, not several', () {
      // Precomposed é vs e: one grapheme substitution.
      expect(sttEditDistance('café', 'cafe'), 1);
      // Decomposed e + combining acute is one grapheme cluster, so "é"(decomposed)
      // vs "e" is still ONE edit at grapheme granularity (UTF-16 code-unit
      // counting would wrongly report 1 deletion of the combining mark here, but
      // grapheme counting keeps it a single substitution against 'e').
      expect(sttEditDistance('é', 'e'), 1);
      // A single emoji swap is ONE edit, not several (it spans two UTF-16 units).
      expect(sttEditDistance('👍', '👎'), 1);
      expect(sttEditDistance('👍', '👍'), 0);
    });
  });

  group('sttTranscriptEditedFromUserStt (D9 reader, fails closed)', () {
    test('edited == true -> true', () {
      expect(
        sttTranscriptEditedFromUserStt({SttProvenanceKeys.edited: true}),
        isTrue,
      );
    });

    test('edited == false -> false', () {
      expect(
        sttTranscriptEditedFromUserStt({SttProvenanceKeys.edited: false}),
        isFalse,
      );
    });

    test('missing key -> false (verbatim)', () {
      expect(sttTranscriptEditedFromUserStt({'results': <dynamic>[]}), isFalse);
    });

    test('null map -> false', () {
      expect(sttTranscriptEditedFromUserStt(null), isFalse);
    });

    test('the STRING "true" -> false (only a real bool true reads edited)', () {
      // Teeth: a loose truthiness check would flip this RED.
      expect(
        sttTranscriptEditedFromUserStt({SttProvenanceKeys.edited: 'true'}),
        isFalse,
      );
    });
  });

  group('StreamingSttSendData', () {
    test('verbatim send: isEdited false, editDistance 0, keys carried', () {
      const data = StreamingSttSendData(
        text: 'hola mundo',
        originalAsrText: 'hola mundo',
        isEdited: false,
        editDistance: 0,
        words: <SttWord>[],
        service: 'deepgram',
        langCode: 'en',
      );
      final keys = data.toProvenanceKeys();
      expect(keys[SttProvenanceKeys.edited], isFalse);
      expect(keys[SttProvenanceKeys.editDistance], 0);
      expect(keys[SttProvenanceKeys.originalAsr], 'hola mundo');
    });

    test('edited send: provenance keys reflect the edit + original ASR', () {
      const data = StreamingSttSendData(
        text: 'hola mundo!',
        originalAsrText: 'ola mundo',
        isEdited: true,
        editDistance: 2,
        words: <SttWord>[],
        service: 'deepgram',
        langCode: 'en',
      );
      final keys = data.toProvenanceKeys();
      expect(keys[SttProvenanceKeys.edited], isTrue);
      expect(keys[SttProvenanceKeys.editDistance], 2);
      expect(keys[SttProvenanceKeys.originalAsr], 'ola mundo');
    });
  });

  group('sttOriginalAsrFromUserStt', () {
    test('returns the original_asr string when present', () {
      expect(
        sttOriginalAsrFromUserStt({SttProvenanceKeys.originalAsr: 'hola'}),
        'hola',
      );
    });
    test('null map / missing key / non-string -> null', () {
      expect(sttOriginalAsrFromUserStt(null), isNull);
      expect(sttOriginalAsrFromUserStt({'x': 1}), isNull);
      expect(
        sttOriginalAsrFromUserStt({SttProvenanceKeys.originalAsr: 5}),
        isNull,
      );
    });
  });

  group('sttDiffPairFromUserStt', () {
    Map<String, dynamic> embed(StreamingSttSendData d) =>
        streamedUserSttEmbed(d, langCode: 'en');

    test(
      'edited send -> (original ASR, sent text) pair from the real embed',
      () {
        final pair = sttDiffPairFromUserStt(
          embed(
            const StreamingSttSendData(
              text: 'hola mundo',
              originalAsrText: 'ola mundo',
              isEdited: true,
              editDistance: 1,
              words: <SttWord>[],
              service: 'deepgram',
              langCode: 'en',
            ),
          ),
        );
        expect(pair, isNotNull);
        expect(pair!.originalAsr, 'ola mundo');
        expect(pair.current, 'hola mundo');
      },
    );

    test('verbatim send (edited == false) -> null (no diff to show)', () {
      final pair = sttDiffPairFromUserStt(
        embed(
          const StreamingSttSendData(
            text: 'hola mundo',
            originalAsrText: 'hola mundo',
            isEdited: false,
            editDistance: 0,
            words: <SttWord>[],
            service: 'deepgram',
            langCode: 'en',
          ),
        ),
      );
      expect(pair, isNull);
    });

    test('edited but original_asr missing -> null (fails closed)', () {
      expect(
        sttDiffPairFromUserStt({SttProvenanceKeys.edited: true, 'results': []}),
        isNull,
      );
    });
  });
}
