import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_disambiguation.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';

// Unit tests for heteronym disambiguation against UD context.
// Design: client/.github/instructions/phonetic-transcription-v2-design.instructions.md §3

const hai = Pronunciation(
  transcription: 'hái',
  ttsPhoneme: 'hai2',
  udConditions: 'Pos=ADV',
);
const huan = Pronunciation(
  transcription: 'huán',
  ttsPhoneme: 'huan2',
  udConditions: 'Pos=VERB',
);

void main() {
  group('disambiguate', () {
    test('single pronunciation always matches', () {
      final result = disambiguate([hai]);
      expect(result.matched, hai);
      expect(result.isAmbiguous, isFalse);
    });

    test('POS picks exactly one of two readings', () {
      expect(disambiguate([hai, huan], pos: 'ADV').matched, hai);
      expect(disambiguate([hai, huan], pos: 'VERB').matched, huan);
    });

    test('POS comparison is case-insensitive', () {
      expect(disambiguate([hai, huan], pos: 'verb').matched, huan);
    });

    test('no context leaves a heteronym ambiguous', () {
      final result = disambiguate([hai, huan]);
      expect(result.matched, isNull);
      expect(result.isAmbiguous, isTrue);
      expect(result.displayTranscription, 'hái / huán');
      expect(result.ttsPhoneme, isNull);
    });

    test('morph features must all hold', () {
      const past = Pronunciation(
        transcription: 'red',
        ttsPhoneme: 'rɛd',
        udConditions: 'Pos=VERB;Tense=Past',
      );
      const pres = Pronunciation(
        transcription: 'reed',
        ttsPhoneme: 'riːd',
        udConditions: 'Pos=VERB;Tense=Pres',
      );
      final result = disambiguate(
        [past, pres],
        pos: 'VERB',
        morph: {'Tense': 'Past'},
      );
      expect(result.matched, past);
    });

    test('unconditional row is the default among conditional ones', () {
      const base = Pronunciation(transcription: 'bù', ttsPhoneme: 'bu4');
      const special = Pronunciation(
        transcription: 'bú',
        ttsPhoneme: 'bu2',
        udConditions: 'Pos=X',
      );
      final result = disambiguate([base, special], pos: 'ADV');
      expect(result.matched, base);
    });

    group('fails closed on conditions it cannot parse (#8076)', () {
      // The old parser skipped any fragment it couldn't split on one '=',
      // which made the whole row match every context — two rows then both
      // "matched" and disambiguation always gave up.
      test('pipe-joined alternatives do not match everything', () {
        const orRow = Pronunciation(
          transcription: 'tiáo',
          ttsPhoneme: 'tiao2',
          udConditions: 'Pos=NOUN|Pos=VERB',
        );
        const plain = Pronunciation(
          transcription: 'tiāo',
          ttsPhoneme: 'tiao1',
          udConditions: 'Pos=VERB',
        );
        final result = disambiguate([orRow, plain], pos: 'VERB');
        expect(result.matched, plain);
      });

      test('an IPA string leaked into the conditions never matches', () {
        const leaked = Pronunciation(
          transcription: 'why',
          ttsPhoneme: 'waɪ',
          udConditions: 'hwʌɪ',
        );
        final result = disambiguate([leaked, hai], pos: 'ADV');
        expect(result.matched, hai);
      });

      test('unparseable fragment fails its whole row', () {
        const broken = Pronunciation(
          transcription: 'yí',
          ttsPhoneme: 'yi2',
          udConditions: 'Pos=NUM;Before1;2;3',
        );
        final result = disambiguate([broken], pos: 'NUM');
        // Single row still matches (nothing to disambiguate), but in a
        // multi-row set the broken row must not win by matching everything.
        expect(result.matched, broken);
        const clean = Pronunciation(
          transcription: 'yī',
          ttsPhoneme: 'yi1',
          udConditions: 'Pos=NUM',
        );
        final multi = disambiguate([broken, clean], pos: 'NUM');
        expect(multi.matched, clean);
      });
    });
  });
}
