import 'dart:async';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_events.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class LevelUpdate {
  final int prevLevel;
  final int newLevel;

  LevelUpdate({
    required this.prevLevel,
    required this.newLevel,
  });
}

class AnalyticsUpdate {
  final List<OneConstructUse> newConstructs;
  final String? targetID;

  AnalyticsUpdate(
    this.newConstructs, {
    this.targetID,
  });
}

class AnalyticsUpdateDispatcher {
  final AnalyticsDataService dataService;

  final StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  final StreamController<String> activityAnalyticsStream =
      StreamController<String>.broadcast();

  final StreamController<Set<ConstructIdentifier>> unlockedConstructsStream =
      StreamController<Set<ConstructIdentifier>>.broadcast();

  final StreamController<LevelUpdate> levelUpdateStream =
      StreamController<LevelUpdate>.broadcast();

  AnalyticsUpdateDispatcher(this.dataService);

  void dispose() {
    constructUpdateStream.close();
    activityAnalyticsStream.close();
    unlockedConstructsStream.close();
    levelUpdateStream.close();
  }

  void sendActivityAnalyticsUpdate(
    String activityAnalytics,
  ) =>
      activityAnalyticsStream.add(activityAnalytics);

  Future<void> sendConstructAnalyticsUpdate(
    AnalyticsUpdate analyticsUpdate,
  ) async {
    final events = await dataService.updateLocalAnalytics(analyticsUpdate);
    for (final event in events) {
      _dispatch(event);
    }
  }

  void _dispatch(AnalyticsUpdateEvent event) {
    switch (event) {
      case final LevelUpEvent e:
        _onLevelUp(e.from, e.to);
        break;
      case final MorphUnlockedEvent e:
        _onUnlockMorphLemmas(e.unlocked);
        break;
      case final XPGainedEvent e:
        _onXPGained(e.points, e.targetID);
        break;
    }
  }

  void _onLevelUp(final int lowerLevel, final int upperLevel) {
    levelUpdateStream.add(
      LevelUpdate(
        prevLevel: lowerLevel,
        newLevel: upperLevel,
      ),
    );
  }

  void _onUnlockMorphLemmas(Set<ConstructIdentifier> unlocked) {
    const excludedLemmas = {'not_proper'};

    final filtered = {
      for (final id in unlocked)
        if (!excludedLemmas.contains(id.lemma.toLowerCase())) id,
    };

    if (filtered.isNotEmpty) {
      unlockedConstructsStream.add(filtered);
    }
  }

  void _onXPGained(int points, String? targetID) {
    final update = AnalyticsStreamUpdate(
      points: points,
      targetID: targetID,
    );
    constructUpdateStream.add(update);
  }
}
