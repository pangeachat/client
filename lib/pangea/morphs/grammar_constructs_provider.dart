import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/localized_morph_features_and_tags.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class GrammarConstructsProvider {
  static GrammarConstructsRequest get _request => GrammarConstructsRequest(
    targetLanguage: _targetLanguage,
    userL1: _userL1,
  );

  static String get _targetLanguage =>
      MatrixState.pangeaController.userController.userL2Code ??
      LanguageKeys.defaultLanguage;

  static String get _userL1 =>
      MatrixState.pangeaController.userController.userL1Code ??
      LanguageKeys.defaultLanguage;

  static LocalizedMorphFeaturesAndTags get defaultFeaturesAndTags =>
      LocalizedMorphFeaturesAndTags.defaultFeaturesAndTags(
        targetLanguage: _targetLanguage,
        userL1: _userL1,
      );

  static Future<String?> fetchTagDescription({
    required String feature,
    required String tag,
  }) async {
    final morphs = await fetchFeaturesAndTags();
    return morphs.getFeature(feature)?.getTag(tag)?.description;
  }

  static GrammarTag? getTag({required String feature, required String tag}) {
    final morphs = getFeaturesAndTags();
    return morphs.getFeature(feature)?.getTag(tag);
  }

  static Future<List<GrammarTag>> fetchTags({required String feature}) async {
    final morphs = await fetchFeaturesAndTags();
    return morphs.getFeature(feature)?.tags ?? [];
  }

  static List<GrammarTag> getTags({required String feature}) {
    final morphs = getFeaturesAndTags();
    return morphs.getFeature(feature)?.tags ?? [];
  }

  static Future<LocalizedMorphFeaturesAndTags> fetchFeaturesAndTags() async {
    final result = await GrammarConstructsRepo.instance.get(_request);
    final response = result.asValue?.value;
    if (response != null) {
      return LocalizedMorphFeaturesAndTags.fromLocalizedGrammarConstructsResponse(
        response: response,
      );
    }

    return defaultFeaturesAndTags;
  }

  static LocalizedMorphFeaturesAndTags getFeaturesAndTags() {
    final response = GrammarConstructsRepo.instance.getCached(_request);
    if (response != null) {
      return LocalizedMorphFeaturesAndTags.fromLocalizedGrammarConstructsResponse(
        response: response,
      );
    }

    return defaultFeaturesAndTags;
  }

  static Future<void> setTagDescription({
    required String feature,
    required String tag,
    required String description,
  }) async {
    final request = _request;
    final constructsResult = await GrammarConstructsRepo.instance.get(request);
    final constructs = constructsResult.result;
    if (constructs == null) {
      Logs().w("Failed to fetch grammar constructs in setTagDescription");
      return;
    }

    final features = constructs.features;
    final featureIndex = features.indexWhere((f) => f.value == feature);
    if (featureIndex == -1) {
      Logs().w("Feature $feature not found in setTagDescription");
      return;
    }

    final tags = features[featureIndex].tags;
    final tagIndex = tags.indexWhere((t) => t.value == tag);
    if (tagIndex == -1) {
      Logs().w("Tag $tag not found in setTagDescription");
      return;
    }

    final currentTag = tags[tagIndex];
    final updatedTag = currentTag.copyWith(description: description);

    final updatedTags = List<GrammarTag>.from(tags);
    updatedTags[tagIndex] = updatedTag;

    final currentFeature = features[featureIndex];
    final updatedFeature = currentFeature.copyWith(tags: updatedTags);

    final updatedFeatures = List<GrammarFeature>.from(features);
    updatedFeatures[featureIndex] = updatedFeature;

    final updatedConstructs = constructs.copyWith(features: updatedFeatures);
    await GrammarConstructsRepo.instance.setCached(request, updatedConstructs);
  }
}
