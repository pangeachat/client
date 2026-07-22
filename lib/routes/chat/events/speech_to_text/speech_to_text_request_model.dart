import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/routes/chat/events/speech_to_text/audio_encoding_enum.dart';

class SpeechToTextRequestModel extends BaseRequest {
  final Uint8List audioContent;
  final SpeechToTextAudioConfigModel config;
  final Event? audioEvent;
  final bool? mock;

  /// When true, the choreographer returns the ASR transcript text (+ word
  /// timings) WITHOUT running the LLM tokenizer -- the voice-send fast path.
  /// A skip-tokenize response is a distinct cache slot (see [storageKey]) and
  /// must never share one with a full tokenized response for the same audio.
  final bool skipTokenize;

  SpeechToTextRequestModel({
    required this.audioContent,
    required this.config,
    this.audioEvent,
    this.mock,
    this.skipTokenize = false,
  });

  /// A full sha256 digest of the audio content. The R0 key sampled only the
  /// length + first 10 bytes, which collide across different short recordings
  /// that share a fixed codec header (WAV/OGG magic bytes) -- firing STT at
  /// record-stop could then serve a stale transcript for a different take.
  /// A content digest keys on the whole recording, mirroring choreo's
  /// `sha256_signature`.
  String get _audioDigest => sha256.convert(audioContent).toString();

  @override
  String get storageKey =>
      '$_audioDigest|${jsonEncode(config.toJson())}|$skipTokenize';

  @override
  Map<String, dynamic> toJson() => {
    "config": config.toJson(),
    "audio_content": base64Encode(audioContent),
    // OMIT when false so the flag-OFF request bytes are byte-identical to
    // today's (choreo defaults skip_tokenize to false); it is still part of
    // storageKey/==/hashCode so the cache never mixes the two paths.
    if (skipTokenize) "skip_tokenize": true,
    if (mock != null) ModelKey.mock: mock,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpeechToTextRequestModel) return false;

    return listEquals(audioContent, other.audioContent) &&
        config == other.config &&
        skipTokenize == other.skipTokenize;
  }

  @override
  int get hashCode => Object.hash(_audioDigest, config.hashCode, skipTokenize);
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
    ModelKey.userL1: userL1,
    ModelKey.userL2: userL2,
    "enable_word_confidence": enableWordConfidence,
    "enable_automatic_punctuation": enableAutomaticPunctuation,
  };
}
