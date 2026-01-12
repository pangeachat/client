import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum SpanChoiceTypeEnum {
  bestCorrection,
  distractor,
  bestAnswer,
}

extension SpanChoiceExt on SpanChoiceTypeEnum {
  String get name {
    switch (this) {
      case SpanChoiceTypeEnum.bestCorrection:
        return "bestCorrection";
      case SpanChoiceTypeEnum.distractor:
        return "distractor";
      case SpanChoiceTypeEnum.bestAnswer:
        return "bestAnswer";
    }
  }

  String defaultFeedback(BuildContext context) {
    switch (this) {
      case SpanChoiceTypeEnum.bestCorrection:
        return L10n.of(context).bestCorrectionFeedback;
      case SpanChoiceTypeEnum.distractor:
        return L10n.of(context).distractorFeedback;
      case SpanChoiceTypeEnum.bestAnswer:
        return L10n.of(context).bestAnswerFeedback;
    }
  }

  IconData get icon {
    switch (this) {
      case SpanChoiceTypeEnum.bestCorrection:
        return Icons.check_circle;
      case SpanChoiceTypeEnum.distractor:
        return Icons.cancel;
      case SpanChoiceTypeEnum.bestAnswer:
        return Icons.check_circle;
    }
  }

  Color get color {
    switch (this) {
      case SpanChoiceTypeEnum.bestCorrection:
        return Colors.green;
      case SpanChoiceTypeEnum.distractor:
        return Colors.red;
      case SpanChoiceTypeEnum.bestAnswer:
        return Colors.green;
    }
  }
}
