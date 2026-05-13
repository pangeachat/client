import 'package:fluffychat/pangea/common/utils/base_response.dart';

class GrammarConstructMeaningResponse extends BaseResponse {
  final String feature;
  final String featureTitle;
  final List<GrammarFeatureValueMeaning> values;

  GrammarConstructMeaningResponse({
    required this.feature,
    required this.featureTitle,
    required this.values,
  });

  @override
  Map<String, dynamic> toJson() => {
    "feature": feature,
    "feature_title": featureTitle,
    "values": values.map((v) => v.toJson()).toList(),
  };

  static GrammarConstructMeaningResponse fromJson(Map<String, dynamic> json) =>
      GrammarConstructMeaningResponse(
        feature: json["feature"],
        featureTitle: json["feature_title"],
        values: List.from(json["values"])
            .map(
              (v) => GrammarFeatureValueMeaning.fromJson(
                Map<String, dynamic>.from(v),
              ),
            )
            .toList(),
      );
}

class GrammarFeatureValueMeaning {
  final String description;
  final String title;
  final String value;

  const GrammarFeatureValueMeaning({
    required this.description,
    required this.title,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
    "description": description,
    "title": title,
    "value": value,
  };

  static GrammarFeatureValueMeaning fromJson(Map<String, dynamic> json) =>
      GrammarFeatureValueMeaning(
        description: json["description"],
        title: json["title"],
        value: json["value"],
      );
}
