import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/pangea/morphs/parts_of_speech_enum.dart';

void main() {
  group('PartOfSpeechEnum.isEligibleLemmaTag', () {
    test('excludes non-lemma UD categories regardless of case', () {
      const nonLemmaTags = [
        'punct',
        'PUNCT',
        'sym',
        'SYM',
        'space',
        'SPACE',
        'affix',
        'AFFIX',
        'x',
        'X',
      ];
      for (final tag in nonLemmaTags) {
        expect(
          PartOfSpeechEnum.isEligibleLemmaTag(tag),
          isFalse,
          reason: '$tag should never be eligible as a lemma category',
        );
      }
    });

    test('allows real word categories', () {
      for (final tag in ['noun', 'VERB', 'adj', 'PRON', 'det']) {
        expect(PartOfSpeechEnum.isEligibleLemmaTag(tag), isTrue);
      }
    });

    test('treats unrecognized tags as eligible', () {
      expect(PartOfSpeechEnum.isEligibleLemmaTag('Pres'), isTrue);
    });
  });

  group('PartOfSpeechEnum.isContentWord', () {
    test('a phrase entry counts as a content word (#9386)', () {
      expect(PartOfSpeechEnum.phrase.isContentWord, isTrue);
    });

    test('a construct tagged PHRASE resolves to it regardless of case', () {
      final construct = ConstructIdentifier(
        lemma: 'hace sol',
        type: ConstructTypeEnum.vocab,
        category: 'PHRASE',
      );
      expect(construct.isContentWord, isTrue);
    });
  });
}
