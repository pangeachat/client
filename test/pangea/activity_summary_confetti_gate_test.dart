import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';
import 'get_test_client.dart';

/// The star rain celebrates the activity summary landing on screen. An
/// unsubscribed learner never sees one — the subscription gate stands in its
/// place (#8860) — yet the summary still arrives in room state, and the
/// confetti fired on it at what looked like a random moment (#8905). The
/// confetti must follow the same subscription gate the summary widget does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = '@test:fakeServer.notExisting';
  const roomId = '!confetti:fakeServer.notExisting';

  late Client client;

  setUpAll(() async {
    // `isActivityFinished` skips the bot's role, and the bot's name comes from
    // the env file.
    dotenv.testLoad(
      mergeWith: {'SYNAPSE_URL': 'https://fakeServer.notExisting'},
    );
    // The controller's teardown reads a GetStorage box, which needs
    // path_provider; point it at a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('summary_confetti');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async => client = await getTestClient());

  tearDown(() => client.dispose());

  /// A session finished for everyone, with a generated summary already in
  /// room state — the moment the confetti is meant to celebrate.
  Room finishedRoomWithSummary() {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    final role = ActivityRoleModel(
      id: 'role1',
      userId: userId,
      role: 'debater',
      finishedAt: DateTime.utc(2026, 1, 1, 13),
    );
    room.setState(
      Event(
        type: PangeaEventTypes.activityRole,
        content: ActivityRolesModel({role.id: role}).toJson(),
        senderId: userId,
        eventId: '\$role',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: room,
      ),
    );
    room.setState(
      Event(
        type: PangeaEventTypes.activitySummary,
        content: ActivitySummaryModel(
          summary: ActivitySummaryResponseModel(
            participants: const [],
            summary: 'Well played.',
          ),
        ).toJson(),
        senderId: userId,
        eventId: '\$summary',
        originServerTs: DateTime.utc(2026, 1, 1, 14),
        // Summaries are keyed by the viewer's L1; the fake controller's is 'en'.
        stateKey: 'en',
        room: room,
      ),
    );
    return room;
  }

  Future<bool> confettiFires({required bool subscribed}) async {
    MatrixState.pangeaController = _ConfettiTestController(
      subscribed: subscribed,
    );
    final controller = ActivityChatController(
      userID: userId,
      room: finishedRoomWithSummary(),
      inputFocus: FocusNode(),
    );
    expect(
      controller.hasSummary,
      isTrue,
      reason: 'precondition: there is a summary to celebrate',
    );

    controller.showConfetti();
    final fired = controller.confettiNotifier.value;

    await controller.dispose();
    return fired;
  }

  test('a subscribed learner gets the confetti', () async {
    expect(await confettiFires(subscribed: true), isTrue);
  });

  test(
    'an unsubscribed learner, who sees the gate instead, does not',
    () async {
      expect(await confettiFires(subscribed: false), isFalse);
    },
  );
}

/// [FakePangeaController] plus what the activity chat controller reads back
/// through the static: the subscription gate, and the analytics dispatcher it
/// subscribes to on construction.
class _ConfettiTestController implements PangeaController {
  _ConfettiTestController({required bool subscribed})
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
