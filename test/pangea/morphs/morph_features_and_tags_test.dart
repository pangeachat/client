import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';

/// Regression coverage for #7715: grammar practice must draw answer options
/// only from the display-eligible tag set (the values that actually manifest
/// in the target language), never from the full unfiltered UD inventory.
void main() {
  Map<String, dynamic> tag(
    String value, {
    required bool display,
    String? title,
  }) => {
    "value": value,
    "display": display,
    "example": "",
    "sequence_position": 3.5,
    "title": title ?? value,
    "description": "",
  };

  MorphFeaturesAndTags build(List<Map<String, dynamic>> features) =>
      MorphFeaturesAndTags.fromGrammarConstructsResponse(
        response: GrammarConstructsResponse.fromJson({
          "user_l1": "en",
          "source_l1": "en",
          "target_language": "fr",
          "features": features,
        }),
      );

  setUp(MorphFeaturesAndTags.clearLookupCache);

  group('MorphFeaturesAndTags.getTags', () {
    test('returns only display-eligible tags', () {
      final morphs = build([
        {
          "feature": "Mood",
          "feature_title": "Mood",
          "values": [
            tag("Ind", display: true, title: "Indicative"),
            tag("Sub", display: true, title: "Subjunctive"),
            tag("Jus", display: false, title: "Jussive"),
            tag("Prp", display: false, title: "Purposive"),
          ],
        },
      ]);

      expect(
        morphs.getTags("Mood").map((t) => t.value),
        ["Ind", "Sub"],
        reason: 'display:false typological labels must be filtered out',
      );
    });

    test('does not mutate the unfiltered inventory on getFeature', () {
      final morphs = build([
        {
          "feature": "Mood",
          "feature_title": "Mood",
          "values": [
            tag("Ind", display: true),
            tag("Jus", display: false),
          ],
        },
      ]);

      // getFeature still exposes the raw GrammarFeature (full inventory);
      // only getTags applies the display filter. This documents where the
      // fix lives so a future refactor doesn't silently reintroduce the leak.
      expect(morphs.getFeature("Mood")?.tags.map((t) => t.value), [
        "Ind",
        "Jus",
      ]);
      expect(morphs.getTags("Mood").map((t) => t.value), ["Ind"]);
    });
  });

  group('MorphFeaturesAndTags.distractorTagValues', () {
    test('excludes display:false values and the answer (case-insensitive)', () {
      final morphs = build([
        {
          "feature": "Mood",
          "feature_title": "Mood",
          "values": [
            tag("Ind", display: true),
            tag("Sub", display: true),
            tag("Cnd", display: true),
            tag("Jus", display: false),
            tag("Adm", display: false),
          ],
        },
      ]);

      expect(morphs.distractorTagValues("Mood", "ind"), ["Sub", "Cnd"]);
    });

    test('excludes non-lemma POS categories even when display:true', () {
      final morphs = build([
        {
          "feature": "Pos",
          "feature_title": "Part of speech",
          "values": [
            tag("NOUN", display: true),
            // A non-lemma category that is (incorrectly) display:true must
            // still never be offered as a distractor — the #7601 guard.
            tag("PUNCT", display: true),
            tag("AFFIX", display: false),
          ],
        },
      ]);

      expect(morphs.distractorTagValues("Pos", "NOUN"), isEmpty);
    });

    test('returns empty when the answer is the only display-eligible tag', () {
      final morphs = build([
        {
          "feature": "Poss",
          "feature_title": "Possessive",
          "values": [
            tag("Yes", display: true),
            tag("No", display: false),
          ],
        },
      ]);

      expect(morphs.distractorTagValues("Poss", "Yes"), isEmpty);
    });
  });
}
