import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';

// Unit tests for the phrase gate that keeps whole sentences out of the
// phonetic-transcription endpoint (#8077). PT is specified for isolated
// words only — design doc §5. The example inputs are real surfaces observed
// in the staging pt-v2 cache.

void main() {
  group('isPhraseSurface', () {
    test('single words are not phrases', () {
      for (final word in ['还', '学习', 'lluvia', 'read', "l'art", 'なか']) {
        expect(isPhraseSurface(word), isFalse, reason: word);
      }
    });

    test('short multi-word tokens stay eligible (phrasal verbs, idioms)', () {
      expect(isPhraseSurface('give up'), isFalse);
      expect(isPhraseSurface('à + le'), isFalse);
    });

    test('sentence punctuation marks a phrase', () {
      expect(isPhraseSurface('Ciao, bot!'), isTrue);
      expect(isPhraseSurface("Qu'est-ce que tu étudies ?"), isTrue);
      expect(isPhraseSurface('你好！你今天好吗？'), isTrue);
      expect(isPhraseSurface('こんにちは、元気です。'), isTrue);
      expect(isPhraseSurface('Sì, mi piace la mia cucina.'), isTrue);
    });

    test('long word runs are phrases even without punctuation', () {
      expect(
        isPhraseSurface('Zeker ava huisgenoot gezamenlijk afspraak'),
        isTrue,
      );
    });
  });
}
