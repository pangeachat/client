import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin AnalyticsUpdater<T extends StatefulWidget> on State<T> {
  StreamSubscription? _analyticsSubscription;

  @override
  void initState() {
    super.initState();
    final updater = Matrix.of(context).analyticsDataService.updateDispatcher;
    _analyticsSubscription =
        updater.constructUpdateStream.stream.listen(_onAnalyticsUpdate);
  }

  @override
  void dispose() {
    _analyticsSubscription?.cancel();
    super.dispose();
  }

  Future<void> addAnalytics(
    List<OneConstructUse> constructs,
    String? targetId,
  ) =>
      Matrix.of(context).analyticsDataService.updateService.addAnalytics(
            targetId,
            constructs,
          );

  void _onAnalyticsUpdate(AnalyticsStreamUpdate update) {
    if (update.targetID != null) {
      OverlayUtil.showPointsGained(update.targetID!, update.points, context);
    }
  }
}
