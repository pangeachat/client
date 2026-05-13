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
