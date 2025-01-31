class MorphFeature {
  final String feature;
  final List<String> tag;

  MorphFeature({required this.feature, required this.tag});

  factory MorphFeature.fromJson(Map<String, dynamic> json) {
    return MorphFeature(
      feature: json['feature'],
      tag: List<String>.from(json['tag']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'feature': feature,
      'tag': tag,
    };
  }
}

class MorphsByLanguage {
  final String languageCode;
  final List<MorphFeature> features;

  MorphsByLanguage({required this.languageCode, required this.features});

  factory MorphsByLanguage.fromJson(Map<String, dynamic> json) {
    return MorphsByLanguage(
      languageCode: json['language_code'],
      features: List<MorphFeature>.from(
        json['features'].map((x) => MorphFeature.fromJson(x)),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'language_code': languageCode,
      'features': features.map((x) => x.toJson()).toList(),
    };
  }
}
