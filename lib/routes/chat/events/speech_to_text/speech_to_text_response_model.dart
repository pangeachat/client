import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' show Logs;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

/// Tolerance belongs where untrusted data ENTERS, and a defect in one field
/// must never cost a field that does not depend on it.
///
/// A speech provider's response is untrusted in exactly the way room content
/// is, and the parse below used to couple every field to every other one. A
/// missing `word`, a non-numeric `confidence`, a NaN, a single non-map entry in
/// `word_timings` -- any of them threw, the throw propagated out of the whole
/// response parse, and the one caller that catches it marks the chunk FAILED
/// and counts it lost. So one malformed timing entry cost up to ninety seconds
/// of somebody's speech. Timings are what POSITION the words; they must never
/// be able to destroy them.
///
/// So the fields BESIDE the text degrade to their absent value, and the fields
/// that ARE the text still fail the parse. Those are not the same choice, and
/// the difference is what the failure would claim. A transcript we cannot read
/// leaves nothing to save, and reporting that chunk as SILENCE would be a
/// statement about the speaker produced entirely from our own parse failure --
/// the exact mistake `capture_refused` exists to prevent, one layer down. A
/// chunk that fails is counted as lost, which is what actually happened.
///
/// "Beside" means beside in the LIST too, not only beside in the object. The
/// call path reads the first usable transcript and nothing else, so a sibling
/// result or a sibling alternative it never looks at must not be able to take
/// down the one it does. Those are DROPPED.
///
/// Dropping is not the same as degrading to empty, and the difference is what
/// the failure would CLAIM. A response that arrived carrying content, none of
/// which we could read, still fails the parse: reporting that chunk as SILENCE
/// would be a statement about the speaker produced entirely from our own parse
/// failure, which is the exact mistake `capture_refused` exists to prevent one
/// layer down. A chunk that fails is counted as lost, which is what happened.
///
/// A response that genuinely carried nothing is a different thing again, and
/// parses fine. `results: []` is the frozen exhausted-fallback answer, and a
/// result with `transcripts: []` is a provider that found nothing sayable.
/// Those are answers, not failures.

/// A finite number, or null.
///
/// `is num` alone is not enough: NaN and infinity are numbers to it and then
/// throw from `round()` and `toInt()`, which is how a provider's NaN reached
/// the catch that marks a chunk lost.
num? _finite(Object? value) => value is num && value.isFinite ? value : null;

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
    //
    // Still a hard cast, because `results` is the payload container: a response
    // with no readable container at all is not an answer about anybody.
    final raw = json['results'] as List;

    final results = <SpeechToTextResult>[];
    for (final entry in raw) {
      final result = SpeechToTextResult.fromJson(entry);
      // Dropped, not fatal. Nothing on the call path reads past the first
      // usable transcript, so a malformed second result used to destroy a
      // perfectly good first one -- and with it up to ninety seconds of speech.
      if (result != null) results.add(result);
    }

    // Content arrived and none of it could be read. Keeping the empty list here
    // would read downstream as the provider finding nothing sayable, which is
    // silence -- a claim about the speaker sourced entirely from our own
    // failure. It fails instead, and the chunk is counted lost.
    if (results.isEmpty && raw.isNotEmpty) {
      throw const FormatException(
        'No readable result in the speech-to-text response',
      );
    }

    return SpeechToTextResponseModel(
      results: results,
      // Provenance, not content. A non-string here used to throw and take the
      // transcript with it.
      service: json['service'] is String ? json['service'] as String : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    "results": results.map((e) => e.toJson()).toList(),
    if (service != null) "service": service,
  };

  /// [useType] says where the speech came from. It defaults to a voice message
  /// because that is the only caller that predates calls; a call passes `pvc`,
  /// which scores identically and also counts as speaking.
  List<OneConstructUse> constructs(
    String roomId,
    String eventId, [
    ConstructUseTypeEnum useType = ConstructUseTypeEnum.pvm,
  ]) {
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
      constructs.addAll(token.allUses(useType, metadata, useType.pointValue));
    }
    return constructs;
  }
}

class SpeechToTextResult {
  final List<Transcript> transcripts;

  SpeechToTextResult({required this.transcripts});

  /// One result, or null when nothing in it can be read.
  ///
  /// Null rather than throwing, so the caller above drops it and the readable
  /// results still stand. A result whose `transcripts` list is EMPTY is not
  /// unreadable -- it is a provider that found nothing sayable, which is an
  /// answer, and it survives as one.
  static SpeechToTextResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final entries = raw['transcripts'];
    if (entries is! List) return null;

