import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';

class CefrMatchResult {
  final Color? chipColor;
  final IconData? icon;
  final String? message;

  const CefrMatchResult({this.chipColor, this.icon, this.message});

  static const none = CefrMatchResult();
}

CefrMatchResult computeCefrMatch({
  required BuildContext context,
  required LanguageLevelTypeEnum? userLevel,
  required LanguageLevelTypeEnum courseLevel,
  required String courseLanguage,
  required String? userLanguage,
}) {
  if (userLevel == null ||
      userLanguage == null ||
      userLanguage != courseLanguage) {
    return CefrMatchResult.none;
  }

  final diff = courseLevel.storageInt - userLevel.storageInt;
  final absDiff = diff.abs();

  return CefrMatchResult(
    chipColor: absDiff == 0
        ? AppConfig.success
        : absDiff == 1
        ? AppConfig.gold
        : AppConfig.error,
    icon: absDiff == 0 ? Icons.check : Icons.warning_amber_outlined,
    message: absDiff == 0
        ? L10n.of(context).cefrLevelMatch
        : diff > 0
        ? L10n.of(context).cefrLevelAbove
        : L10n.of(context).cefrLevelBelow,
  );
}
