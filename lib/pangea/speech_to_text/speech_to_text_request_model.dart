import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/speech_to_text/audio_encoding_enum.dart';

class SpeechToTextRequestModel {
  final Uint8List audioContent;
  final SpeechToTextAudioConfigModel config;
  final Event? audioEvent;

  SpeechToTextRequestModel({
    required this.audioContent,
    required this.config,
    this.audioEvent,
  });

  Map<String, dynamic> toJson() => {
    "audio_content": base64Encode(audioContent),
    "config": config.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpeechToTextRequestModel) return false;

    return listEquals(audioContent, other.audioContent) &&
        config == other.config;
  }

  @override
  int get hashCode {
    final bytesSample = audioContent.length > 10
        ? audioContent.sublist(0, 10)
        : audioContent;
    return Object.hashAll([Object.hashAll(bytesSample), config.hashCode]);
  }
}

class SpeechToTextAudioConfigModel {
  final AudioEncodingEnum encoding;
  final int sampleRateHertz;
  final bool enableWordConfidence;
  final bool enableAutomaticPunctuation;
  final String userL1;
  final String userL2;

  SpeechToTextAudioConfigModel({
    required this.encoding,
    required this.userL1,
    required this.userL2,
    this.sampleRateHertz = 16000,
    this.enableWordConfidence = true,
    this.enableAutomaticPunctuation = true,
  });

  Map<String, dynamic> toJson() => {
    "encoding": encoding.value,
    "sample_rate_hertz": sampleRateHertz,
    "user_l1": userL1,
    "user_l2": userL2,
    "enable_word_confidence": enableWordConfidence,
    "enable_automatic_punctuation": enableAutomaticPunctuation,
  };
}
