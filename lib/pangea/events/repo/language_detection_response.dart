import 'package:fluffychat/pangea/choreographer/models/language_detection_model.dart';

class LanguageDetectionResponse {
  List<LanguageDetection> detections;
  String fullText;

  LanguageDetectionResponse({
    required this.detections,
    required this.fullText,
  });

  factory LanguageDetectionResponse.fromJson(Map<String, dynamic> json) {
    return LanguageDetectionResponse(
      detections: List<LanguageDetection>.from(
        (json['detections'] as Iterable).map(
          (e) => LanguageDetection.fromJson(e),
        ),
      ),
      fullText: json['full_text'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'detections': detections.map((e) => e.toJson()).toList(),
      'full_text': fullText,
    };
  }
}
