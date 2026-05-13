import 'package:collection/collection.dart';

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

  GrammarFeatureValueMeaning? getTag(String tag) =>
      values.firstWhereOrNull((v) => v.value == tag);

  GrammarConstructMeaningResponse copyWith({
    String? feature,
    String? featureTitle,
    List<GrammarFeatureValueMeaning>? values,
  }) {
    return GrammarConstructMeaningResponse(
      feature: feature ?? this.feature,
      featureTitle: featureTitle ?? this.featureTitle,
      values: values ?? this.values,
    );
  }

  GrammarConstructMeaningResponse copyWithMeaning({
    required GrammarFeatureValueMeaning meaning,
  }) {
    final valuesMap = Map<String, GrammarFeatureValueMeaning>.fromEntries(
      List<GrammarFeatureValueMeaning>.from(
        values,
      ).map((v) => MapEntry<String, GrammarFeatureValueMeaning>(v.value, v)),
    );
    valuesMap[meaning.value] = meaning;
    return copyWith(values: valuesMap.values.toList());
  }

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

  GrammarFeatureValueMeaning copyWith({
    String? description,
    String? title,
    String? value,
  }) {
    return GrammarFeatureValueMeaning(
      description: description ?? this.description,
      title: title ?? this.title,
      value: value ?? this.value,
    );
  }

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
