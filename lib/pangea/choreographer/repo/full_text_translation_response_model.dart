import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class FullTextTranslationResponseModel {
  List<String> translations;

  /// detected source
  /// PTODO -
  String source;
  String? deepL;

  FullTextTranslationResponseModel({
    required this.translations,
    required this.source,
    required this.deepL,
  });

  factory FullTextTranslationResponseModel.fromJson(Map<String, dynamic> json) {
    return FullTextTranslationResponseModel(
      translations: (json["translations"] as Iterable)
          .map<String>(
            (e) => e,
          )
          .toList()
          .cast<String>(),
      source: json[ModelKey.srcLang],
      deepL: json['deepl_res'],
    );
  }

  String get bestTranslation => deepL ?? translations.first;
}
