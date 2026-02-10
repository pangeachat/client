/// Phonetic Transcription v2 models.
///
/// Maps to choreo endpoint `POST /choreo/phonetic_transcription_v2`.
/// Request: [PTRequest] with surface, langCode, userL1, userL2.
/// Response: [PTResponse] with a list of [Pronunciation]s.
library;

class Pronunciation {
  final String transcription;
  final String ttsPhoneme;
  final String? udConditions;

  const Pronunciation({
    required this.transcription,
    required this.ttsPhoneme,
    this.udConditions,
  });

  factory Pronunciation.fromJson(Map<String, dynamic> json) {
    return Pronunciation(
      transcription: json['transcription'] as String,
      ttsPhoneme: json['tts_phoneme'] as String,
      udConditions: json['ud_conditions'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'transcription': transcription,
        'tts_phoneme': ttsPhoneme,
        'ud_conditions': udConditions,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pronunciation &&
          transcription == other.transcription &&
          ttsPhoneme == other.ttsPhoneme &&
          udConditions == other.udConditions;

  @override
  int get hashCode =>
      transcription.hashCode ^ ttsPhoneme.hashCode ^ udConditions.hashCode;
}

class PTRequest {
  final String surface;
  final String langCode;
  final String userL1;
  final String userL2;

  const PTRequest({
    required this.surface,
    required this.langCode,
    required this.userL1,
    required this.userL2,
  });

  factory PTRequest.fromJson(Map<String, dynamic> json) {
    return PTRequest(
      surface: json['surface'] as String,
      langCode: json['lang_code'] as String,
      userL1: json['user_l1'] as String,
      userL2: json['user_l2'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'surface': surface,
        'lang_code': langCode,
        'user_l1': userL1,
        'user_l2': userL2,
      };

  /// Cache key excludes userL2 (doesn't affect pronunciation).
  String get cacheKey => '$surface|$langCode|$userL1';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PTRequest &&
          surface == other.surface &&
          langCode == other.langCode &&
          userL1 == other.userL1 &&
          userL2 == other.userL2;

  @override
  int get hashCode =>
      surface.hashCode ^ langCode.hashCode ^ userL1.hashCode ^ userL2.hashCode;
}

class PTResponse {
  final List<Pronunciation> pronunciations;

  const PTResponse({required this.pronunciations});

  factory PTResponse.fromJson(Map<String, dynamic> json) {
    return PTResponse(
      pronunciations: (json['pronunciations'] as List)
          .map((e) => Pronunciation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'pronunciations': pronunciations.map((p) => p.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PTResponse &&
          const _PronunciationListEquality()
              .equals(pronunciations, other.pronunciations);

  @override
  int get hashCode => const _PronunciationListEquality().hash(pronunciations);
}

/// Deep equality for List<Pronunciation>.
class _PronunciationListEquality {
  const _PronunciationListEquality();

  bool equals(List<Pronunciation> a, List<Pronunciation> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int hash(List<Pronunciation> list) {
    int result = 0;
    for (final p in list) {
      result ^= p.hashCode;
    }
    return result;
  }
}
