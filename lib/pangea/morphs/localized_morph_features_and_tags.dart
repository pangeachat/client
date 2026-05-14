import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

class LocalizedMorphFeaturesAndTags {
  final String _targetLanguage;
  final String _userL1;
  final List<LocalizedMorphFeatureTags> _features;

  static final Map<String, Map<String, GrammarFeature>> _featureLookup = {};

  static final Map<String, Map<String, Map<String, GrammarTag>>> _tagLookup =
      {};

  LocalizedMorphFeaturesAndTags({
    required String targetLanguage,
    required String userL1,
    required List<LocalizedMorphFeatureTags> features,
  }) : _targetLanguage = targetLanguage,
       _userL1 = userL1,
       _features = features;

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

  String get _langKey => "$_targetLanguage-$_userL1";

  List<LocalizedMorphFeatureTags> get features => _features;

  static void clearLookupCache() {
    _tagLookup.clear();
    _featureLookup.clear();
  }

  LocalizedMorphFeatureTags? _getFeature(String feature) =>
      _features.firstWhereOrNull(
        (f) => f.feature.value.toLowerCase() == feature.toLowerCase(),
      );

  GrammarFeature? getFeature(String feature) {
    final lookup = _featureLookup[_langKey]?[feature];
    if (lookup != null) {
      return lookup;
    }

    final match = _getFeature(feature)?.feature;
    if (match == null) {
      return match;
    }

    _featureLookup[_langKey] ??= {};
    _featureLookup[_langKey]![feature] = match;
    return match;
  }

  GrammarTag? getTag(String feature, String tag) {
    final lookup = _tagLookup[_langKey]?[feature]?[tag];
    if (lookup != null) {
      return lookup;
    }

    final match = _getFeature(feature)?.getTag(tag);
    if (match == null) {
      return null;
    }

    _tagLookup[_langKey] ??= {};
    _tagLookup[_langKey]![feature] ??= {};
    _tagLookup[_langKey]![feature]![tag] = match;
    return match;
  }

  String guessMorphCategory(String morphLemma) {
    for (final featureTags in _features) {
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

  LocalizedMorphFeatureTags({required this.feature, required this.tags});

  GrammarTag? getTag(String tag) =>
      tags.firstWhereOrNull((t) => t.value.toLowerCase() == tag.toLowerCase());

  List<String> get tagValues => tags.map((t) => t.value).toList();
}
