class LanguageDetectionRequest {
  final String text;
  final String? senderl1;
  final String? senderl2;

  LanguageDetectionRequest({
    required this.text,
    this.senderl1,
    this.senderl2,
  });

  Map<String, dynamic> toJson() {
    return {
      'full_text': text,
      'sender_l1': senderl1,
      'sender_l2': senderl2,
    };
  }
}
