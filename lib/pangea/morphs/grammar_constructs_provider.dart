import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_repo.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_request.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_meaning_feedback_repo.dart';
import 'package:fluffychat/pangea/morphs/morph_features_and_tags.dart';
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

  static MorphFeaturesAndTags get defaultFeaturesAndTags =>
      MorphFeaturesAndTags.defaultFeaturesAndTags(
        targetLanguage: _targetLanguage,
        userL1: _userL1,
      );

  static String? getTagTitle({required String feature, required String tag}) =>
      getTag(feature: feature, tag: tag)?.title;

  static Future<String?> fetchTagDescription({
    required String feature,
    required String tag,
  }) async => (await fetchTag(feature: feature, tag: tag))?.description;

  static GrammarTag? getTag({required String feature, required String tag}) {
    final morphs = getFeaturesAndTags();
    return morphs.getTag(feature, tag);
  }

  static Future<GrammarTag?> fetchTag({
    required String feature,
    required String tag,
  }) async {
    final morphs = await fetchFeaturesAndTags();
    return morphs.getTag(feature, tag);
  }

  static List<GrammarTag> getTags({required String feature}) {
    final morphs = getFeaturesAndTags();
    return morphs.getFeature(feature)?.tags ?? [];
  }

  static Future<List<GrammarTag>> fetchTags({required String feature}) async {
    final morphs = await fetchFeaturesAndTags();
    return morphs.getFeature(feature)?.tags ?? [];
  }

  static GrammarFeature? getFeature({required String feature}) {
    final morphs = getFeaturesAndTags();
    return morphs.getFeature(feature);
  }

  static MorphFeaturesAndTags getFeaturesAndTags() {
    final response = GrammarConstructsRepo.instance.getCached(_request);
    if (response != null) {
      return MorphFeaturesAndTags.fromGrammarConstructsResponse(
        response: response,
      );
    }

    return defaultFeaturesAndTags;
  }

  static Future<MorphFeaturesAndTags> fetchFeaturesAndTags() async {
    final result = await GrammarConstructsRepo.instance.get(_request);
    final response = result.asValue?.value;
    if (response != null) {
      return MorphFeaturesAndTags.fromGrammarConstructsResponse(
        response: response,
      );
    }

    return defaultFeaturesAndTags;
  }

  /// Flag a grammar meaning (#6839): send the user's feedback to the
  /// choreographer, which regenerates the feature's meaning bundle in
  /// place and returns it (choreo #2548). The regenerated titles and
  /// descriptions are merged into the cached joined response by value
  /// (canonical-only fields — display, example, sequence — are untouched).
  static Future<void> submitTagFeedback({
    required String feature,
    required String feedback,
  }) async {
    final request = _request;
    final regen = await GrammarMeaningFeedbackRepo.submitFeedback(
      feature: feature,
      targetLanguage: request.targetLanguage,
      userL1: request.userL1,
      feedback: feedback,
    );

    final constructsResult = await GrammarConstructsRepo.instance.get(request);
    final constructs = constructsResult.result;
    if (constructs == null) {
      Logs().w("Failed to fetch grammar constructs in submitTagFeedback");
      return;
    }

    final features = constructs.features;
    final featureIndex = features.indexWhere((f) => f.value == feature);
    if (featureIndex == -1) {
      Logs().w("Feature $feature not found in submitTagFeedback");
      return;
    }

    final currentFeature = features[featureIndex];
    final updatesByValue = {for (final v in regen.values) v.value: v};
    final updatedTags = currentFeature.tags.map((tag) {
      final update = updatesByValue[tag.value];
      if (update == null) return tag;
      return tag.copyWith(title: update.title, description: update.description);
    }).toList();

    final updatedFeatures = List<GrammarFeature>.from(features);
    updatedFeatures[featureIndex] = currentFeature.copyWith(
      title: regen.featureTitle,
      tags: updatedTags,
    );

    final updatedConstructs = constructs.copyWith(features: updatedFeatures);
    await GrammarConstructsRepo.instance.setCached(request, updatedConstructs);
    MorphFeaturesAndTags.clearLookupCache();
  }
}
