import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/phonetic_transcription/pt_v2_models.dart';

class TokenInfoFeedbackRequestData {
  final String userId;
  final String? roomId;
  final String? fullText;
  final String detectedLanguage;
  final List<PangeaToken> tokens;
  final int selectedToken;
  final LemmaInfoResponse lemmaInfo;
  final PTRequest? ptRequest;
  final PTResponse? ptResponse;
  final String wordCardL1;

  TokenInfoFeedbackRequestData({
    required this.userId,
    required this.detectedLanguage,
    required this.tokens,
    required this.selectedToken,
    required this.lemmaInfo,
    required this.wordCardL1,
    this.ptRequest,
    this.ptResponse,
    this.roomId,
    this.fullText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenInfoFeedbackRequestData &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          roomId == other.roomId &&
          fullText == other.fullText &&
          detectedLanguage == other.detectedLanguage &&
          selectedToken == other.selectedToken &&
          lemmaInfo == other.lemmaInfo &&
          ptRequest == other.ptRequest &&
          ptResponse == other.ptResponse &&
          wordCardL1 == other.wordCardL1;

  @override
  int get hashCode =>
      userId.hashCode ^
      roomId.hashCode ^
      fullText.hashCode ^
      detectedLanguage.hashCode ^
      selectedToken.hashCode ^
      lemmaInfo.hashCode ^
      ptRequest.hashCode ^
      ptResponse.hashCode ^
      wordCardL1.hashCode;
}

class TokenInfoFeedbackRequest {
  final TokenInfoFeedbackRequestData data;
  final String userFeedback;

  TokenInfoFeedbackRequest({required this.data, required this.userFeedback});

  Map<String, dynamic> toJson() {
    return {
      'user_id': data.userId,
      'room_id': data.roomId,
      'full_text': data.fullText,
      'detected_language': data.detectedLanguage,
      'tokens': data.tokens.map((token) => token.toJson()).toList(),
      'selected_token': data.selectedToken,
      'lemma_info': data.lemmaInfo.toJson(),
      'pt_request': data.ptRequest?.toJson(),
      'pt_response': data.ptResponse?.toJson(),
      'user_feedback': userFeedback,
      'word_card_l1': data.wordCardL1,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenInfoFeedbackRequest &&
          runtimeType == other.runtimeType &&
          data == other.data &&
          userFeedback == other.userFeedback;

  @override
  int get hashCode => data.hashCode ^ userFeedback.hashCode;
}
