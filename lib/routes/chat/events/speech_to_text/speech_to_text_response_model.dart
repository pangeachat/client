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

  /// Whether this response carries a usable transcript AND non-empty tokens.
  /// The tokenizer-decouple send path embeds a text-usable transcript with
  /// `stt_tokens: []`; the token consumers (analytics, toolbar selection) need
  /// this stronger gate so they prefer a later token-rich representation over
  /// the provisional empty-token embed (see `selectUsableStt(preferTokens:)`).
  bool get hasUsableTokens =>
      hasUsableTranscript &&
      results.first.transcripts.first.sttTokens.isNotEmpty;

  Transcript get transcript => results.first.transcripts.first;

  /// Returns a copy identical to this response EXCEPT the first transcript's
  /// `stt_tokens`, replaced by [sttTokens]. The single mutation the background
  /// tokenize performs on the skip-tokenize base response: every other field
  /// (service, confidence, wordsPerHr, word_timings, langCode) is preserved so
  /// the enriched result is byte-identical to the base apart from its tokens.
  SpeechToTextResponseModel withFirstTranscriptTokens(
    List<STTToken> sttTokens,
  ) {
    if (results.isEmpty || results.first.transcripts.isEmpty) {
      throw StateError(
        'withFirstTranscriptTokens requires a usable transcript',
      );
    }
    final firstResult = results.first;
    final newFirstTranscript = firstResult.transcripts.first.copyWith(
      sttTokens: sttTokens,
    );
    final newResults = [
      SpeechToTextResult(
        transcripts: [newFirstTranscript, ...firstResult.transcripts.skip(1)],
      ),
      ...results.skip(1),
    ];
    return SpeechToTextResponseModel(results: newResults, service: service);
  }

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

  /// Provider word-level timings, carried through on the skip-tokenize path
  /// (tokens get null timings, so the raw ASR timings are the only ones kept).
  /// Nullable and OMIT-WHEN-NULL in [toJson] so a normal (non-decoupled)
  /// response serializes byte-identically to before this field existed.
  final List<WordTiming>? wordTimings;

  Transcript({
    required this.text,
    required this.confidence,
    required this.sttTokens,
    required this.langCode,
    required this.wordsPerHr,
    this.wordTimings,
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
    wordTimings: (json['word_timings'] as List?)
        ?.map((e) => WordTiming.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Transcript copyWith({List<STTToken>? sttTokens}) => Transcript(
    text: text,
    confidence: confidence,
    sttTokens: sttTokens ?? this.sttTokens,
    langCode: langCode,
    wordsPerHr: wordsPerHr,
    wordTimings: wordTimings,
  );

  Map<String, dynamic> toJson() => {
    "transcript": text,
    "confidence": confidence,
    "stt_tokens": sttTokens.map((e) => e.toJson()).toList(),
    "lang_code": langCode,
    "words_per_hr": wordsPerHr,
    if (wordTimings != null)
      "word_timings": wordTimings!.map((e) => e.toJson()).toList(),
  };

  Color get color => confidence > 80 ? AppConfig.success : AppConfig.warning;
}

/// Raw ASR word timing carried on the skip-tokenize path. Timestamps are
/// nullable (never fabricated -- some providers omit them); confidence is an
/// integer 0..100 the choreographer normalizes from the provider's 0-1 float
/// (a valid `0` is preserved, not nulled). Contract frozen with the choreo
/// `WordTiming` schema (see PHASE1-SPEC D3).
class WordTiming {
  final String word;
  final int? startTimeMs;
  final int? endTimeMs;

  /// Integer 0..100, NEVER null -- the choreographer normalizes every
  /// provider's 0-1 float to this scale (a valid `0` is preserved), so the
  /// frozen §5 contract makes it required and bounded. Only the timestamps are
  /// nullable (some providers omit them; they are never fabricated).
  final int confidence;

  WordTiming({
    required this.word,
    required this.confidence,
    this.startTimeMs,
    this.endTimeMs,
  });

  /// Normalizes any incoming confidence to the frozen contract: a rounded int
  /// clamped to 0..100. Guards against a malformed upstream value (a fraction,
  /// or an out-of-range number) ever leaking a contract violation into the app.
  static int _normalizeConfidence(num raw) => raw.round().clamp(0, 100);

  factory WordTiming.fromJson(Map<String, dynamic> json) => WordTiming(
    word: json['word'] as String,
    startTimeMs: (json['start_time_ms'] as num?)?.toInt(),
    endTimeMs: (json['end_time_ms'] as num?)?.toInt(),
    confidence: _normalizeConfidence(json['confidence'] as num),
  );

  Map<String, dynamic> toJson() => {
    "word": word,
    "start_time_ms": startTimeMs,
    "end_time_ms": endTimeMs,
    "confidence": confidence,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WordTiming &&
        other.word == word &&
        other.startTimeMs == startTimeMs &&
        other.endTimeMs == endTimeMs &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(word, startTimeMs, endTimeMs, confidence);
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
