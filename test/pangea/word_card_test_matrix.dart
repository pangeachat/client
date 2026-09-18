import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// A [Matrix] host for pumping the word card. Skips `initMatrix()` and serves
/// what the card reads back through [MatrixState]: an analytics service that
/// never finishes initializing (so no database is opened), a subscription
/// controller that shows gated content, and a user controller with an L1 —
/// plus an [accessToken] when a test wants the card's repos to reach a
/// `MockClient` rather than fail on the missing token.
class WordCardTestMatrix extends Matrix {
  const WordCardTestMatrix({
    super.key,
    required super.clients,
    required super.store,
    required super.child,
    this.accessToken,
  });

  final String? accessToken;

  @override
  MatrixState createState() => _WordCardTestMatrixState();
}

class _WordCardTestMatrixState extends MatrixState {
  final AnalyticsDataService _service = _FakeAnalyticsDataService();

  @override
  // ignore: must_call_super
  void initState() {
    // `initMatrix` normally assigns this; the new-token lookup reads the
    // analytics service back through it.
    MatrixState.pangeaController = _WordCardTestController(
      this,
      accessToken: (widget as WordCardTestMatrix).accessToken,
    );
  }

  @override
  AnalyticsDataService get analyticsDataService => _service;
}

/// [FakePangeaController] plus the two controllers this surface reads back
/// through the static: the word card asks the subscription controller whether
/// to render its content, and the TTS path asks the user controller for the L2.
class _WordCardTestController implements PangeaController {
  _WordCardTestController(this.matrixState, {String? accessToken})
    : _delegate = FakePangeaController(
        userL1Code: 'en',
        accessToken: accessToken,
      );

  @override
  final MatrixState matrixState;

  final PangeaController _delegate;

  @override
  UserController get userController => _delegate.userController;

  @override
  final SubscriptionController subscriptionController =
      _FakeSubscriptionController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSubscriptionController implements SubscriptionController {
  @override
  bool get showSubscriptionGatedContent => true;

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
  bool isConstructBlocked(ConstructIdentifier id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
