import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/base_response.dart';

class LocalizedGrammarConstructsResponse extends BaseResponse {
  final String userL1;
  final String sourceL1;
  final String targetLanguage;
  final List<LocalizedGrammarFeature> features;

  LocalizedGrammarConstructsResponse({
    required this.userL1,
    required this.sourceL1,
    required this.targetLanguage,
    required this.features,
  });

  LocalizedGrammarFeature? getFeature(String feature) =>
      features.firstWhereOrNull((f) => f.feature == feature);

  LocalizedGrammarConstructsResponse copyWith({
    String? userL1,
    String? sourceL1,
    String? targetLanguage,
    List<LocalizedGrammarFeature>? features,
  }) => LocalizedGrammarConstructsResponse(
    userL1: userL1 ?? this.userL1,
    sourceL1: sourceL1 ?? this.sourceL1,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    features: features ?? this.features,
  );

  LocalizedGrammarConstructsResponse copyWithMeaning({
    required String feature,
    required LocalizedGrammarFeatureValue meaning,
  }) {
    final valuesMap = Map<String, LocalizedGrammarFeature>.fromEntries(
      List<LocalizedGrammarFeature>.from(
        features,
      ).map((f) => MapEntry<String, LocalizedGrammarFeature>(f.feature, f)),
    );

    final currentValue = valuesMap[feature];
    if (currentValue == null) return this;

    valuesMap[feature] = currentValue.copyWithMeaning(meaning: meaning);
    return copyWith(features: valuesMap.values.toList());
  }

  @override
  Map<String, dynamic> toJson() => {
    "user_l1": userL1,
    "source_l1": sourceL1,
    "target_language": targetLanguage,
    "features": features.map((f) => f.toJson()).toList(),
  };

  static LocalizedGrammarConstructsResponse fromJson(
    Map<String, dynamic> json,
  ) => LocalizedGrammarConstructsResponse(
    userL1: json["user_l1"],
    sourceL1: json["source_l1"],
    targetLanguage: json["target_language"],
    features: List.from(json["features"])
        .map(
          (f) => LocalizedGrammarFeature.fromJson(Map<String, dynamic>.from(f)),
        )
        .toList(),
  );
}

class LocalizedGrammarFeature {
  final String feature;
  final String featureTitle;
  final List<LocalizedGrammarFeatureValue> values;

  const LocalizedGrammarFeature({
    required this.feature,
    required this.featureTitle,
    required this.values,
  });

  LocalizedGrammarFeatureValue? getTag(String tag) =>
      values.firstWhereOrNull((v) => v.value == tag);

  LocalizedGrammarFeature copyWith({
    String? feature,
    String? featureTitle,
    List<LocalizedGrammarFeatureValue>? values,
  }) => LocalizedGrammarFeature(
    feature: feature ?? this.feature,
    featureTitle: featureTitle ?? this.featureTitle,
    values: values ?? this.values,
  );

  LocalizedGrammarFeature copyWithMeaning({
    required LocalizedGrammarFeatureValue meaning,
  }) {
    final valuesMap = Map<String, LocalizedGrammarFeatureValue>.fromEntries(
      List<LocalizedGrammarFeatureValue>.from(
        values,
      ).map((v) => MapEntry<String, LocalizedGrammarFeatureValue>(v.value, v)),
    );
    valuesMap[meaning.value] = meaning;
    return copyWith(values: valuesMap.values.toList());
  }

  Map<String, dynamic> toJson() => {
    "feature": feature,
    "feature_title": featureTitle,
    "values": values.map((v) => v.toJson()).toList(),
  };

  static LocalizedGrammarFeature fromJson(Map<String, dynamic> json) =>
      LocalizedGrammarFeature(
        feature: json["feature"],
        featureTitle: json["feature_title"],
        values: List.from(json["values"])
            .map(
              (v) => LocalizedGrammarFeatureValue.fromJson(
                Map<String, dynamic>.from(v),
              ),
            )
            .toList(),
      );
}

class LocalizedGrammarFeatureValue {
  final bool display;
  final String example;
  final double sequencePosition;
  final String value;
  final String description;
  final String title;

  const LocalizedGrammarFeatureValue({
    required this.description,
    required this.display,
    required this.example,
    required this.sequencePosition,
    required this.title,
    required this.value,
  });

  LocalizedGrammarFeatureValue copyWith({
    bool? display,
    String? example,
    double? sequencePosition,
    String? value,
    String? description,
    String? title,
  }) => LocalizedGrammarFeatureValue(
    display: display ?? this.display,
    example: example ?? this.example,
    sequencePosition: sequencePosition ?? this.sequencePosition,
    value: value ?? this.value,
    description: description ?? this.description,
    title: title ?? this.title,
  );

  Map<String, dynamic> toJson() => {
    "description": description,
    "display": display,
    "example": example,
    "sequence_position": sequencePosition,
    "title": title,
    "value": value,
  };

  static LocalizedGrammarFeatureValue fromJson(Map<String, dynamic> json) =>
      LocalizedGrammarFeatureValue(
        description: json["description"],
        display: json["display"],
        example: json["example"],
        sequencePosition: json["sequence_position"],
        title: json["title"],
        value: json["value"],
      );
}
