import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/incoming_call_banner.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../fake_pangea_controller.dart';
import '../get_test_client.dart';

/// Skips `initMatrix()` — push, notification listeners and the Pangea
/// controller are all irrelevant here and none of them stand up under
/// `flutter test`. The banner only wants `Matrix.of(context).callService`.
class _TestMatrixState extends MatrixState {
  @override
  // ignore: must_call_super
  void initState() {}
}

class _TestMatrix extends Matrix {
  const _TestMatrix({
    required super.clients,
    required super.store,
    required super.child,
  });

  @override
  MatrixState createState() => _TestMatrixState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = '@test:fakeServer.notExisting';
  const caller = '@friend:fakeServer.notExisting';
  const roomId = '!call:fakeServer.notExisting';

  late Client client;
  late SharedPreferences store;

  setUpAll(() async {
    // Avatar reads BotName.byEnvironment, which needs GetStorage and dotenv.
    final tempDir = await Directory.systemTemp.createTemp('call_banner');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'SYNAPSE_URL': 'https://fakeServer.notExisting',
      },
    );
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    MatrixState.pangeaController = FakePangeaController();
  });

  setUp(() async {
    client = await getTestClient();
  });

  tearDown(() async {
    await client.dispose();
  });

  /// A direct chat, because only a direct chat rings.
  Room directChat() {
    final room = Room(id: roomId, client: client, membership: Membership.join);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        caller: [roomId],
      },
    );
    return room;
  }

  /// Built by the sender's own serialiser, so this cannot drift from the shape
  /// a real ring actually has.
  Event ring(Room room, {String id = '\$ring'}) => Event(
    type: PangeaEventTypes.callNotification,
    content: const CallNotification(
      membershipEventId: '\$membership',
      senderDeviceId: 'CALLERDEVICE',
      video: false,
    ).toContent(DateTime.now()),
    senderId: caller,
    eventId: id,
    originServerTs: DateTime.now(),
    room: room,
  );

  /// A decline sent by THIS account — from another of its devices, which is
  /// what answering on a second phone looks like from here.
  Event ownDecline(Room room, {String refersTo = '\$ring'}) => Event(
    type: PangeaEventTypes.callDecline,
    content: {
      'm.relates_to': {'rel_type': 'm.reference', 'event_id': refersTo},
    },
    senderId: me,
    eventId: '\$decline',
    originServerTs: DateTime.now(),
    room: room,
  );

  /// Pumped twice: the banner subscribes in a post-frame callback, so nothing
  /// sent before that frame has run would reach it.
  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      _TestMatrix(
        clients: [client],
        store: store,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: IncomingCallBanner(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a call answered on another device', () {
    testWidgets('stops this one offering to answer it', (tester) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('\$ring')),
        findsOneWidget,
        reason: 'the prompt is up before anything turns the call down',
      );

      // Turned down on another of this account's phones. The caller is already
      // tearing the call down, so going on offering Answer here offers
      // something that no longer exists.
      client.onTimelineEvent.add(ownDecline(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$ring')), findsNothing);
    });

    testWidgets('and a ring still in flight cannot put it back', (
      tester,
    ) async {
      final room = directChat();
      await pumpBanner(tester);

      client.onTimelineEvent.add(ownDecline(room));
      await tester.pumpAndSettle();
      // The same ring arriving late — a decline can beat its own notification
      // through the timeline on a second device.
      client.onTimelineEvent.add(ring(room));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('\$ring')), findsNothing);
    });
  });
}
