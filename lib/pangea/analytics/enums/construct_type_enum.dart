import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics/constants/analytics_constants.dart';
import 'package:fluffychat/pangea/analytics/enums/morph_categories_enum.dart';
import 'package:fluffychat/pangea/analytics/enums/parts_of_speech_enum.dart';
import 'package:fluffychat/pangea/analytics/enums/progress_indicators_enum.dart';

enum ConstructTypeEnum {
  /// for vocabulary words
  vocab,

  /// for morphs, actually called "Grammar" in the UI... :P
  morph,
}

extension ConstructExtension on ConstructTypeEnum {
  String get string {
    switch (this) {
      case ConstructTypeEnum.vocab:
        return 'vocab';
      case ConstructTypeEnum.morph:
        return 'morph';
    }
  }

  int get maxXPPerLemma {
    switch (this) {
      case ConstructTypeEnum.vocab:
        return AnalyticsConstants.vocabUseMaxXP;
      case ConstructTypeEnum.morph:
        return AnalyticsConstants.morphUseMaxXP;
    }
  }

  String? getDisplayCopy(String category, BuildContext context) {
    switch (this) {
      case ConstructTypeEnum.morph:
        return getMorphologicalCategoryCopy(category, context);
      case ConstructTypeEnum.vocab:
        return getVocabCategoryName(category, context);
    }
  }

  ProgressIndicatorEnum get indicator {
    switch (this) {
      case ConstructTypeEnum.morph:
        return ProgressIndicatorEnum.morphsUsed;
      case ConstructTypeEnum.vocab:
        return ProgressIndicatorEnum.wordsUsed;
    }
  }
}

class ConstructTypeUtil {
  static ConstructTypeEnum fromString(String? string) {
    switch (string) {
      case 'v':
      case 'vocab':
        return ConstructTypeEnum.vocab;
      case 'm':
      case 'morph':
        return ConstructTypeEnum.morph;
      default:
        debugger(when: kDebugMode);
        return ConstructTypeEnum.vocab;
    }
  }
}
