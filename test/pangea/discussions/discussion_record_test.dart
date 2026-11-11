import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/discussions/discussion_record.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../activity_session_fixtures.dart';
import '../get_test_client.dart';

/// The saved-list record of a discussion seat (#9647): filed once when the
/// learner ends it, its completion reported once even when the analytics
/// room's echo comes late, and taken off again by "Wait, I'm not done".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = testSessionUserId;
  final ended = DateTime.utc(2026, 11, 3, 12);

  late Client client;
  late List<String> filed;
  late List<String> unfiled;
  late List<String> completed;

  /// What this client last synced of the saved list.
  late Set<String> syncedList;

  /// Whether a write reaches an analytics room.
  late bool hasAnalyticsRoom;
  late DiscussionRecord record;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'BOT_NAME=$testDiscussionBotId');
    final tempDir = await Directory.systemTemp.createTemp('discussion_record');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: DateTime.now().toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [
          {
            'language_code': 'es',
            'language_name': 'Spanish',
            'l2_support': 'full',
          },
        ],
      }),
    });
    await PLanguageStore.initialize();
  });

  setUp(() async {
    client = await getTestClient();
    filed = [];
    unfiled = [];
    completed = [];
    syncedList = {};
    hasAnalyticsRoom = true;
    record = DiscussionRecord(
      file: (roomId, _) async {
        filed.add(roomId);
        return hasAnalyticsRoom;
      },
      unfile: (roomId, _) async {
        unfiled.add(roomId);
        return hasAnalyticsRoom;
      },
      onCompleted: (room, _, _) => completed.add(room.id),
      isFiled: (room, _) => syncedList.contains(room.id),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  Room endedRoom() => discussionRoom(
    client,
    seats: [discussionSeat(me, finishedAt: ended, archivedAt: ended)],
  );

  test('an ended seat is filed and its completion reported, once, though '
      'the list this client synced never shows it yet', () async {
    final room = endedRoom();
    await record.sync(room);
    // A second pass before the analytics room's echo lands.
    await record.sync(room);

    expect(filed, [room.id]);
    expect(completed, [room.id]);
  });

  test('a seat already on the list was counted where it was filed', () async {
    final room = endedRoom();
    syncedList.add(room.id);
    await record.sync(room);

    expect(filed, isEmpty);
    expect(completed, isEmpty);
  });

  test('with no analytics room to file it in, nothing counts', () async {
    hasAnalyticsRoom = false;
    final room = endedRoom();
    await record.sync(room);

    expect(filed, [room.id]);
    expect(completed, isEmpty);
  });

  test('"Wait, I\'m not done" takes it off the list, and ending again files '
      'it again', () async {
    final room = endedRoom();
    await record.sync(room);
    syncedList.add(room.id);

    // The server cleared the seat's finish and archive.
    final reopened = discussionRoom(client, seats: [discussionSeat(me)]);
    await record.sync(reopened);
    expect(unfiled, [room.id]);

    syncedList.remove(room.id);
    await record.sync(endedRoom());
    expect(filed, [room.id, room.id]);
  });

  test('a seat that was never ended is never written', () async {
    await record.sync(discussionRoom(client, seats: [discussionSeat(me)]));
    expect(filed, isEmpty);
    expect(unfiled, isEmpty);
  });

  test('an admin reading along has nothing to file', () async {
    await record.sync(
      discussionRoom(
        client,
        seats: [
          discussionSeat(
            '@classmate:fakeServer.notExisting',
            finishedAt: ended,
            archivedAt: ended,
          ),
        ],
      ),
    );
    expect(filed, isEmpty);
  });

  test('a discussion in a language the app does not know is reported, not '
      'skipped silently', () async {
    final room = endedRoom();
    final plan = room.getState(PangeaEventTypes.activityPlan)!;
    final content = Map<String, dynamic>.from(plan.content);
    final req = Map<String, dynamic>.from(content['req'] as Map);
    req['target_language'] = 'xx';
    content['req'] = req;
    room.setState(
      activitySessionStateEvent(
        room,
        type: PangeaEventTypes.activityPlan,
        content: content,
      ),
    );

    await record.sync(room);
    expect(filed, isEmpty);
    expect(
      ErrorHandler.reportedOnceKeysForTest,
      contains('discussion_record_language:xx'),
    );
  });
}
