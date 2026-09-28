import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// [FakePangeaController] plus what the activity chat controller reads back
/// through the static: the subscription gate, and the analytics dispatcher it
/// subscribes to on construction.
class ActivityChatTestPangeaController implements PangeaController {
  ActivityChatTestPangeaController({bool subscribed = true})
    : subscriptionController = _FakeSubscriptionController(subscribed);

  final PangeaController _delegate = FakePangeaController(userL1Code: 'en');

  @override
  UserController get userController => _delegate.userController;

  @override
  final SubscriptionController subscriptionController;

  @override
  final MatrixState matrixState = _FakeMatrixState();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSubscriptionController implements SubscriptionController {
  _FakeSubscriptionController(this.showSubscriptionGatedContent);

  @override
  final bool showSubscriptionGatedContent;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixState implements MatrixState {
  @override
  final AnalyticsDataService analyticsDataService = _FakeAnalyticsDataService();

  // `State` mixes in Diagnosticable, whose toString takes a named argument
  // that `Object.toString` lacks — the one member noSuchMethod can't cover.
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeMatrixState';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAnalyticsDataService implements AnalyticsDataService {
  @override
  late final AnalyticsUpdateDispatcher updateDispatcher =
      AnalyticsUpdateDispatcher(this);

  @override
  bool get isInitializing => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
