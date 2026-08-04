import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/default_grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';

/// Regression coverage for pangeachat/2-step-choreographer#2931.
///
/// The offline fallback bundle is English-targeted (`target_language: "en"`).
/// Its `display` flags describe which constructs manifest *in English* and
/// carry no information about any other L2. Applying them to a Russian
/// learner hid `Case=Ins` — instrumental case — from every surface that
/// reads the fallback, even though the token carried `Case=Ins` and the
/// server's `ru` bundle marks it `display: true`.
///
/// Also pins the fallback inventory to the post-#2873 master: the invented
/// (feature, value) pairs purged server-side must not survive here, or the
/// unfiltered mismatch path would resurface the #2357 duplicates.
void main() {
  setUp(MorphFeaturesAndTags.clearLookupCache);

  group('defaultFeaturesAndTags language matching', () {
    test('does not hide non-English constructs for a non-English L2', () {
      final morphs = MorphFeaturesAndTags.defaultFeaturesAndTags(
        targetLanguage: 'ru',
        userL1: 'en',
      );

      expect(
        morphs.getTags('Case').map((t) => t.value),
        contains('Ins'),
        reason:
            'instrumental case manifests in Russian; the English fallback '
            'marks it display:false and must not filter it out for ru',
      );
    });

    test('still applies display filtering when the L2 is English', () {
      final morphs = MorphFeaturesAndTags.defaultFeaturesAndTags(
        targetLanguage: 'en',
        userL1: 'en',
      );

      expect(
        morphs.getTags('Case').map((t) => t.value),
        isNot(contains('Ins')),
        reason:
            'for English the fallback flags are authoritative, so '
            'display:false values stay filtered',
      );
      expect(morphs.getTags('Case').map((t) => t.value), contains('Nom'));
    });

    test('regional variants of English still filter', () {
      final morphs = MorphFeaturesAndTags.defaultFeaturesAndTags(
        targetLanguage: 'en-US',
        userL1: 'en',
      );

      expect(
        morphs.getTags('Case').map((t) => t.value),
        isNot(contains('Ins')),
      );
    });

    test('server responses are always display-filtered regardless of L2', () {
      final morphs = MorphFeaturesAndTags.fromGrammarConstructsResponse(
        response: GrammarConstructsResponse.fromJson({
          "user_l1": "en",
          "source_l1": "en",
          "target_language": "ru",
          "features": [
            {
              "feature": "Case",
              "feature_title": "Case",
              "values": [
                {
                  "value": "Ins",
                  "display": true,
                  "example": "",
                  "sequence_position": 3.5,
                  "title": "Instrumental",
                  "description": "",
                },
                {
                  "value": "Abs",
                  "display": false,
                  "example": "",
                  "sequence_position": 5.5,
                  "title": "Absolutive",
                  "description": "",
                },
              ],
            },
          ],
        }),
      );

      expect(morphs.getTags('Case').map((t) => t.value), ['Ins']);
    });
  });

  group('fallback inventory matches the post-#2873 master', () {
    late GrammarConstructsResponse fallback;

    setUp(() {
      fallback = GrammarConstructsResponse.fromJson(
        defaultGrammarConstructsResponse,
      );
    });

    List<String> valuesOf(String feature) => fallback.features
        .where((f) => f.value.toLowerCase() == feature.toLowerCase())
        .expand((f) => f.tags.map((t) => t.value))
        .toList();

    bool hasFeature(String feature) => fallback.features.any(
      (f) => f.value.toLowerCase() == feature.toLowerCase(),
    );

    test('purged features are absent', () {
      // ConjType duplicated Pos=CCONJ/SCONJ; NounType duplicated
      // Pos=PROPN/NOUN. Both were removed from the master in #2873.
      expect(hasFeature('ConjType'), isFalse);
      expect(hasFeature('NounType'), isFalse);
    });

    test('purged values are absent', () {
      expect(valuesOf('AdvType'), isNot(contains('Adverbial')));
      expect(valuesOf('Case'), isNot(contains('Adv')));
      expect(valuesOf('Case'), isNot(contains('Pre')));
      expect(valuesOf('Tense'), isNot(contains('Eps')));
      for (final gone in ['Adn', 'Lng', 'Shrt', 'Compl', 'Aux']) {
        expect(valuesOf('VerbForm'), isNot(contains(gone)), reason: gone);
      }
      expect(valuesOf('VerbType'), isNot(contains('Caus')));
      expect(valuesOf('Voice'), isNot(contains('Caus')));
      expect(
        valuesOf('Voice'),
        contains('Cau'),
        reason: 'Cau is the real UD causative voice and must survive',
      );
    });

    test('real constructs survive the purge', () {
      expect(valuesOf('Case'), contains('Ins'));
      expect(valuesOf('Pos'), contains('CCONJ'));
      expect(valuesOf('Tense'), contains('Pres'));
      expect(valuesOf('AdvType'), contains('Tim'));
    });

    test('never-learner-facing POS values are not displayed', () {
      final pos = fallback.features.firstWhere(
        (f) => f.value.toLowerCase() == 'pos',
      );
      for (final value in ['PROPN', 'PUNCT', 'SYM', 'X']) {
        final match = pos.tags.where((t) => t.value == value);
        for (final tag in match) {
          expect(tag.display, isFalse, reason: 'Pos=$value must stay hidden');
        }
      }
    });
  });
}
