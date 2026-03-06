import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';

class TextToSpeechRequestModel {
  String text;
  String langCode;
  String userL1;
  String userL2;
  List<PangeaTokenText> tokens;
  String? voice;
  String? ttsPhoneme;
  double speakingRate;

  TextToSpeechRequestModel({
    required this.text,
    required this.langCode,
    required this.userL1,
    required this.userL2,
    required this.tokens,
    this.voice,
    this.ttsPhoneme,
    this.speakingRate = 0.85,
  });

  Map<String, dynamic> toJson() => {
    ModelKey.text: text,
    ModelKey.langCode: langCode,
    ModelKey.userL1: userL1,
    ModelKey.userL2: userL2,
    ModelKey.tokens: tokens.map((token) => token.toJson()).toList(),
    'voice': voice,
    if (ttsPhoneme != null) 'tts_phoneme': ttsPhoneme,
    'speaking_rate': speakingRate,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TextToSpeechRequestModel &&
        other.text == text &&
        other.langCode == langCode &&
        other.voice == voice &&
        other.ttsPhoneme == ttsPhoneme;
  }

  @override
  int get hashCode =>
      text.hashCode ^ langCode.hashCode ^ voice.hashCode ^ ttsPhoneme.hashCode;
}
