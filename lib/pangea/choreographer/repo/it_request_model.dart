import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/choreographer/models/it_step.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class ITRequestModel {
  final String text;
  final String customInput;
  final String sourceLangCode;
  final String targetLangCode;
  final String userId;
  final String roomId;

  final String? goldTranslation;
  final List<Continuance>? goldContinuances;

  const ITRequestModel({
    required this.text,
    required this.customInput,
    required this.sourceLangCode,
    required this.targetLangCode,
    required this.userId,
    required this.roomId,
    required this.goldTranslation,
    required this.goldContinuances,
  });

  factory ITRequestModel.fromJson(json) => ITRequestModel(
        text: json['text'],
        customInput: json['custom_input'],
        sourceLangCode: json[ModelKey.srcLang],
        targetLangCode: json[ModelKey.tgtLang],
        userId: json['user_id'],
        roomId: json['room_id'],
        goldTranslation: json['gold_translation'],
        goldContinuances: json['gold_continuances'] != null
            ? (json['gold_continuances'])
                .map((e) => Continuance.fromJson(e))
                .toList()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'custom_input': customInput,
        ModelKey.srcLang: sourceLangCode,
        ModelKey.tgtLang: targetLangCode,
        'user_id': userId,
        'room_id': roomId,
        'gold_translation': goldTranslation,
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
        other.userId == userId &&
        other.roomId == roomId &&
        other.goldTranslation == goldTranslation &&
        listEquals(other.goldContinuances, goldContinuances);
  }

  @override
  int get hashCode =>
      text.hashCode ^
      customInput.hashCode ^
      sourceLangCode.hashCode ^
      targetLangCode.hashCode ^
      userId.hashCode ^
      roomId.hashCode ^
      goldTranslation.hashCode ^
      Object.hashAll(goldContinuances ?? []);
}
