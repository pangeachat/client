import 'package:fluffychat/pangea/common/utils/base_response.dart';

class GrammarConstructsResponse extends BaseResponse {
  final String userL1;
  final String sourceL1;
  final String targetLanguage;
  final List<GrammarFeature> features;

  GrammarConstructsResponse({
    required this.userL1,
    required this.sourceL1,
    required this.targetLanguage,
    required this.features,
  });

  GrammarConstructsResponse copyWith({
    String? userL1,
    String? sourceL1,
    String? targetLanguage,
    List<GrammarFeature>? features,
  }) => GrammarConstructsResponse(
    userL1: userL1 ?? this.userL1,
    sourceL1: sourceL1 ?? this.sourceL1,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    features: features ?? this.features,
  );

  @override
  Map<String, dynamic> toJson() => {
    "user_l1": userL1,
    "source_l1": sourceL1,
    "target_language": targetLanguage,
    "features": features.map((f) => f.toJson()).toList(),
  };

  static GrammarConstructsResponse fromJson(Map<String, dynamic> json) =>
      GrammarConstructsResponse(
        userL1: json["user_l1"],
        sourceL1: json["source_l1"],
        targetLanguage: json["target_language"],
        features: List.from(json["features"])
            .map((f) => GrammarFeature.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
      );
}

class GrammarFeature {
  final String value;
  final String title;
  final List<GrammarTag> tags;

  const GrammarFeature({
    required this.value,
    required this.title,
    required this.tags,
  });

  GrammarFeature copyWith({
    String? value,
    String? title,
    List<GrammarTag>? tags,
  }) => GrammarFeature(
    value: value ?? this.value,
    title: title ?? this.title,
    tags: tags ?? this.tags,
  );

  Map<String, dynamic> toJson() => {
    "feature": value,
    "feature_title": title,
    "values": tags.map((v) => v.toJson()).toList(),
  };

  static GrammarFeature fromJson(Map<String, dynamic> json) => GrammarFeature(
    value: json["feature"],
    title: json["feature_title"],
    tags: List.from(
      json["values"],
    ).map((v) => GrammarTag.fromJson(Map<String, dynamic>.from(v))).toList(),
  );
}

class GrammarTag {
  final String value;
  final bool display;
  final String example;
  final double sequencePosition;
  final String description;
  final String title;

  const GrammarTag({
    required this.value,
    required this.description,
    required this.display,
    required this.example,
    required this.sequencePosition,
    required this.title,
  });

  GrammarTag copyWith({
    bool? display,
    String? example,
    double? sequencePosition,
    String? value,
    String? description,
    String? title,
  }) => GrammarTag(
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

  static GrammarTag fromJson(Map<String, dynamic> json) => GrammarTag(
    description: json["description"],
    display: json["display"],
    example: json["example"],
    sequencePosition: json["sequence_position"],
    title: json["title"],
    value: json["value"],
  );
}
