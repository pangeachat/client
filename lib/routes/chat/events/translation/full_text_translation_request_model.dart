import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/models/llm_feedback_model.dart';
import 'package:fluffychat/routes/chat/choreographer/choreo_constants.dart';
import 'package:fluffychat/routes/chat/events/translation/full_text_translation_response_model.dart';

class FullTextTranslationRequestModel {
  final String text;
  final String? srcLang;
  final String tgtLang;
  final String userL1;
  final String userL2;
  final bool? deepL;
  final int? offset;
  final int? length;
  final List<LLMFeedbackModel<FullTextTranslationResponseModel>>? feedback;
  final bool? mock;

  const FullTextTranslationRequestModel({
    required this.text,
    this.srcLang,
    required this.tgtLang,
    required this.userL2,
    required this.userL1,
    this.deepL = false,
    this.offset,
    this.length,
    this.feedback,
    this.mock,
  });

  Map<String, dynamic> toJson() => {
    ChoreoConstants.text: text,
    ChoreoConstants.srcLang: srcLang,
    ChoreoConstants.tgtLang: tgtLang,
    ModelKey.userL2: userL2,
    ModelKey.userL1: userL1,
    ChoreoConstants.deepL: deepL,
    ModelKey.offset: offset,
    ModelKey.length: length,
    if (feedback != null)
      ChoreoConstants.feedback: feedback!.map((f) => f.toJson()).toList(),
    if (mock != null) ModelKey.mock: mock,
  };

  String get storageKey =>
      "$text-$srcLang-$tgtLang-$userL1-$userL2-$deepL-$offset-$length-${feedback?.join('-')}";
}
