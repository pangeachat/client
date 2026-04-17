import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';

class FullTextTranslationResponseModel {
  final List<String> translations;
  final String translation;
  final String source;

  const FullTextTranslationResponseModel({
    required this.translation,
    required this.translations,
    required this.source,
  });

  factory FullTextTranslationResponseModel.fromJson(Map<String, dynamic> json) {
    return FullTextTranslationResponseModel(
      translation: json['translation'] as String,
      translations: (json["translations"] as Iterable)
          .map<String>((e) => e)
          .toList()
          .cast<String>(),
      source: json[ChoreoConstants.srcLang],
    );
  }

  Map<String, dynamic> toJson() => {
    'translation': translation,
    'translations': translations,
    ChoreoConstants.srcLang: source,
  };

  String get bestTranslation => translation;
}
