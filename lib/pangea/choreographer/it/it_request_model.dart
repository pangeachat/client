import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/choreographer/it/completed_it_step_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class ITRequestModel {
  final String text;
  final String customInput;
  final String sourceLangCode;
  final String targetLangCode;

  final String? goldTranslation;
  final List<ContinuanceModel>? goldContinuances;

  const ITRequestModel({
    required this.text,
    required this.customInput,
    required this.sourceLangCode,
    required this.targetLangCode,
    required this.goldTranslation,
    required this.goldContinuances,
  });

  factory ITRequestModel.fromJson(Map<String, dynamic> json) => ITRequestModel(
    text: json[ModelKey.text],
    customInput: json['custom_input'],
    sourceLangCode: json[ModelKey.srcLang],
    targetLangCode: json[ModelKey.tgtLang],
    goldTranslation: json[ModelKey.goldTranslation],
    goldContinuances: json['gold_continuances'] != null
        ? (json['gold_continuances'])
              .map((e) => ContinuanceModel.fromJson(e))
              .toList()
        : null,
  );

  Map<String, dynamic> toJson() => {
    ModelKey.text: text,
    'custom_input': customInput,
    ModelKey.srcLang: sourceLangCode,
    ModelKey.tgtLang: targetLangCode,
    ModelKey.goldTranslation: goldTranslation,
    'gold_continuances': goldContinuances != null
        ? List.from(goldContinuances!.map((e) => e.toJson()))
        : null,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ITRequestModel &&
        other.text == text &&
        other.customInput == customInput &&
        other.sourceLangCode == sourceLangCode &&
        other.targetLangCode == targetLangCode &&
        other.goldTranslation == goldTranslation &&
        listEquals(other.goldContinuances, goldContinuances);
  }

  @override
  int get hashCode =>
      text.hashCode ^
      customInput.hashCode ^
      sourceLangCode.hashCode ^
      targetLangCode.hashCode ^
      goldTranslation.hashCode ^
      Object.hashAll(goldContinuances ?? []);
}
