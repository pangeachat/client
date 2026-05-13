import 'package:fluffychat/pangea/morphs/localized_grammar_constructs_response.dart';

class LocalizedMorphFeaturesAndTags {
  final List<LocalizedMorphFeatureTags> features;

  const LocalizedMorphFeaturesAndTags({required this.features});

  factory LocalizedMorphFeaturesAndTags.fromLocalizedGrammarConstructsResponse({
    required LocalizedGrammarConstructsResponse response,
  }) {
    final List<LocalizedMorphFeatureTags> sortedFeatures = [];
    for (final feature in response.features) {
      final tags = List<LocalizedGrammarFeatureValue>.from(
        feature.values,
      ).where((t) => t.display).toList();

      tags.sort((a, b) => a.sequencePosition.compareTo(b.sequencePosition));
      sortedFeatures.add(
        LocalizedMorphFeatureTags(feature: feature, tags: tags),
      );
    }
    return LocalizedMorphFeaturesAndTags(features: sortedFeatures);
  }
}

class LocalizedMorphFeatureTags {
  final LocalizedGrammarFeature feature;
  final List<LocalizedGrammarFeatureValue> tags;

  const LocalizedMorphFeatureTags({required this.feature, required this.tags});
}
