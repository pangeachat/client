import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/events/models/content_feedback.dart';

class LemmaInfoResponse implements JsonSerializable {
  final List<String> emoji;
  final String meaning;

  LemmaInfoResponse({
    required this.emoji,
    required this.meaning,
  });

  factory LemmaInfoResponse.fromJson(Map<String, dynamic> json) {
    return LemmaInfoResponse(
      // NOTE: This is a workaround for the fact that the server sometimes sends more than 3 emojis
      emoji: (json['emoji'] as List<dynamic>).map((e) => e as String).toList(),
      meaning: json['meaning'] as String,
    );
  }

  static LemmaInfoResponse get error => LemmaInfoResponse(
        emoji: [],
        meaning: 'ERROR',
      );

  @override
  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'meaning': meaning,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LemmaInfoResponse &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(emoji, other.emoji) &&
          meaning == other.meaning;

  @override
  int get hashCode => const ListEquality().hash(emoji) ^ meaning.hashCode;
}
