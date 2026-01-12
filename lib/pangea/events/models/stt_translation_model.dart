import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

class SttTranslationModel {
  final String translation;
  final String langCode;

  SttTranslationModel({
    required this.translation,
    required this.langCode,
  });

  factory SttTranslationModel.fromJson(Map<String, dynamic> json) {
    final content = json.tryGetMap(PangeaEventTypes.sttTranslation);
    if (content == null) {
      throw Exception("STT Translation content is null");
    }

    return SttTranslationModel(
      translation: content['translation'] as String,
      langCode: content['lang_code'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'translation': translation,
      'lang_code': langCode,
    };
  }
}
