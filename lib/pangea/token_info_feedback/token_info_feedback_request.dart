import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';

class TokenInfoFeedbackRequest {
  final String userId;
  final String roomId;
  final String fullText;
  final String detectedLanguage;
  final List<PangeaToken> tokens;
  final int selectedToken;
  final LemmaInfoResponse? lemmaInfo;
  final String? phonetics;
  final String userFeedback;
  final String wordCardL1;

  TokenInfoFeedbackRequest({
    required this.userId,
    required this.roomId,
    required this.fullText,
    required this.detectedLanguage,
    required this.tokens,
    required this.selectedToken,
    this.lemmaInfo,
    this.phonetics,
    required this.userFeedback,
    required this.wordCardL1,
  });

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'room_id': roomId,
      'full_text': fullText,
      'detected_language': detectedLanguage,
      'tokens': tokens.map((token) => token.toJson()).toList(),
      'selected_token': selectedToken,
      'lemma_info': lemmaInfo?.toJson(),
      'phonetics': phonetics,
      'user_feedback': userFeedback,
      'word_card_l1': wordCardL1,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenInfoFeedbackRequest &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          roomId == other.roomId &&
          fullText == other.fullText &&
          detectedLanguage == other.detectedLanguage &&
          selectedToken == other.selectedToken &&
          lemmaInfo == other.lemmaInfo &&
          phonetics == other.phonetics &&
          userFeedback == other.userFeedback &&
          wordCardL1 == other.wordCardL1;

  @override
  int get hashCode =>
      userId.hashCode ^
      roomId.hashCode ^
      fullText.hashCode ^
      detectedLanguage.hashCode ^
      selectedToken.hashCode ^
      lemmaInfo.hashCode ^
      phonetics.hashCode ^
      userFeedback.hashCode ^
      wordCardL1.hashCode;
}
