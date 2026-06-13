import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class LanguageDetectionRequest {
  final String text;
  final String? senderl1;
  final String? senderl2;
  final bool? mock;

  LanguageDetectionRequest({
    required this.text,
    this.senderl1,
    this.senderl2,
    this.mock,
  });

  Map<String, dynamic> toJson() {
    return {
      ModelKey.fullText: text,
      'sender_l1': senderl1,
      'sender_l2': senderl2,
      if (mock != null) ModelKey.mock: mock,
    };
  }

  @override
  int get hashCode => text.hashCode ^ senderl1.hashCode ^ senderl2.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LanguageDetectionRequest &&
        other.text == text &&
        other.senderl1 == senderl1 &&
        other.senderl2 == senderl2;
  }
}
