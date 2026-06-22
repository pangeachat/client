import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/base_request.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/events/models/language_detection_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

class TokensRequestModel extends BaseRequest {
  /// the text to be tokenized
  String fullText;

  /// if known, [langCode] is the language of of the text
  /// it is used to determine which model to use in tokenizing
  String? langCode;

  /// [senderL1] and [senderL2] are the languages of the sender
  /// if langCode is not known, the [senderL1] and [senderL2] will be used to help determine the language of the text
  /// if langCode is known, [senderL1] and [senderL2] will be used to determine whether the tokens need
  /// pos/mporph tags and whether lemmas are eligible to marked as "save_vocab=true"
  String senderL1;

  /// [senderL1] and [senderL2] are the languages of the sender
  /// if langCode is not known, the [senderL1] and [senderL2] will be used to help determine the language of the text
  /// if langCode is known, [senderL1] and [senderL2] will be used to determine whether the tokens need
  /// pos/mporph tags and whether lemmas are eligible to marked as "save_vocab=true"
  String senderL2;

  bool? mock;

  TokensRequestModel({
    required this.fullText,
    required this.senderL1,
    required this.senderL2,
    this.langCode,
    this.mock,
  });

  @override
  String get storageKey => '$fullText|$senderL1|$senderL2';

  @override
  Map<String, dynamic> toJson() => {
    ModelKey.fullText: fullText,
    ModelKey.userL1: senderL1,
    ModelKey.userL2: senderL2,
    ModelKey.langCode: langCode ?? LanguageKeys.unknownLanguage,
    if (mock != null) ModelKey.mock: mock,
  };

  // override equals and hashcode
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TokensRequestModel &&
        other.fullText == fullText &&
        other.senderL1 == senderL1 &&
        other.senderL2 == senderL2;
  }

  @override
  int get hashCode => fullText.hashCode ^ senderL1.hashCode ^ senderL2.hashCode;
}

class TokensResponseModel extends BaseResponse {
  List<PangeaToken> tokens;
  String lang;
  List<LanguageDetectionModel> detections;

  TokensResponseModel({
    required this.tokens,
    required this.lang,
    required this.detections,
  });

  factory TokensResponseModel.fromJson(Map<String, dynamic> json) {
    final response = TokensResponseModel(
      tokens: (json[ModelKey.tokens] as Iterable)
          .map<PangeaToken>(
            (e) => PangeaToken.fromJson(e as Map<String, dynamic>),
          )
          .toList()
          .cast<PangeaToken>(),
      lang: json[ChoreoConstants.lang],
      detections: (json[ChoreoConstants.allDetections] as Iterable)
          .map<LanguageDetectionModel>(
            (e) => LanguageDetectionModel.fromJson(e as Map<String, dynamic>),
          )
          .toList()
          .cast<LanguageDetectionModel>(),
    );

    if (response.tokens.any((t) => t.pos == 'other')) {
      ErrorHandler.logError(
        e: Exception('Received token with pos "other"'),
        data: {"response": json},
        level: SentryLevel.warning,
      );
    }

    return response;
  }

  @override
  Map<String, dynamic> toJson() => {
    ModelKey.tokens: tokens.map((t) => t.toJson()).toList(),
    ChoreoConstants.lang: lang,
    ChoreoConstants.allDetections: detections.map((d) => d.toJson()).toList(),
  };
}
