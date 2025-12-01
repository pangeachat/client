// record the options that the user selected
// note that this is not the same as the correct answer
// the user might have selected multiple options before
// finding the answer

import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/practice_activities/activity_type_enum.dart';
import 'package:fluffychat/pangea/practice_activities/practice_record_repo.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';

class PracticeRecord {
  late List<ActivityRecordResponse> responses;

  PracticeRecord({
    List<ActivityRecordResponse>? responses,
    DateTime? timestamp,
  }) {
    if (responses == null) {
      this.responses = List<ActivityRecordResponse>.empty(growable: true);
    } else {
      this.responses = responses;
    }
  }

  factory PracticeRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    return PracticeRecord(
      responses: (json['responses'] as List)
          .map(
            (e) => ActivityRecordResponse.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      timestamp: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'responses': responses.map((e) => e.toJson()).toList(),
    };
  }

  int get completeResponses =>
      responses.where((element) => element.isCorrect).length;

  /// get the latest response index according to the response timeStamp
  /// sort the responses by timestamp and get the index of the last response
  ActivityRecordResponse? get latestResponse {
    if (responses.isEmpty) {
      return null;
    }
    responses.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return responses[responses.length - 1];
  }

  bool alreadyHasMatchResponse(
    ConstructIdentifier cId,
    String text,
  ) =>
      responses.any(
        (element) => element.cId == cId && element.text == text,
      );

  /// [target] needed for saving the record, little funky
  /// [cId] identifies the construct in the case of match activities which have multiple
  /// [text] is the user's response
  /// [score] > 0 means correct, otherwise is incorrect
  void addResponse({
    required ConstructIdentifier cId,
    required PracticeTarget target,
    required String text,
    required double score,
  }) {
    responses.add(
      ActivityRecordResponse(
        cId: cId,
        text: text,
        audioBytes: null,
        imageBytes: null,
        timestamp: DateTime.now(),
        score: score,
      ),
    );

    try {
      PracticeRecordRepo.set(target, this);
    } catch (e) {
      debugger(when: kDebugMode);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PracticeRecord &&
        other.responses.length == responses.length &&
        List.generate(
          responses.length,
          (index) => responses[index] == other.responses[index],
        ).every((element) => element);
  }

  @override
  int get hashCode => responses.hashCode;
}

class ActivityRecordResponse {
  /// the cId of the construct that the user attached their response to
  /// ie. in the "I like the dog" if the user erroneously attaches a dog emoji to the word like
  /// then the cId is that of 'like
  ConstructIdentifier cId;
  // the user's response
  // has nullable string, nullable audio bytes, nullable image bytes, and timestamp
  final String? text;
  final Uint8List? audioBytes;
  final Uint8List? imageBytes;
  final DateTime timestamp;
  final double score;

  ActivityRecordResponse({
    required this.cId,
    this.text,
    this.audioBytes,
    this.imageBytes,
    required this.score,
    required this.timestamp,
  });

  bool get isCorrect => score > 0;

  //TODO - differentiate into different activity types
  ConstructUseTypeEnum useType(ActivityTypeEnum aType) =>
      isCorrect ? aType.correctUse : aType.incorrectUse;

  factory ActivityRecordResponse.fromJson(Map<String, dynamic> json) {
    return ActivityRecordResponse(
      cId: ConstructIdentifier.fromJson(json['cId'] as Map<String, dynamic>),
      text: json['text'] as String?,
      audioBytes: json['audio'] as Uint8List?,
      imageBytes: json['image'] as Uint8List?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      // this has a default of 1 to make this backwards compatible
      // score was added later and is not present in all records
      // currently saved to Matrix
      score: json['score'] ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cId': cId.toJson(),
      'text': text,
      'audio': audioBytes,
      'image': imageBytes,
      'timestamp': timestamp.toIso8601String(),
      'score': score.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ActivityRecordResponse &&
        other.text == text &&
        other.audioBytes == audioBytes &&
        other.imageBytes == imageBytes &&
        other.timestamp == timestamp &&
        other.score == score &&
        other.cId == cId;
  }

  @override
  int get hashCode =>
      text.hashCode ^
      audioBytes.hashCode ^
      imageBytes.hashCode ^
      timestamp.hashCode ^
      score.hashCode ^
      cId.hashCode;
}
