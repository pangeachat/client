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
  final int points;
  final String? targetID;

  const XPGainedEvent(this.points, this.targetID);

  /// Build the event for one analytics update from the uses just added.
  ///
  /// Carries the raw point value of the action itself rather than the capped
  /// per-construct XP delta — a use on a flower-level (capped) construct still
  /// animates even though it changes total XP by 0 (#7756).
  factory XPGainedEvent.fromUses(
    List<OneConstructUse> addedUses,
    String? targetID,
  ) => XPGainedEvent(
    addedUses.fold<int>(0, (sum, use) => sum + use.xp),
    targetID,
  );
}

class NewConstructsEvent extends AnalyticsUpdateEvent {
  final Set<ConstructIdentifier> newConstructs;

  const NewConstructsEvent(this.newConstructs);
}
