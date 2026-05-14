import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

class LocalizedMorphFeaturesAndTags {
  final String targetLanguage;
  final String userL1;
  final List<LocalizedMorphFeatureTags> features;

  const LocalizedMorphFeaturesAndTags({
    required this.targetLanguage,
    required this.userL1,
    required this.features,
  });

  factory LocalizedMorphFeaturesAndTags.fromLocalizedGrammarConstructsResponse({
    required GrammarConstructsResponse response,
  }) {
    final List<LocalizedMorphFeatureTags> sortedFeatures = [];
    for (final feature in response.features) {
      final tags = List<GrammarTag>.from(
        feature.tags,
      ).where((t) => t.display).toList();

      tags.sort((a, b) => a.sequencePosition.compareTo(b.sequencePosition));
      sortedFeatures.add(
        LocalizedMorphFeatureTags(feature: feature, tags: tags),
      );
    }
    return LocalizedMorphFeaturesAndTags(
      targetLanguage: response.targetLanguage,
      userL1: response.userL1,
      features: sortedFeatures,
    );
  }

  factory LocalizedMorphFeaturesAndTags.defaultFeaturesAndTags({
    required String targetLanguage,
    required String userL1,
  }) => LocalizedMorphFeaturesAndTags(
    targetLanguage: targetLanguage,
    userL1: userL1,
    features: [],
  );

  LocalizedMorphFeatureTags? getFeature(String feature) =>
      features.firstWhereOrNull((f) => f.feature.value == feature);

  String guessMorphCategory(String morphLemma) {
    for (final featureTags in features) {
      if (featureTags.tags.any((t) => t.value == morphLemma)) {
        return featureTags.feature.value;
      }
    }
    ErrorHandler.logError(
      m: "Morph construct lemma $morphLemma not found in morph categories and labels",
      data: {"morphLemma": morphLemma},
    );
    return "Other";
  }
}

class LocalizedMorphFeatureTags {
  final GrammarFeature feature;
  final List<GrammarTag> tags;

  const LocalizedMorphFeatureTags({required this.feature, required this.tags});

  GrammarTag? getTag(String tag) =>
      tags.firstWhereOrNull((t) => t.value == tag);

  List<String> get tagValues => tags.map((t) => t.value).toList();
}
