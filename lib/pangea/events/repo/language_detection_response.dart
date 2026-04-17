import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/models/language_detection_model.dart';

class LanguageDetectionResponse {
  List<LanguageDetectionModel> detections;
  String fullText;

  LanguageDetectionResponse({required this.detections, required this.fullText});

  factory LanguageDetectionResponse.fromJson(Map<String, dynamic> json) {
    return LanguageDetectionResponse(
      detections: List<LanguageDetectionModel>.from(
        (json['detections'] as Iterable).map(
          (e) => LanguageDetectionModel.fromJson(e),
        ),
      ),
      fullText: json[ModelKey.fullText],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'detections': detections.map((e) => e.toJson()).toList(),
      ModelKey.fullText: fullText,
    };
  }
}
