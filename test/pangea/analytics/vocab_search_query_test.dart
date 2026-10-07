import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/analytics/construct_analytics/vocab_search_match.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_search_query.dart';

/// Vocab search matches a word or a meaning the learner already has for it
/// (#9042). A word's own text always outranks a meaning match.
void main() {
  group('matching', () {
    test('matches the lemma ignoring case and diacritics', () {
      final query = VocabSearchQuery('CAFE');
      expect(query.matchLemma('café'), isNotNull);
    });

    test('matches a meaning ignoring case and diacritics', () {
      final query = VocabSearchQuery('Cafe');
      expect(query.matchMeanings(['the café']), isNotNull);
    });

    test('matches any of several meanings', () {
      final query = VocabSearchQuery('greeting');
      expect(query.matchMeanings(['hello', 'a greeting']), isNotNull);
    });

    test('misses when neither lemma nor meaning contains the text', () {
      final query = VocabSearchQuery('hello');
      expect(query.matchLemma('bonjour'), isNull);
      expect(query.matchMeanings(['good day']), isNull);
      expect(query.matchMeanings(const []), isNull);
    });

    test('ignores surrounding whitespace in the search text', () {
      expect(VocabSearchQuery(' hello ').matchMeanings(['hello']), isNotNull);
    });

    test('whitespace-only text is empty', () {
      expect(VocabSearchQuery('   ').isEmpty, isTrue);
      expect(VocabSearchQuery('a').isEmpty, isFalse);
    });
  });

  group('ranking', () {
    final query = VocabSearchQuery('bon');
    VocabSearchMatch lemma(String text) => query.matchLemma(text)!;
    VocabSearchMatch meaning(String text) => query.matchMeanings([text])!;

    test('an exact lemma ranks above a lemma that starts with the text', () {
      expect(lemma('bon').compareTo(lemma('bonjour')), lessThan(0));
    });

    test('lemma matches rank by how early the text appears', () {
      expect(lemma('bonjour').compareTo(lemma('abonner')), lessThan(0));
    });

    test('any lemma match ranks above any meaning match', () {
      expect(lemma('abonner').compareTo(meaning('bon')), lessThan(0));
    });

    test('meaning matches rank by how early the text appears', () {
      expect(meaning('bonus').compareTo(meaning('a bonus')), lessThan(0));
    });

    test('a word ranks by its best meaning', () {
      expect(
        query.matchMeanings(['a bonus', 'bonus'])!.compareTo(meaning('bonus')),
        0,
      );
    });
  });
}
