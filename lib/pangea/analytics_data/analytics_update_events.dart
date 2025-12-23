import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

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

class XPGainedEvent extends AnalyticsUpdateEvent {
  final int points;
  final String? targetID;
  XPGainedEvent(this.points, this.targetID);
}

class ConstructBlockedEvent extends AnalyticsUpdateEvent {
  final ConstructIdentifier blockedConstruct;
  ConstructBlockedEvent(this.blockedConstruct);
}
