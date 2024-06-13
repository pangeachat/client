import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/models/practice_activities.dart/multiple_choice_activity_model.dart';

class ConstructIdentifier {
  final String lemma;
  final ConstructType type;

  ConstructIdentifier({required this.lemma, required this.type});

  factory ConstructIdentifier.fromJson(Map<String, dynamic> json) {
    return ConstructIdentifier(
      lemma: json['lemma'] as String,
      type: ConstructType.values.firstWhere(
        (e) => e.string == json['type'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lemma': lemma,
      'type': type.string,
    };
  }
}

enum ActivityType { multipleChoice, freeResponse, listening, speaking }

class CandidateMessage {
  final String msgId;
  final String roomId;
  final String text;

  CandidateMessage({
    required this.msgId,
    required this.roomId,
    required this.text,
  });

  factory CandidateMessage.fromJson(Map<String, dynamic> json) {
    return CandidateMessage(
      msgId: json['msg_id'] as String,
      roomId: json['room_id'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'msg_id': msgId,
      'room_id': roomId,
      'text': text,
    };
  }
}

enum PracticeActivityMode { focus, srs }

extension on PracticeActivityMode {
  String get value {
    switch (this) {
      case PracticeActivityMode.focus:
        return 'focus';
      case PracticeActivityMode.srs:
        return 'srs';
    }
  }
}

class PracticeActivityRequest {
  final PracticeActivityMode? mode;
  final List<ConstructIdentifier>? targetConstructs;
  final List<CandidateMessage>? candidateMessages;
  final List<String>? userIds;
  final ActivityType? activityType;
  final int? numActivities;

  PracticeActivityRequest({
    this.mode,
    this.targetConstructs,
    this.candidateMessages,
    this.userIds,
    this.activityType,
    this.numActivities,
  });

  factory PracticeActivityRequest.fromJson(Map<String, dynamic> json) {
    return PracticeActivityRequest(
      mode: PracticeActivityMode.values.firstWhere(
        (e) => e.value == json['mode'],
      ),
      targetConstructs: (json['target_constructs'] as List?)
          ?.map((e) => ConstructIdentifier.fromJson(e as Map<String, dynamic>))
          .toList(),
      candidateMessages: (json['candidate_msgs'] as List)
          .map((e) => CandidateMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      userIds: (json['user_ids'] as List?)?.map((e) => e as String).toList(),
      activityType: ActivityType.values.firstWhere(
        (e) => e.toString().split('.').last == json['activity_type'],
      ),
      numActivities: json['num_activities'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode?.value,
      'target_constructs': targetConstructs?.map((e) => e.toJson()).toList(),
      'candidate_msgs': candidateMessages?.map((e) => e.toJson()).toList(),
      'user_ids': userIds,
      'activity_type': activityType?.toString().split('.').last,
      'num_activities': numActivities,
    };
  }

  // override operator == and hashCode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PracticeActivityRequest &&
        other.mode == mode &&
        other.targetConstructs == targetConstructs &&
        other.candidateMessages == candidateMessages &&
        other.userIds == userIds &&
        other.activityType == activityType &&
        other.numActivities == numActivities;
  }

  @override
  int get hashCode {
    return mode.hashCode ^
        targetConstructs.hashCode ^
        candidateMessages.hashCode ^
        userIds.hashCode ^
        activityType.hashCode ^
        numActivities.hashCode;
  }
}

class FreeResponse {
  final String question;
  final String correctAnswer;
  final String gradingGuide;

  FreeResponse({
    required this.question,
    required this.correctAnswer,
    required this.gradingGuide,
  });

  factory FreeResponse.fromJson(Map<String, dynamic> json) {
    return FreeResponse(
      question: json['question'] as String,
      correctAnswer: json['correct_answer'] as String,
      gradingGuide: json['grading_guide'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'correct_answer': correctAnswer,
      'grading_guide': gradingGuide,
    };
  }
}

class Listening {
  final String audioUrl;
  final String text;

  Listening({required this.audioUrl, required this.text});

  factory Listening.fromJson(Map<String, dynamic> json) {
    return Listening(
      audioUrl: json['audio_url'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audio_url': audioUrl,
      'text': text,
    };
  }
}

class Speaking {
  final String text;

  Speaking({required this.text});

  factory Speaking.fromJson(Map<String, dynamic> json) {
    return Speaking(
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
    };
  }
}

class PracticeActivityModel {
  final List<ConstructIdentifier> tgtConstructs;
  final String langCode;
  final String msgId;
  final ActivityType activityType;
  final MultipleChoice? multipleChoice;
  final Listening? listening;
  final Speaking? speaking;
  final FreeResponse? freeResponse;

  PracticeActivityModel({
    required this.tgtConstructs,
    required this.langCode,
    required this.msgId,
    required this.activityType,
    this.multipleChoice,
    this.listening,
    this.speaking,
    this.freeResponse,
  });

  factory PracticeActivityModel.fromJson(Map<String, dynamic> json) {
    return PracticeActivityModel(
      tgtConstructs: (json['tgt_constructs'] as List)
          .map((e) => ConstructIdentifier.fromJson(e as Map<String, dynamic>))
          .toList(),
      langCode: json['lang_code'] as String,
      msgId: json['msg_id'] as String,
      activityType: ActivityType.values.firstWhere(
        (e) => e.toString().split('.').last == json['activity_type'],
      ),
      multipleChoice: json['multiple_choice'] != null
          ? MultipleChoice.fromJson(
              json['multiple_choice'] as Map<String, dynamic>,
            )
          : null,
      listening: json['listening'] != null
          ? Listening.fromJson(json['listening'] as Map<String, dynamic>)
          : null,
      speaking: json['speaking'] != null
          ? Speaking.fromJson(json['speaking'] as Map<String, dynamic>)
          : null,
      freeResponse: json['free_response'] != null
          ? FreeResponse.fromJson(json['free_response'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tgt_constructs': tgtConstructs.map((e) => e.toJson()).toList(),
      'lang_code': langCode,
      'msg_id': msgId,
      'activity_type': activityType.toString().split('.').last,
      'multiple_choice': multipleChoice?.toJson(),
      'listening': listening?.toJson(),
      'speaking': speaking?.toJson(),
      'free_response': freeResponse?.toJson(),
    };
  }
}
