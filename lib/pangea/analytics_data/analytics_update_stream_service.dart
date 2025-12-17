import 'dart:async';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LevelUpdate {
  final int prevLevel;
  final int newLevel;

  LevelUpdate({
    required this.prevLevel,
    required this.newLevel,
  });
}

// enum AnalyticsUpdateType { server, local }

class AnalyticsUpdate {
  // final AnalyticsUpdateType type;
  final List<OneConstructUse> newConstructs;
  // final bool isLogout;
  final String? targetID;

  AnalyticsUpdate(
    // this.type,
    this.newConstructs, {
    // this.isLogout = false,
    this.targetID,
  });
}

class AnalyticsUpdateStreamService {
  final AnalyticsDataService dataService;

  StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  StreamController<String> activityAnalyticsStream =
      StreamController<String>.broadcast();

  StreamController<Set<ConstructIdentifier>> unlockedConstructsStream =
      StreamController<Set<ConstructIdentifier>>.broadcast();

  StreamController<LevelUpdate> levelUpdateStream =
      StreamController<LevelUpdate>.broadcast();

  AnalyticsUpdateStreamService(this.dataService);

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
    final update = AnalyticsStreamUpdate(
      points: analyticsUpdate.newConstructs.fold<int>(
        0,
        (previousValue, element) => previousValue + element.xp,
      ),
      targetID: analyticsUpdate.targetID,
    );

    if (analyticsUpdate.newConstructs.isEmpty) {
      constructUpdateStream.add(update);
      return;
    }

    final morphIds = analyticsUpdate.newConstructs
        .where((c) => c.constructType == ConstructTypeEnum.morph)
        .map((c) => c.identifier)
        .toSet();

    final prevData = await dataService.derivedData;
    final prevMorphs = await dataService.getConstructUses(morphIds.toList());

    await dataService.updateLocalAnalytics(analyticsUpdate);

    final newMorphs = await dataService.getConstructUses(morphIds.toList());
    final newUnlockedMorphs = morphIds.where((id) {
      final prevPoints = prevMorphs[id]?.points ?? 0;
      final newPoints = newMorphs[id]?.points ?? 0;
      return prevPoints < 30 && newPoints >= 30;
    }).toSet();

    final data = await dataService.derivedData;
    if (prevData.level < data.level) {
      // do not await this - it's not necessary for this to finish
      // before the function completes and it blocks the UI
      _onLevelUp(prevData.level, data.level);
    }

    if (prevData.level > data.level) {
      _onLevelDown(data.level, prevData.level, data.totalXP);
    }

    if (newUnlockedMorphs.isNotEmpty) {
      _onUnlockMorphLemmas(newUnlockedMorphs);
    }

    constructUpdateStream.add(update);

    // Update public profile each time that new analytics are added.
    // If the level hasn't changed, this will not send an update to the server.
    // Do this on all updates (not just on level updates) to account for cases
    // of target language updates being missed (https://github.com/pangeachat/client/issues/2006)
    MatrixState.pangeaController.userController.updateAnalyticsProfile(
      level: data.level,
    );
  }

  void _onLevelUp(final int lowerLevel, final int upperLevel) {
    levelUpdateStream.add(
      LevelUpdate(
        prevLevel: lowerLevel,
        newLevel: upperLevel,
      ),
    );
  }

  Future<void> _onLevelDown(
    final int lowerLevel,
    final int upperLevel,
    final int totalXP,
  ) async {
    final offset =
        DerivedAnalyticsDataModel.calculateXpWithLevel(lowerLevel) - totalXP;
    await MatrixState.pangeaController.userController.addXPOffset(offset);
    final newOffset =
        MatrixState.pangeaController.userController.analyticsProfile!.xpOffset!;

    await dataService.updateXPOffset(newOffset);
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
}
