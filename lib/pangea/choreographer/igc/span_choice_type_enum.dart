import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum SpanChoiceTypeEnum {
  suggestion,
  alt,
  distractor,
  @Deprecated('Use suggestion instead')
  bestCorrection,
  @Deprecated('Use suggestion instead')
  bestAnswer,
}

extension SpanChoiceExt on SpanChoiceTypeEnum {
  String get name {
    switch (this) {
      case SpanChoiceTypeEnum.suggestion:
        return "suggestion";
      case SpanChoiceTypeEnum.alt:
        return "alt";
      case SpanChoiceTypeEnum.bestCorrection:
        return "bestCorrection";
      case SpanChoiceTypeEnum.distractor:
        return "distractor";
      case SpanChoiceTypeEnum.bestAnswer:
        return "bestAnswer";
    }
  }

  bool get isSuggestion =>
      this == SpanChoiceTypeEnum.suggestion ||
      this == SpanChoiceTypeEnum.bestCorrection ||
      this == SpanChoiceTypeEnum.bestAnswer;

  String defaultFeedback(BuildContext context) {
    switch (this) {
      case SpanChoiceTypeEnum.suggestion:
      case SpanChoiceTypeEnum.bestCorrection:
        return L10n.of(context).bestCorrectionFeedback;
      case SpanChoiceTypeEnum.alt:
      case SpanChoiceTypeEnum.bestAnswer:
        return L10n.of(context).bestAnswerFeedback;
      case SpanChoiceTypeEnum.distractor:
        return L10n.of(context).distractorFeedback;
    }
  }

  IconData get icon {
    switch (this) {
      case SpanChoiceTypeEnum.suggestion:
      case SpanChoiceTypeEnum.bestCorrection:
      case SpanChoiceTypeEnum.alt:
      case SpanChoiceTypeEnum.bestAnswer:
        return Icons.check_circle;
      case SpanChoiceTypeEnum.distractor:
        return Icons.cancel;
    }
  }

  Color get color {
    switch (this) {
      case SpanChoiceTypeEnum.suggestion:
      case SpanChoiceTypeEnum.bestCorrection:
        return Colors.green;
      case SpanChoiceTypeEnum.alt:
      case SpanChoiceTypeEnum.bestAnswer:
        return Colors.green;
      case SpanChoiceTypeEnum.distractor:
        return Colors.red;
    }
  }
}
