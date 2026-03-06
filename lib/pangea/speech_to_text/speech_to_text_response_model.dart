import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';

class SpeechToTextResponseModel {
  final List<SpeechToTextResult> results;

  SpeechToTextResponseModel({required this.results});

  Transcript get transcript => results.first.transcripts.first;

  String get langCode => results.first.transcripts.first.langCode;

  factory SpeechToTextResponseModel.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as List;
    if (results.isEmpty) {
      throw Exception('SpeechToTextModel.fromJson: results is empty');
    }
    return SpeechToTextResponseModel(
      results: (json['results'] as List)
          .map((e) => SpeechToTextResult.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    "results": results.map((e) => e.toJson()).toList(),
  };

  List<OneConstructUse> constructs(String roomId, String eventId) {
    final List<OneConstructUse> constructs = [];
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
    confidence: json['confidence'] <= 100
        ? json['confidence']
        : json['confidence'] / 100,
    sttTokens: (json['stt_tokens'] as List)
        .map((e) => STTToken.fromJson(e))
        .toList(),
    langCode: json['lang_code'],
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
    // debugPrint('STTToken.fromJson: $json');
    return STTToken(
      token: PangeaToken.fromJson(json['token']),
      startTime: json['start_time'] != null
          ? Duration(milliseconds: (json['start_time'] * 1000).round())
          : null,
      endTime: json['end_time'] != null
          ? Duration(milliseconds: (json['end_time'] * 1000).round())
          : null,
      confidence: json['confidence'],
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
