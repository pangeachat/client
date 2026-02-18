import 'dart:math';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class DerivedAnalyticsDataModel {
  final int _totalXP;
  final int offset;

  DerivedAnalyticsDataModel({int totalXP = 0, this.offset = 0})
    : _totalXP = totalXP;

  int get totalXP => _totalXP + offset;

  int get level => calculateLevelWithXp(totalXP);

  // the minimum XP required for a given level
  int get _minXPForLevel => calculateXpWithLevel(level);

  // the minimum XP required for the next level
  int get minXPForNextLevel => calculateXpWithLevel(level + 1);

  // the progress within the current level as a percentage (0.0 to 1.0)
  double get levelProgress {
    final progress =
        (totalXP - _minXPForLevel) / (minXPForNextLevel - _minXPForLevel);
    return progress >= 0 ? progress : 0;
  }

  static const double D = 300;

  static int calculateXpWithLevel(int level) {
    // If level <= 1, XP should be 0 or negative by this math.
    // In practice, you might clamp it to 0:
    if (level <= 1) {
      return 0;
    }

    // Convert level to double for the math
    final double lc = level.toDouble();

    // XP from the inverse formula:
    final double xpDouble = (D / 8.0) * (2.0 * pow(lc - 1.0, 2.0) - 1.0);

    final int xp = xpDouble.ceil();
    return (xp < 0) ? 0 : xp;
  }

  static int calculateLevelWithXp(int totalXP) {
    final doubleScore = (1 + sqrt((1 + (8.0 * totalXP / D)) / 2.0));
    if (!doubleScore.isNaN && doubleScore.isFinite) {
      return doubleScore.floor();
    } else {
      ErrorHandler.logError(
        e: "Calculated level in Nan or Infinity",
        data: {"totalXP": totalXP, "level": doubleScore},
      );
      return 1;
    }
  }

  DerivedAnalyticsDataModel copyWithOffset(int offset) {
    return DerivedAnalyticsDataModel(totalXP: _totalXP, offset: offset);
  }

  DerivedAnalyticsDataModel copyWithTotalXP(int totalXP) {
    return DerivedAnalyticsDataModel(totalXP: totalXP, offset: offset);
  }

  DerivedAnalyticsDataModel addXP(int xpToAdd) {
    return DerivedAnalyticsDataModel(
      totalXP: _totalXP + xpToAdd,
      offset: offset,
    );
  }

  factory DerivedAnalyticsDataModel.fromJson(Map<String, dynamic> map) {
    return DerivedAnalyticsDataModel(
      totalXP: map['total_xp'] ?? 0,
      offset: map['offset'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'total_xp': _totalXP, 'offset': offset};
  }
}
