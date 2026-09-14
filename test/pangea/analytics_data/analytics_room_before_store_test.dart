import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';
import '../get_test_client.dart';

/// Regression: Sentry CLIENT-D3G (#9017).
///
/// The activity auto-save sweep asks the data service for the account's
/// analytics room on every plan hydration. That lookup used to reach the
/// Matrix client THROUGH the analytics client, which is null before the store
/// opens and again after dispose — so a sweep on either side of that window
/// threw a null check and blocked the archive, once per hydration, for the
/// life of the tab. The room lookup never needed the store: it must answer
/// from the account client whether or not the store is there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('analytics_room');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
  });

  test('getAnalyticsRoom answers from the account client while the store '
      'has not opened', () async {
    final client = await getTestClient();
    addTearDown(client.dispose);
    // The lookup waits for a first sync; the fixture sync also seeds rooms
    // the test did not ask for, so it is run and then cleared.
    if (client.prevBatch == null) {
      await client.oneShotSync();
      client.rooms.clear();
    }
    final userId = client.userID!;

    final analyticsRoom = Room(
      id: '!1234:fakeServer.notExisting',
      client: client,
    );
    analyticsRoom.setState(
      Event(
        type: EventTypes.RoomCreate,
        content: {
          'creator': userId,
          'type': PangeaRoomTypes.analytics,
          ModelKey.langCode: 'es',
        },
        senderId: userId,
        eventId: '\$create',
        originServerTs: DateTime.utc(2026, 1, 1, 12),
        stateKey: '',
        room: analyticsRoom,
      ),
    );
    client.rooms.add(analyticsRoom);

    // A store that never opens: the state every read on the init path
    // runs in, and the state dispose leaves behind.
    final service = AnalyticsDataService(
      client,
      databaseBuilder: (_) => Completer<AnalyticsDatabase>().future,
    );
    expect(
      service.databaseReady.isCompleted,
      isFalse,
      reason: 'precondition: the analytics store has not opened',
    );

    final found = await service.getAnalyticsRoom(
      LanguageModel(langCode: 'es', displayName: 'Spanish'),
    );
    expect(found?.id, analyticsRoom.id);
  });
}
