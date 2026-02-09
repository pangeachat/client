import 'dart:convert';

import 'package:fluffychat/pangea/choreographer/igc/igc_response_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/models/base_request_model.dart';
import 'package:fluffychat/pangea/common/models/llm_feedback_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IGCRequestModel with BaseRequestModel {
  final String fullText;
  final bool enableIT;
  final bool enableIGC;
  final String userId;
  final List<PreviousMessage> prevMessages;
  final List<LLMFeedbackModel<IGCResponseModel>> feedback;

  @override
  String get userCefr => MatrixState
      .pangeaController.userController.profile.userSettings.cefrLevel.string;

  @override
  String get userL1 => MatrixState.pangeaController.userController.userL1Code!;

  @override
  String get userL2 => MatrixState.pangeaController.userController.userL2Code!;

  const IGCRequestModel({
    required this.fullText,
    required this.enableIGC,
    required this.enableIT,
    required this.userId,
    required this.prevMessages,
    this.feedback = const [],
  });

  /// Creates a copy of this request with optional feedback.
  IGCRequestModel copyWithFeedback(
    List<LLMFeedbackModel<IGCResponseModel>> newFeedback,
  ) =>
      IGCRequestModel(
        fullText: fullText,
        enableIGC: enableIGC,
        enableIT: enableIT,
        userId: userId,
        prevMessages: prevMessages,
        feedback: newFeedback,
      );

  Map<String, dynamic> toJson() {
    final json = {
      ModelKey.fullText: fullText,
      ModelKey.userL1: userL1,
      ModelKey.userL2: userL2,
      ModelKey.enableIT: enableIT,
      ModelKey.enableIGC: enableIGC,
      ModelKey.userId: userId,
      ModelKey.prevMessages:
          jsonEncode(prevMessages.map((x) => x.toJson()).toList()),
    };
    if (feedback.isNotEmpty) {
      json[ModelKey.feedback] = feedback.map((f) => f.toJson()).toList();
    }
    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! IGCRequestModel) return false;

    return fullText.trim() == other.fullText.trim() &&
        fullText == other.fullText &&
        userL1 == other.userL1 &&
        userL2 == other.userL2 &&
        enableIT == other.enableIT &&
        userId == other.userId &&
        _feedbackHash == other._feedbackHash;
  }

  /// Hash of feedback content for cache differentiation
  int get _feedbackHash =>
      feedback.isEmpty ? 0 : Object.hashAll(feedback.map((f) => f.feedback));

  @override
  int get hashCode => Object.hash(
        fullText.trim(),
        userL1,
        userL2,
        enableIT,
        enableIGC,
        userId,
        _feedbackHash,
      );
}

/// Previous text/audio message sent in chat
/// Contain message content, sender, and timestamp
class PreviousMessage {
  final String content;
  final String sender;
  final DateTime timestamp;

  const PreviousMessage({
    required this.content,
    required this.sender,
    required this.timestamp,
  });

  factory PreviousMessage.fromJson(Map<String, dynamic> json) =>
      PreviousMessage(
        content: json[ModelKey.prevContent] ?? "",
        sender: json[ModelKey.prevSender] ?? "",
        timestamp: json[ModelKey.prevTimestamp] == null
            ? DateTime.now()
            : DateTime.parse(json[ModelKey.prevTimestamp]),
      );

  Map<String, dynamic> toJson() => {
        ModelKey.prevContent: content,
        ModelKey.prevSender: sender,
        ModelKey.prevTimestamp: timestamp.toIso8601String(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! PreviousMessage) return false;

    return content == other.content &&
        sender == other.sender &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode {
    return Object.hash(
      content,
      sender,
      timestamp,
    );
  }
}