    final transcripts = <Transcript>[];
    for (final entry in entries) {
      final transcript = Transcript.fromJson(entry);
      // A malformed second alternative is one the call path never reads.
      if (transcript != null) transcripts.add(transcript);
    }
    if (transcripts.isEmpty && entries.isNotEmpty) return null;
    return SpeechToTextResult(transcripts: transcripts);
  }

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

  /// One transcript alternative, or null when its TEXT cannot be read.
  ///
  /// The text is the only field left that can make an alternative unreadable;
  /// everything beside it degrades to its absent value instead. Null rather
  /// than throwing so a malformed alternative is dropped and the readable ones
  /// still stand -- an empty text is not unreadable, it is a real answer that
  /// `hasUsableTranscript` already reports as unusable.
  static Transcript? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['transcript'];
    if (text is! String) return null;

    return Transcript(
      text: text,
      confidence: _confidence(raw[ChoreoConstants.confidence]),
      sttTokens: _tokens(raw['stt_tokens']),
      // Empty means UNKNOWN, and a caller that writes a language tag has to
      // treat it as such rather than putting an empty tag on the wire.
      langCode: raw[ModelKey.langCode] is String
          ? raw[ModelKey.langCode] as String
          : '',
      wordsPerHr: _finite(raw['words_per_hr'])?.toInt(),
      wordTimings: _timings(raw['word_timings']),
    );
  }

  /// The transcript's own confidence, on the frozen 0..100 scale.
  ///
  /// Over 100 is the double-scaled shape this has always divided by 100. That
  /// division produces a DOUBLE, which was then assigned straight to an int
  /// field -- so a confidence of 250 threw a type error out of the parse and
  /// cost the chunk its words, and an absent or non-numeric one threw before
  /// the comparison even ran. Rounded and clamped now, like the per-word one,
  /// so a conforming 0..100 int still passes through untouched.
  static int _confidence(Object? raw) {
    final value = _finite(raw);
    if (value == null) return 0;
    return (value <= 100 ? value : value / 100).round().clamp(0, 100);
  }

  /// The word timings, or null when any one of them cannot be read.
  ///
  /// ALL or nothing. Keeping the readable ones would hand the segment builder
  /// a list that no longer accounts for the whole transcript -- which is not a
  /// finer cut of it but a partial one, and a partial one moves where the cuts
  /// land. Null is a state the whole pipeline already handles: it yields one
  /// segment for the chunk, with no position claimed for it.
  static List<WordTiming>? _timings(Object? raw) {
    if (raw is! List) return null;
    final timings = <WordTiming>[];
    for (final entry in raw) {
      final timing = WordTiming.fromJson(entry);
      if (timing == null) return null;
      timings.add(timing);
    }
    return timings;
  }

  /// The tokens, or empty when any one of them cannot be read.
  ///
  /// All or nothing for the same reason the timings are: a partial token list
  /// under-credits the learner silently. Empty is a state this app already
  /// produces and already handles -- the skip-tokenize send path embeds
  /// `stt_tokens: []` deliberately, and every consumer gates on
  /// [SpeechToTextResponseModel.hasUsableTokens].
  ///
  /// Caught HERE rather than by loosening [STTToken] or [PangeaToken]. Those
  /// are read by the toolbar, by practice and by analytics, and making them
  /// tolerant would let a real contract break degrade quietly everywhere
  /// instead of failing where somebody would notice. Tolerance belongs at the
  /// boundary untrusted data crosses, and nowhere further in.
  static List<STTToken> _tokens(Object? raw) {
    if (raw is! List) return const [];
    try {
      return [for (final entry in raw) STTToken.fromJson(entry)];
    } catch (e, s) {
      Logs().w(
        'A speech-to-text token could not be read; tokens dropped',
        e,
        s,
      );
      return const [];
    }
  }

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

  /// One timing entry, or null when it cannot be read.
  ///
  /// Nullable rather than throwing, and a static method rather than a factory
  /// because a factory cannot return null. See the note at the top of this
  /// file: an entry we cannot parse costs the timings, never the words.
  static WordTiming? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final word = raw['word'];
    final confidence = _finite(raw['confidence']);
    if (word is! String || confidence == null) return null;

    // Present-but-unreadable is NOT the same as absent. The contract allows a
    // provider to omit a timestamp and this app is careful never to fabricate
    // one, so reading a garbage timestamp as the omission would quietly hand
    // the cutter a timing set that still reconstructs the text and still
    // cuts -- at boundaries taken from a number nobody sent.
    final start = raw['start_time_ms'];
    final end = raw['end_time_ms'];
    if ((start != null && _finite(start) == null) ||
        (end != null && _finite(end) == null)) {
      return null;
    }

    return WordTiming(
      word: word,
      startTimeMs: (start as num?)?.toInt(),
      endTimeMs: (end as num?)?.toInt(),
      confidence: _normalizeConfidence(confidence),
    );
  }

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
