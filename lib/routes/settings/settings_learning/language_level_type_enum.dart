import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

enum LanguageLevelTypeEnum {
  preA1,
  a1,
  a2,
  b1,
  b2,
  c1,
  c2;

  // Makes enum a string
  String get string {
    switch (this) {
      case LanguageLevelTypeEnum.preA1:
        return 'PREA1';
      case LanguageLevelTypeEnum.a1:
        return 'A1';
      case LanguageLevelTypeEnum.a2:
        return 'A2';
      case LanguageLevelTypeEnum.b1:
        return 'B1';
      case LanguageLevelTypeEnum.b2:
        return 'B2';
      case LanguageLevelTypeEnum.c1:
        return 'C1';
      case LanguageLevelTypeEnum.c2:
        return 'C2';
    }
  }

  // Makes enum an int
  int get storageInt {
    switch (this) {
      case LanguageLevelTypeEnum.preA1:
        return 0;
      case LanguageLevelTypeEnum.a1:
        return 1;
      case LanguageLevelTypeEnum.a2:
        return 2;
      case LanguageLevelTypeEnum.b1:
        return 3;
      case LanguageLevelTypeEnum.b2:
        return 4;
      case LanguageLevelTypeEnum.c1:
        return 5;
      case LanguageLevelTypeEnum.c2:
        return 6;
    }
  }

  static LanguageLevelTypeEnum fromInt(int? value) {
    switch (value) {
      case 0:
        return LanguageLevelTypeEnum.preA1;
      case 1:
        return LanguageLevelTypeEnum.a1;
      case 2:
        return LanguageLevelTypeEnum.a2;
      case 3:
        return LanguageLevelTypeEnum.b1;
      case 4:
        return LanguageLevelTypeEnum.b2;
      case 5:
        return LanguageLevelTypeEnum.c1;
      case 6:
        return LanguageLevelTypeEnum.c2;
      default:
        return LanguageLevelTypeEnum.a1;
    }
  }

  static LanguageLevelTypeEnum fromString(String? value) {
    switch (value) {
      case 'PREA1':
      case 'PRE-A1':
      case 'Pre-A1':
        return LanguageLevelTypeEnum.preA1;
      case 'A1':
        return LanguageLevelTypeEnum.a1;
      case 'A2':
        return LanguageLevelTypeEnum.a2;
      case 'B1':
        return LanguageLevelTypeEnum.b1;
      case 'B2':
        return LanguageLevelTypeEnum.b2;
      case 'C1':
        return LanguageLevelTypeEnum.c1;
      case 'C2':
        return LanguageLevelTypeEnum.c2;
      default:
        return LanguageLevelTypeEnum.a1;
    }
  }

  /// The compact CEFR code used wherever the level is shown as a chip or in a
  /// short sentence — the map's Level pill and its fallback notice. `PREA1`
  /// reads as `Pre-A1`; every other level is its own code. The dropdown
  /// entries use the fuller ACTFL+CEFR [title] instead (e.g. "Novice Mid
  /// (A1)").
  String get shortLabel =>
      this == LanguageLevelTypeEnum.preA1 ? 'Pre-A1' : string;

  String title(BuildContext context) {
    final L10n copy = L10n.of(context);
    switch (this) {
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

  String description(BuildContext context) {
    final L10n copy = L10n.of(context);
    switch (this) {
      case LanguageLevelTypeEnum.preA1:
        return copy.languageLevelPreA1Desc;
      case LanguageLevelTypeEnum.a1:
        return copy.languageLevelA1Desc;
      case LanguageLevelTypeEnum.a2:
        return copy.languageLevelA2Desc;
      case LanguageLevelTypeEnum.b1:
        return copy.languageLevelB1Desc;
      case LanguageLevelTypeEnum.b2:
        return copy.languageLevelB2Desc;
      case LanguageLevelTypeEnum.c1:
        return copy.languageLevelC1Desc;
      case LanguageLevelTypeEnum.c2:
        return copy.languageLevelC2Desc;
    }
  }

  /// The level in [available] closest to [target] — the map's fallback when the
  /// learner picks a level no activity carries. Returns null when [available]
  /// is empty (nothing to fall back to) or already contains [target] (no
  /// fallback needed). Ties resolve **downward**: with content one level above
  /// and one below, the easier one is the safer thing to hand a learner who
  /// asked for something below both.
  static LanguageLevelTypeEnum? nearestTo(
    LanguageLevelTypeEnum target,
    Set<LanguageLevelTypeEnum> available,
  ) {
    if (available.isEmpty || available.contains(target)) return null;
    final sorted = available.toList()
      ..sort((a, b) {
        final byDistance = (a.storageInt - target.storageInt).abs().compareTo(
          (b.storageInt - target.storageInt).abs(),
        );
        return byDistance != 0
            ? byDistance
            : a.storageInt.compareTo(b.storageInt);
      });
    return sorted.first;
  }

  static Set<LanguageLevelTypeEnum> bandAtOrBelow(
    LanguageLevelTypeEnum? level,
  ) {
    if (level == null) return LanguageLevelTypeEnum.values.toSet();
    return LanguageLevelTypeEnum.values
        .where((l) => l.storageInt <= level.storageInt)
        .toSet();
  }
}
