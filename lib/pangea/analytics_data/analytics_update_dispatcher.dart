import 'dart:async';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/analytics_update_events.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';

class LevelUpdate {
  final int prevLevel;
  final int newLevel;

  LevelUpdate({
    required this.prevLevel,
    required this.newLevel,
  });
}

class AnalyticsUpdate {
  final List<OneConstructUse> addedConstructs;
  final ConstructIdentifier? blockedConstruct;
  final String? targetID;

  AnalyticsUpdate(
    this.addedConstructs, {
    this.blockedConstruct,
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

  final StreamController<Set<ConstructIdentifier>> newConstructsStream =
      StreamController<Set<ConstructIdentifier>>.broadcast();

  final StreamController<MapEntry<ConstructIdentifier, UserSetLemmaInfo>>
      _lemmaInfoUpdateStream = StreamController<
          MapEntry<ConstructIdentifier, UserSetLemmaInfo>>.broadcast();

  AnalyticsUpdateDispatcher(this.dataService);

  void dispose() {
    constructUpdateStream.close();
    activityAnalyticsStream.close();
    unlockedConstructsStream.close();
    levelUpdateStream.close();
    _lemmaInfoUpdateStream.close();
  }

  Stream<UserSetLemmaInfo> lemmaUpdateStream(
    ConstructIdentifier constructId,
  ) =>
      _lemmaInfoUpdateStream.stream
          .where((update) => update.key == constructId)
          .map((update) => update.value);

  void sendActivityAnalyticsUpdate(
    String activityAnalytics,
  ) =>
      activityAnalyticsStream.add(activityAnalytics);

  void sendLemmaInfoUpdate(
    ConstructIdentifier constructId,
    UserSetLemmaInfo lemmaInfo,
  ) =>
      _lemmaInfoUpdateStream.add(MapEntry(constructId, lemmaInfo));

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
      case final ConstructBlockedEvent e:
        _onBlockedConstruct(e.blockedConstruct);
        break;
      case final NewConstructsEvent e:
        _onNewConstruct(e.newConstructs);
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

  void _onBlockedConstruct(ConstructIdentifier constructId) {
    final update = AnalyticsStreamUpdate(
      blockedConstruct: constructId,
    );
    constructUpdateStream.add(update);
  }

  void _onNewConstruct(Set<ConstructIdentifier> constructIds) {
    if (constructIds.isEmpty) return;
    newConstructsStream.add(constructIds);
  }
}
