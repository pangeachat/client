import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

class SpeechToTextResponseModel extends BaseResponse {
  final List<SpeechToTextResult> results;

  /// The ASR provider that produced this transcript (e.g. `google`,
  /// `whisper`). Nullable: older persisted events were written before this
  /// field existed on the wire, so it may be absent on historical reads.
  final String? service;

  SpeechToTextResponseModel({required this.results, this.service});

  /// Whether this response actually carries a usable transcript. Mirrors the
  /// bot's `_is_valid_stt_response` (get_audio_stt.py): a first result with a
  /// first transcript whose text is non-empty. `transcript`/`langCode` below
  /// read `results.first.transcripts.first`, so callers MUST gate on this
  /// before reading them -- an exhausted-fallback (`results: []`) or a
  /// nested-empty response is parseable but not usable, and reading its
  /// transcript would throw.
  bool get hasUsableTranscript =>
      results.isNotEmpty &&
      results.first.transcripts.isNotEmpty &&
      results.first.transcripts.first.text.isNotEmpty;

  Transcript get transcript => results.first.transcripts.first;

  String get langCode => results.first.transcripts.first.langCode;

  factory SpeechToTextResponseModel.fromJson(Map<String, dynamic> json) {
    // An exhausted-fallback choreo response is `{"results": [], ...}` --
    // HTTP 200, not an error. That's a valid, empty transcript, not a parse
    // failure, so it must not throw here (R0-2); the caller decides whether
    // an empty model is usable.
    return SpeechToTextResponseModel(
      results: (json['results'] as List)
          .map((e) => SpeechToTextResult.fromJson(e))
          .toList(),
      service: json['service'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    "results": results.map((e) => e.toJson()).toList(),
    if (service != null) "service": service,
  };

  List<OneConstructUse> constructs(String roomId, String eventId) {
    final List<OneConstructUse> constructs = [];
    // Exhausted-fallback model: nothing was transcribed, so there are no
    // constructs to score. `transcript` assumes at least one result and
    // would throw otherwise.
    if (results.isEmpty) return constructs;
    final metadata = ConstructUseMetaData(
      roomId: roomId,
      eventId: eventId,
      timeStamp: DateTime.now(),
    );
    for (final sstToken in transcript.sttTokens) {
      final token = sstToken.token;
      if (!token.lemma.saveVocab) continue;
      constructs.addAll(
        token.allUses(
          ConstructUseTypeEnum.pvm,
          metadata,
          ConstructUseTypeEnum.pvm.pointValue,
        ),
      );
    }
    return constructs;
  }
}

class SpeechToTextResult {
  final List<Transcript> transcripts;

  SpeechToTextResult({required this.transcripts});

  factory SpeechToTextResult.fromJson(Map<String, dynamic> json) =>
      SpeechToTextResult(
        transcripts: (json['transcripts'] as List)
            .map((e) => Transcript.fromJson(e))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    "transcripts": transcripts.map((e) => e.toJson()).toList(),
  };
}

class Transcript {
  final String text;
  final int confidence;
  final List<STTToken> sttTokens;
  final String langCode;
  final int? wordsPerHr;

  Transcript({
    required this.text,
    required this.confidence,
    required this.sttTokens,
    required this.langCode,
    required this.wordsPerHr,
  });

  /// Returns the number of words per minute rounded to one decimal place.
  double? get wordsPerMinute => wordsPerHr != null ? wordsPerHr! / 60 : null;

  factory Transcript.fromJson(Map<String, dynamic> json) => Transcript(
    text: json['transcript'],
    confidence: json[ChoreoConstants.confidence] <= 100
        ? json[ChoreoConstants.confidence]
        : json[ChoreoConstants.confidence] / 100,
    sttTokens: (json['stt_tokens'] as List)
        .map((e) => STTToken.fromJson(e))
        .toList(),
    langCode: json[ModelKey.langCode],
    wordsPerHr: json['words_per_hr'],
  );

  Map<String, dynamic> toJson() => {
    "transcript": text,
    "confidence": confidence,
    "stt_tokens": sttTokens.map((e) => e.toJson()).toList(),
    "lang_code": langCode,
    "words_per_hr": wordsPerHr,
  };

  Color get color => confidence > 80 ? AppConfig.success : AppConfig.warning;
}

class STTToken {
  final PangeaToken token;
  final Duration? startTime;
  final Duration? endTime;
  final int? confidence;

  STTToken({
    required this.token,
    this.startTime,
    this.endTime,
    this.confidence,
  });

  int get offset => token.text.offset;

  int get length => token.text.length;

  Color color(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  factory STTToken.fromJson(Map<String, dynamic> json) {
    // The choreographer already sends start/end time as integer
    // milliseconds; pass them through as-is (R0-2). Previously this
    // multiplied by 1000, inflating a true 480ms into 480000ms.
    return STTToken(
      token: PangeaToken.fromJson(json['token']),
      startTime: json['start_time'] != null
          ? Duration(milliseconds: (json['start_time'] as num).round())
          : null,
      endTime: json['end_time'] != null
          ? Duration(milliseconds: (json['end_time'] as num).round())
          : null,
      confidence: json[ChoreoConstants.confidence],
    );
  }

  Map<String, dynamic> toJson() => {
    "token": token.toJson(),
    "start_time": startTime?.inMilliseconds,
    "end_time": endTime?.inMilliseconds,
    "confidence": confidence,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! STTToken) return false;

    return token == other.token &&
        startTime == other.startTime &&
        endTime == other.endTime &&
        confidence == other.confidence;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      token.hashCode,
      startTime.hashCode,
      endTime.hashCode,
      confidence.hashCode,
    ]);
  }
}
