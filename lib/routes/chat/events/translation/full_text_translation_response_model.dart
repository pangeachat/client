import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';

class FullTextTranslationResponseModel extends BaseResponse {
  final List<String> translations;
  final String translation;
  final String source;

  FullTextTranslationResponseModel({
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

  @override
  Map<String, dynamic> toJson() => {
    'translation': translation,
    'translations': translations,
    ChoreoConstants.srcLang: source,
  };

  String get bestTranslation => translation;
}
