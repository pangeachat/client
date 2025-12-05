import 'dart:convert';

import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';

class IGCRequestModel {
  final String fullText;
  final String userL1;
  final String userL2;
  final GenderEnum userGender;
  final bool enableIT;
  final bool enableIGC;
  final String userId;
  final List<PreviousMessage> prevMessages;

  const IGCRequestModel({
    required this.fullText,
    required this.userL1,
    required this.userL2,
    required this.userGender,
    required this.enableIGC,
    required this.enableIT,
    required this.userId,
    required this.prevMessages,
  });

  Map<String, dynamic> toJson() => {
        ModelKey.fullText: fullText,
        ModelKey.userL1: userL1,
        ModelKey.userL2: userL2,
        ModelKey.userGender: userGender.string,
        "enable_it": enableIT,
        "enable_igc": enableIGC,
        ModelKey.userId: userId,
        ModelKey.prevMessages:
            jsonEncode(prevMessages.map((x) => x.toJson()).toList()),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! IGCRequestModel) return false;

    return fullText.trim() == other.fullText.trim() &&
        fullText == other.fullText &&
        userL1 == other.userL1 &&
        userL2 == other.userL2 &&
        userGender == other.userGender &&
        enableIT == other.enableIT &&
        userId == other.userId;
  }

  @override
  int get hashCode => Object.hash(
        fullText.trim(),
        userL1,
        userL2,
        userGender,
        enableIT,
        enableIGC,
        userId,
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
