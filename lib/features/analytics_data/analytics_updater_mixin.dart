import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/routes/chat/gain_points_animation.dart';
import 'package:fluffychat/routes/chat/growth_animation.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin AnalyticsUpdater<T extends StatefulWidget> on State<T> {
  StreamSubscription? _analyticsSubscription;
  StreamSubscription? _constructLevelSubscription;

  @override
  void initState() {
    super.initState();
    final updater = Matrix.of(context).analyticsDataService.updateDispatcher;
    _analyticsSubscription = updater.constructUpdateStream.stream.listen(
      _onAnalyticsUpdate,
    );
    _constructLevelSubscription = updater.constructLevelUpdateStream.stream
        .listen(_onConstructLevelUp);
  }

  @override
  void dispose() {
    _analyticsSubscription?.cancel();
    _constructLevelSubscription?.cancel();
    super.dispose();
  }

  Future<void> addAnalytics(
    List<OneConstructUse> constructs,
    String? targetId,
    String language,
  ) => Matrix.of(context).analyticsDataService.updateService.addAnalytics(
    targetId,
    constructs,
    language,
  );

  void _onAnalyticsUpdate(AnalyticsStreamUpdate update) {
    if (update.targetID != null) {
      PointsGainedAnimation.show(update.targetID!, update.points, context);
    }
  }

  void _onConstructLevelUp(ConstructLevelUpdate update) {
    final targetId = update.targetID;
    if (targetId != null) {
      GrowthAnimation.show(
        context,
        targetId,
        "${targetId}_growth_${update.constructId.string}",
        update.level.icon(24),
      );
    }
  }
}
