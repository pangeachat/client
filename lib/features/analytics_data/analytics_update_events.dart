import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';

sealed class AnalyticsUpdateEvent {
  const AnalyticsUpdateEvent();
}

class LevelUpEvent extends AnalyticsUpdateEvent {
  final int from;
  final int to;

  const LevelUpEvent(this.from, this.to);
}

class MorphUnlockedEvent extends AnalyticsUpdateEvent {
  final Set<ConstructIdentifier> unlocked;
  final String? targetId;

  const MorphUnlockedEvent(this.unlocked, this.targetId);
}

class ConstructLevelUpEvent extends AnalyticsUpdateEvent {
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final String? targetID;

  const ConstructLevelUpEvent(this.constructId, this.level, this.targetID);
}

class XPGainedEvent extends AnalyticsUpdateEvent {
  /// XP actually gained: the per-construct delta, capped at the flower
  /// threshold. This is what total XP / level math is based on.
  final int points;

  /// Raw point value of the uses the update added, ignoring the flower cap.
  /// Only the XP gain/loss animation reads this — a use on a flower-level
  /// (capped) construct has [points] of 0 but still animates (#7756).
  final int totalPoints;

  final String? targetID;

  const XPGainedEvent(this.points, this.totalPoints, this.targetID);

  /// Build the event for one analytics update: [points] is the capped delta
  /// computed by the caller; [totalPoints] is summed from the added uses.
  factory XPGainedEvent.fromUses(
    List<OneConstructUse> addedUses,
    int cappedPoints,
    String? targetID,
  ) => XPGainedEvent(
    cappedPoints,
    addedUses.fold<int>(0, (sum, use) => sum + use.xp),
    targetID,
  );
}

class NewConstructsEvent extends AnalyticsUpdateEvent {
  final Set<ConstructIdentifier> newConstructs;

  const NewConstructsEvent(this.newConstructs);
}
