import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_level_enum.dart';
import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_events.dart';
import 'package:fluffychat/pangea/lemmas/user_set_lemma_info.dart';

class LevelUpdate {
  final int prevLevel;
  final int newLevel;

  const LevelUpdate({required this.prevLevel, required this.newLevel});
}

class AnalyticsUpdate {
  final List<OneConstructUse> addedConstructs;
  final String? targetID;

  const AnalyticsUpdate(this.addedConstructs, {this.targetID});
}

class ConstructLevelUpdate {
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final String? targetID;

  const ConstructLevelUpdate({
    required this.constructId,
    required this.level,
    this.targetID,
  });
}

class UnlockedConstructsUpdate {
  final Set<ConstructIdentifier> constructs;
  final String? targetId;

  const UnlockedConstructsUpdate({required this.constructs, this.targetId});
}

class AnalyticsUpdateDispatcher {
  final AnalyticsDataService dataService;

  final StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  final StreamController<String?> activityAnalyticsStream =
      StreamController<String?>.broadcast();

  final StreamController<UnlockedConstructsUpdate> unlockedConstructsStream =
      StreamController<UnlockedConstructsUpdate>.broadcast();

  final StreamController<LevelUpdate> levelUpdateStream =
      StreamController<LevelUpdate>.broadcast();

  final StreamController<Set<ConstructIdentifier>> newConstructsStream =
      StreamController<Set<ConstructIdentifier>>.broadcast();

  final StreamController<ConstructLevelUpdate> constructLevelUpdateStream =
      StreamController<ConstructLevelUpdate>.broadcast();

  final StreamController<MapEntry<ConstructIdentifier, UserSetLemmaInfo>>
  _lemmaInfoUpdateStream =
      StreamController<
        MapEntry<ConstructIdentifier, UserSetLemmaInfo>
      >.broadcast();

  AnalyticsUpdateDispatcher(this.dataService);

  void dispose() {
    constructUpdateStream.close();
    activityAnalyticsStream.close();
    unlockedConstructsStream.close();
    levelUpdateStream.close();
    constructLevelUpdateStream.close();
    _lemmaInfoUpdateStream.close();
  }

  Stream<UserSetLemmaInfo> lemmaUpdateStream(ConstructIdentifier constructId) =>
      _lemmaInfoUpdateStream.stream
          .where((update) => update.key == constructId)
          .map((update) => update.value);

  void sendActivityAnalyticsUpdate(String? activityAnalytics) {
    if (_dropIfDisposed(activityAnalyticsStream, 'activity analytics')) return;
    activityAnalyticsStream.add(activityAnalytics);
  }

  /// True, having left a breadcrumb, when [stream] was closed by [dispose].
  ///
  /// A send lands here after the account is torn down: logging out while
  /// `_initAnalytics` is still running, or while a sync's bulk update is in
  /// flight, closes the streams first and the late completion sends anyway.
  /// Nothing listens by then, so the send is dropped. It used to be reported
  /// as an error, once per user per such logout -- and the report's
  /// `isLoggedIn` datum went through the null-asserting analytics client, so
  /// once the store was closed the report itself threw (#8780).
  bool _dropIfDisposed(StreamController<Object?> stream, String what) {
    if (!stream.isClosed) return false;
    Sentry.addBreadcrumb(
      Breadcrumb(
        message:
            'AnalyticsUpdateDispatcher: dropped $what update after dispose',
      ),
    );
    return true;
  }

  void sendLemmaInfoUpdate(
    ConstructIdentifier constructId,
    UserSetLemmaInfo lemmaInfo,
  ) => _lemmaInfoUpdateStream.add(MapEntry(constructId, lemmaInfo));

  Future<void> sendBlockedConstructsUpdate(
    Set<ConstructIdentifier> blockedConstructs,
    String language,
  ) async {
    await dataService.updateBlockedConstructs(blockedConstructs, language);
    constructUpdateStream.add(
      AnalyticsStreamUpdate(blockedConstructs: blockedConstructs),
    );
  }

  Future<void> sendRestoredConstructsUpdate(
    Set<ConstructIdentifier> restoredConstructs,
    String language,
  ) async {
    await dataService.updateRestoredConstructs(restoredConstructs, language);
    constructUpdateStream.add(
      AnalyticsStreamUpdate(restoredConstructs: restoredConstructs),
    );
  }

  void sendEmptyAnalyticsUpdate() {
    if (_dropIfDisposed(constructUpdateStream, 'analytics')) return;
    constructUpdateStream.add(AnalyticsStreamUpdate());
  }

  Future<void> sendServerAnalyticsUpdate(
    List<ConstructAnalyticsEvent> events,
    String language,
  ) async {
    await dataService.updateServerAnalytics(events, language);
    sendEmptyAnalyticsUpdate();
  }

  Future<void> sendLocalAnalyticsUpdate(
    AnalyticsUpdate analyticsUpdate,
    String language,
  ) async {
    final events = await dataService.updateLocalAnalytics(
      analyticsUpdate,
      language,
    );
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
        _onUnlockMorphLemmas(e.unlocked, e.targetId);
        break;
      case final XPGainedEvent e:
        _onXPGained(e.points, e.totalPoints, e.targetID);
        break;
      case final ConstructLevelUpEvent e:
        _onConstructLevelUp(e.constructId, e.level, e.targetID);
        break;
      case final NewConstructsEvent e:
        _onNewConstruct(e.newConstructs);
        break;
    }
  }

  void _onLevelUp(final int lowerLevel, final int upperLevel) {
    levelUpdateStream.add(
      LevelUpdate(prevLevel: lowerLevel, newLevel: upperLevel),
    );
  }

  void _onUnlockMorphLemmas(
    Set<ConstructIdentifier> unlocked,
    String? targetId,
  ) {
    const excludedLemmas = {'not_proper'};

    final filtered = {
      for (final id in unlocked)
        if (!excludedLemmas.contains(id.lemma.toLowerCase())) id,
    };

    if (filtered.isNotEmpty) {
      final update = UnlockedConstructsUpdate(
        constructs: filtered,
        targetId: targetId,
      );
      unlockedConstructsStream.add(update);
    }
  }

  void _onXPGained(int points, int totalPoints, String? targetID) {
    final update = AnalyticsStreamUpdate(
      points: points,
      totalPoints: totalPoints,
      targetID: targetID,
    );
    constructUpdateStream.add(update);
  }

  void _onConstructLevelUp(
    ConstructIdentifier constructId,
    ConstructLevelEnum level,
    String? targetID,
  ) {
    constructLevelUpdateStream.add(
      ConstructLevelUpdate(
        constructId: constructId,
        level: level,
        targetID: targetID,
      ),
    );
  }

  void _onNewConstruct(Set<ConstructIdentifier> constructIds) {
    if (constructIds.isEmpty) return;
    newConstructsStream.add(constructIds);
  }
}
