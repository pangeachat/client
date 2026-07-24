import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_meaning_feedback_repo.dart';

/// Regression coverage for #7676: a grammar-meaning feedback response echoes
/// the feature in canonical case ("Aspect"), but the flag is raised from the
/// analytics construct category in lowercase ("aspect"). The merge must match
/// case-insensitively — as the display path (MorphFeaturesAndTags.getTag)
/// already does — or the regenerated copy never lands in the cache and the
/// card keeps showing the old definition even after the reload fires.
void main() {
  GrammarConstructsResponse constructs() => GrammarConstructsResponse.fromJson({
    "user_l1": "en",
    "source_l1": "en",
    "target_language": "de",
    "features": [
      {
        "feature": "Aspect",
        "feature_title": "Aspect",
        "values": [
          {
            "value": "Perf",
            "display": true,
            "example": "Ich habe gelesen",
            "sequence_position": 1.0,
            "title": "Perfect",
            "description": "OLD long definition",
          },
        ],
      },
    ],
  });

  GrammarMeaningFeedbackResponse regen({
    String feature = "Aspect",
    String value = "Perf",
  }) => GrammarMeaningFeedbackResponse(
    feature: feature,
    featureTitle: "Aspect",
    values: [
      GrammarMeaningValueUpdate(
        value: value,
        title: "Perfect Aspect",
        description: "NEW short definition",
      ),
    ],
    editsApplied: true,
  );

  test('merges when the flagged feature is lowercase (#7676)', () {
    final merged = GrammarConstructsProvider.mergeFeedbackIntoConstructs(
      constructs(),
      "aspect", // analytics construct category — lowercase UD key
      regen(),
    );

    expect(merged, isNotNull);
    final tag = merged!.features.single.tags.single;
    expect(tag.description, "NEW short definition");
    expect(tag.title, "Perfect Aspect");
  });

  test('merges tag values case-insensitively', () {
    final merged = GrammarConstructsProvider.mergeFeedbackIntoConstructs(
      constructs(),
      "aspect",
      regen(value: "perf"), // lowercased tag value
    );
    expect(
      merged!.features.single.tags.single.description,
      "NEW short definition",
    );
  });

  test('returns null when the feature is absent (cache left untouched)', () {
    final merged = GrammarConstructsProvider.mergeFeedbackIntoConstructs(
      constructs(),
      "tense",
      regen(),
    );
    expect(merged, isNull);
  });

  test(
    'leaves canonical-only fields (display, example, sequence) untouched',
    () {
      final merged = GrammarConstructsProvider.mergeFeedbackIntoConstructs(
        constructs(),
        "aspect",
        regen(),
      );
      final tag = merged!.features.single.tags.single;
      expect(tag.display, isTrue);
      expect(tag.example, "Ich habe gelesen");
      expect(tag.sequencePosition, 1.0);
    },
  );
}
