import 'package:fluffychat/pangea/common/utils/base_response.dart';

class GrammarConstructFeaturesResponse extends BaseResponse {
  final String sourceL1;
  final List<GrammarFeature> features;

  GrammarConstructFeaturesResponse({
    required this.sourceL1,
    required this.features,
  });

  @override
  Map<String, dynamic> toJson() => {
    "source_l1": sourceL1,
    "features": features.map((f) => f.toJson()).toList(),
  };

  static GrammarConstructFeaturesResponse fromJson(Map<String, dynamic> json) =>
      GrammarConstructFeaturesResponse(
        sourceL1: json["source_l1"],
        features: List.from(json["features"])
            .map((f) => GrammarFeature.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
      );
}

class GrammarFeature {
  final String feature;
  final List<GrammarFeatureValue> values;

  const GrammarFeature({required this.feature, required this.values});

  Map<String, dynamic> toJson() => {
    "feature": feature,
    "values": values.map((v) => v.toJson()).toList(),
  };

  static GrammarFeature fromJson(Map<String, dynamic> json) => GrammarFeature(
    feature: json["feature"],
    values: List.from(json["values"])
        .map((v) => GrammarFeatureValue.fromJson(Map<String, dynamic>.from(v)))
        .toList(),
  );
}

class GrammarFeatureValue {
  final bool display;
  final String example;
  final double sequencePosition;
  final String value;

  const GrammarFeatureValue({
    required this.display,
    required this.example,
    required this.sequencePosition,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    "display": display,
    "example": example,
    "sequence_position": sequencePosition,
    "value": value,
  };

  static GrammarFeatureValue fromJson(Map<String, dynamic> json) =>
      GrammarFeatureValue(
        display: json["display"],
        example: json["example"],
        sequencePosition: json["sequence_position"],
        value: json["value"],
      );
}
