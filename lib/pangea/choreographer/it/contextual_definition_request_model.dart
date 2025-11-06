import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class ContextualDefinitionRequestModel {
  final String fullText;
  final String word;
  final String feedbackLang;
  final String fullTextLang;
  final String wordLang;

  const ContextualDefinitionRequestModel({
    required this.fullText,
    required this.word,
    required this.feedbackLang,
    required this.fullTextLang,
    required this.wordLang,
  });

  Map<String, dynamic> toJson() => {
        ModelKey.fullText: fullText,
        ModelKey.word: word,
        ModelKey.lang: feedbackLang,
        ModelKey.fullTextLang: fullTextLang,
        ModelKey.wordLang: wordLang,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextualDefinitionRequestModel &&
          runtimeType == other.runtimeType &&
          fullText == other.fullText &&
          word == other.word &&
          feedbackLang == other.feedbackLang &&
          fullTextLang == other.fullTextLang &&
          wordLang == other.wordLang;

  @override
  int get hashCode =>
      fullText.hashCode ^
      word.hashCode ^
      feedbackLang.hashCode ^
      fullTextLang.hashCode ^
      wordLang.hashCode;
}
