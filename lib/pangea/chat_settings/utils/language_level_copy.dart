import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class LanguageLevelTextPicker {
  static String languageLevelText(
    BuildContext context,
    LanguageLevelTypeEnum languageLevel,
  ) {
    final L10n copy = L10n.of(context);
    switch (languageLevel) {
      case LanguageLevelTypeEnum.preA1:
        return copy.languageLevelPreA1;
      case LanguageLevelTypeEnum.a1:
        return copy.languageLevelA1;
      case LanguageLevelTypeEnum.a2:
        return copy.languageLevelA2;
      case LanguageLevelTypeEnum.b1:
        return copy.languageLevelB1;
      case LanguageLevelTypeEnum.b2:
        return copy.languageLevelB2;
      case LanguageLevelTypeEnum.c1:
        return copy.languageLevelC1;
      case LanguageLevelTypeEnum.c2:
        return copy.languageLevelC2;
    }
  }
}

class LanguageLevelCopy {
  static String getDescription(String level, L10n l10n) {
    switch (level) {
      case 'PreA1':
        return l10n.languageLevelPreA1Desc;
      case 'A1':
        return l10n.languageLevelA1Desc;
      case 'A2':
        return l10n.languageLevelA2Desc;
      case 'B1':
        return l10n.languageLevelB1Desc;
      case 'B2':
        return l10n.languageLevelB2Desc;
      case 'C1':
        return l10n.languageLevelC1Desc;
      case 'C2':
        return l10n.languageLevelC2Desc;
      default:
        return '';
    }
  }
}
