import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';

class TextToSpeechResponseModel {
  String audioContent;
  String mimeType;
  int durationMillis;
  List<int> waveform;
  String fileExtension;
  List<TTSToken> ttsTokens;

  TextToSpeechResponseModel({
    required this.audioContent,
    required this.mimeType,
    required this.durationMillis,
    required this.waveform,
    required this.fileExtension,
    required this.ttsTokens,
  });

  factory TextToSpeechResponseModel.fromJson(Map<String, dynamic> json) =>
      TextToSpeechResponseModel(
        audioContent: json["audio_content"],
        mimeType: json["mime_type"],
        durationMillis: json["duration_millis"],
        waveform: List<int>.from(json["wave_form"]),
        fileExtension: json["file_extension"],
        ttsTokens: List<TTSToken>.from(
          json["tts_tokens"].map((x) => TTSToken.fromJson(x)),
        ),
      );

  Map<String, dynamic> toJson() => {
        "audio_content": audioContent,
        "mime_type": mimeType,
        "duration_millis": durationMillis,
        "wave_form": List<dynamic>.from(waveform.map((x) => x)),
        "file_extension": fileExtension,
        "tts_tokens": List<dynamic>.from(ttsTokens.map((x) => x.toJson())),
      };

  PangeaAudioEventData toPangeaAudioEventData(
    String text,
    String langCode,
    String? voice,
  ) {
    return PangeaAudioEventData(
      text: text,
      langCode: langCode,
      tokens: ttsTokens,
      voice: voice,
    );
  }
}

class TTSToken {
  final int startMS;
  final int endMS;
  final PangeaTokenText text;

  TTSToken({required this.startMS, required this.endMS, required this.text});

  factory TTSToken.fromJson(Map<String, dynamic> json) => TTSToken(
        startMS: json["start_ms"],
        endMS: json["end_ms"],
        text: PangeaTokenText.fromJson(json["text"]),
      );

  Map<String, dynamic> toJson() => {
        "start_ms": startMS,
        "end_ms": endMS,
        "text": text.toJson(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TTSToken &&
        other.startMS == startMS &&
        other.endMS == endMS &&
        other.text == text;
  }

  @override
  int get hashCode => startMS.hashCode ^ endMS.hashCode ^ text.hashCode;
}

class PangeaAudioEventData {
  final String text;
  final String langCode;
  final List<TTSToken> tokens;
  final String? voice;

  PangeaAudioEventData({
    required this.text,
    required this.langCode,
    required this.tokens,
    this.voice,
  });

  factory PangeaAudioEventData.fromJson(dynamic json) => PangeaAudioEventData(
        text: json[ModelKey.text] as String,
        langCode: json[ModelKey.langCode] as String,
        tokens: List<TTSToken>.from(
          (json[ModelKey.tokens] as Iterable)
              .map((x) => TTSToken.fromJson(x))
              .toList(),
        ),
        voice: json[ModelKey.voice] as String?,
      );

  Map<String, dynamic> toJson() => {
        ModelKey.text: text,
        ModelKey.langCode: langCode,
        ModelKey.tokens: List<Map<String, dynamic>>.from(
          tokens.map((x) => x.toJson()),
        ),
        if (voice != null) ModelKey.voice: voice,
      };
}
