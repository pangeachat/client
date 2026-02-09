import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

sealed class AnalyticsUpdateEvent {}

class LevelUpEvent extends AnalyticsUpdateEvent {
  final int from;
  final int to;
  LevelUpEvent(this.from, this.to);
}

class MorphUnlockedEvent extends AnalyticsUpdateEvent {
  final Set<ConstructIdentifier> unlocked;
  MorphUnlockedEvent(this.unlocked);
}

class ConstructLevelUpEvent extends AnalyticsUpdateEvent {
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final String? targetID;
  ConstructLevelUpEvent(
    this.constructId,
    this.level,
    this.targetID,
  );
}

class XPGainedEvent extends AnalyticsUpdateEvent {
  final int points;
  final String? targetID;
  XPGainedEvent(this.points, this.targetID);
}

class ConstructBlockedEvent extends AnalyticsUpdateEvent {
  final ConstructIdentifier blockedConstruct;
  ConstructBlockedEvent(this.blockedConstruct);
}

class NewConstructsEvent extends AnalyticsUpdateEvent {
  final Set<ConstructIdentifier> newConstructs;
  NewConstructsEvent(this.newConstructs);
}
