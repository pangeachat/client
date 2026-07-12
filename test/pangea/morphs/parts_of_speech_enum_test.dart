import 'package:flutter_test/flutter_test.dart';

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
}
