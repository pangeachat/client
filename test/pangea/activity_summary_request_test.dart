import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_chat_controller.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_activity_chat_pangea_controller.dart';
import 'get_test_client.dart';

/// A learner's retry or feedback goes to the bot as a write to the `request`
/// slot (#9199). Offline, that write fails, and the failure must come back
/// to the caller rather than escape it (#8362).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bot = '@bot:example.org';
  const userId = '@test:fakeServer.notExisting';
  // FakeMatrixApi accepts state writes to this room only.
  const onlineRoomId = '!1234:fakeServer.notExisting';
  const offlineRoomId = '!offline:fakeServer.notExisting';

  late Client client;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$bot');
    // The controller's teardown and the bot's name read GetStorage boxes,
    // which need path_provider; point it at a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('summary_request');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    MatrixState.pangeaController = ActivityChatTestPangeaController();
  });

  setUp(() async => client = await getTestClient());
  tearDown(() => client.dispose());

  /// A finished activity whose summary failed, with the bot still in the room
  /// to serve a retry.
  Room failedSummaryRoom(String roomId) {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    var count = 0;
    void setState(
      String type,
      String stateKey,
      Map<String, dynamic> content, {
      String sender = userId,
    }) => room.setState(
      Event(
        type: type,
        stateKey: stateKey,
        content: content,
        senderId: sender,
        eventId: '\$state${count++}',
        originServerTs: DateTime.now(),
        room: room,
      ),
    );

    final role = ActivityRoleModel(
      id: 'role1',
      userId: userId,
      role: 'Customer',
      finishedAt: DateTime.utc(2026),
    );
    setState(
      PangeaEventTypes.activityRole,
      '',
      ActivityRolesModel({role.id: role}).toJson(),
    );
    setState(EventTypes.RoomMember, userId, {'membership': 'join'});
    setState(EventTypes.RoomMember, bot, {'membership': 'join'}, sender: bot);
    setState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.canonical,
      ActivitySummaryModel(errorAt: DateTime.now()).toJson(),
      sender: bot,
    );
    // Already written, so the controller has no analytics to compute.
    setState(
      PangeaEventTypes.activitySummary,
      ActivitySummaryStateKeys.analytics,
      ActivitySummaryAnalyticsModel().toJson(),
    );
    return room;
  }

  ActivityChatController controllerFor(Room room) => ActivityChatController(
    userID: userId,
    room: room,
    inputFocus: FocusNode(),
  );

  test('writes the request slot with the feedback and a timestamp', () async {
    final controller = controllerFor(failedSummaryRoom(onlineRoomId));
    expect(controller.summaryView.value.canRequest, isTrue);

    final ok = await controller.requestSummary(feedback: 'Too harsh.');
    await controller.dispose();

    expect(ok, isTrue);
    final writes =
        FakeMatrixApi
            .calledEndpoints['/client/v3/rooms/${Uri.encodeComponent(onlineRoomId)}'
            '/state/${PangeaEventTypes.activitySummary}'
            '/${ActivitySummaryStateKeys.request}'];
    expect(writes, hasLength(1));
    final body = jsonDecode(writes!.single as String) as Map<String, dynamic>;
    expect(body['feedback'], 'Too harsh.');
    expect(DateTime.tryParse(body['requested_at'] as String), isNotNull);
  });

  test('a request that never reaches the server reports it', () async {
    final controller = controllerFor(failedSummaryRoom(offlineRoomId));

    // Must not throw: an escaping throw is what used to strand the spinner.
    final ok = await controller.requestSummary();
    final view = controller.summaryView.value;
    await controller.dispose();

    expect(ok, isFalse);
    expect(view.isLoading, isFalse);
    expect(view.hasFailed, isTrue);
  });
}
