import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class LanguageDetectionModel {
  final String langCode;
  final double confidence;

  const LanguageDetectionModel({
    required this.langCode,
    required this.confidence,
  });

  factory LanguageDetectionModel.fromJson(Map<String, dynamic> json) {
    final dynamic confValue = json[ModelKey.confidence];
    double confidence;
    if (confValue is String) {
      confidence = double.parse(confValue);
    } else if (confValue is double) {
      confidence = confValue;
    } else if (confValue is int) {
      confidence = confValue.toDouble();
    } else {
      throw TypeError();
    }
    return LanguageDetectionModel(
      langCode: json[ModelKey.langCode],
      confidence: confidence,
    );
  }

  Map<String, dynamic> toJson() => {
    ModelKey.langCode: langCode,
    ModelKey.confidence: confidence,
  };
}
