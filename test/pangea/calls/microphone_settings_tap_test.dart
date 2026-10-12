import 'package:flutter/services.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/ios_call_screen.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';
import '../get_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  final permissionCalls = <String>[];

  setUp(() async {
    client = await getTestClient();
    permissionCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async {
            permissionCalls.add(call.method);
            return true;
          },
        );
  });

  tearDown(() => client.dispose());

  NotificationResponse tap(Map<String, String> additionalData) =>
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: FluffyChatPushPayload(
          client.clientName,
          null,
          r'$ring',
          additionalData: additionalData,
        ).toString(),
      );

  // iOS does not let the app ask again once the microphone is off, so the
  // notification has to take the learner to the one place they can fix it.
  test('tapping the microphone notification opens Settings', () async {
    await notificationTap(
      tap({IosCallScreen.microphoneSettingsTap: 'true'}),
      client: client,
    );
    expect(permissionCalls, ['openAppSettings']);
  });
}
