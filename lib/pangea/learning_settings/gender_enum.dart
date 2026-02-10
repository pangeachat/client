import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum GenderEnum { unselected, woman, man, other }

extension GenderEnumExtension on GenderEnum {
  String get string {
    switch (this) {
      case GenderEnum.unselected:
        return 'unselected';
      case GenderEnum.woman:
        return 'woman';
      case GenderEnum.man:
        return 'man';
      case GenderEnum.other:
        return 'other';
    }
  }

  static GenderEnum fromString(String? value) {
    switch (value) {
      case 'woman':
        return GenderEnum.woman;
      case 'man':
        return GenderEnum.man;
      case 'other':
        return GenderEnum.other;
      default:
        return GenderEnum.unselected;
    }
  }

  String title(BuildContext context) {
    final L10n l10n = L10n.of(context);
    switch (this) {
      case GenderEnum.unselected:
        return l10n.unselectedGender;
      case GenderEnum.woman:
        return l10n.woman;
      case GenderEnum.man:
        return l10n.man;
      case GenderEnum.other:
        return l10n.otherGender;
    }
  }
}
