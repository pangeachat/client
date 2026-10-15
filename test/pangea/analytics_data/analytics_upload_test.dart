import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics/packed_construct_event.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/features/analytics_data/server_event_arrivals.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_engagement_tracker.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../get_test_client.dart';
import 'analytics_fixtures.dart';

const _analyticsRoomId = '!analytics:fakeServer.notExisting';
final _spanish = LanguageModel(langCode: testLang, displayName: 'Spanish');

/// A homeserver that answers analytics sends from a script and everything
/// else as [FakeMatrixApi] does. An accepted send's server copy is synced
/// back before the send returns, as can happen on a real server, unless
/// [syncCopies] is off.
class _ConstructSendServer extends http.BaseClient {
  _ConstructSendServer(this.accepts);

  /// Whether each construct send, in order, is accepted.
  final List<bool> accepts;
  final FakeMatrixApi _fallback = FakeMatrixApi();
  final List<List<dynamic>> sentUses = [];
  late Client client;
  bool syncCopies = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isConstructSend =
        request.method == 'PUT' &&
        request.url.path.contains('/send/${PangeaEventTypes.construct}/');
    if (!isConstructSend) return _fallback.send(request);

    final content = jsonDecode((request as http.Request).body) as Map;
    sentUses.add(content['uses'] as List);
    if (!accepts[sentUses.length - 1]) {
      return _json(400, {'errcode': 'M_UNKNOWN', 'error': 'refused'});
    }
    final eventId = '\$construct${sentUses.length}';
    if (syncCopies) syncServerCopy(eventId);
    return _json(200, {'event_id': eventId});
  }

  void syncServerCopy(String eventId) => client.onSync.add(
    SyncUpdate(
      nextBatch: 'next',
      rooms: RoomsUpdate(
        join: {
          _analyticsRoomId: JoinedRoomUpdate(
            timeline: TimelineUpdate(
              events: [
                MatrixEvent(
                  type: PangeaEventTypes.construct,
                  content: {},
                  senderId: testUserId,
                  eventId: eventId,
                  originServerTs: DateTime.now(),
                ),
              ],
            ),
          ),
        },
      ),
    ),
  );

  http.StreamedResponse _json(int status, Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

class _FakeDataService implements AnalyticsDataService {
  _FakeDataService(this.room, this.batches);

  final Room room;
  final Map<String, List<OneConstructUse>> batches;
  final List<String> clearedKeys = [];

  @override
  String? get accountUserId => testUserId;

  @override
  bool get isLogged => true;

  @override
  Future<Room?> getAnalyticsRoom(LanguageModel lang) async => room;

  @override
  Future<Map<String, List<OneConstructUse>>> getLocalUseBatches(
    String language,
  ) async => Map.of(batches);

  @override
  Future<void> clearLocalAnalytics(
    String language,
    Iterable<String> batchKeys,
  ) async => clearedKeys.addAll(batchKeys);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePangeaController implements PangeaController {
  @override
  final UserController userController = _FakeUserController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  @override
  LanguageModel? get userL2 => _spanish;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // start() opens the dosage coverage period, which reads env flags backed by
  // GetStorage.
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('analytics_upload');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad();
  });

  late _ConstructSendServer server;
  late Client client;
  late Room room;
  late ValueNotifier<ConnectionStatus> connection;

  Future<void> connect(List<bool> accepts) async {
    server = _ConstructSendServer(accepts);
    client = await getTestClient(httpClient: server);
    server.client = client;
    room = Room(id: _analyticsRoomId, client: client);
    client.rooms.add(room);
    connection = ValueNotifier(ConnectionStatus.connected);
  }

  tearDown(() => client.dispose());

  AnalyticsUpdateService updateService(_FakeDataService data) =>
      AnalyticsUpdateService(
        data,
        tracker: DosageEngagementTracker(),
        audioBuffer: DosageAudioBuffer(),
        connectionStatus: connection,
      );

  /// A use whose JSON is a little over a third of the event size cap, so a
  /// batch of two fills an event on its own.
  OneConstructUse thirdOfCapUse(int i) =>
      use(lemma: '$i${'x' * (PackedConstructEvent.maxBytes ~/ 6)}', ts: at(i));

  group('a flush clears only what the server accepted', () {
    test('every batch is cleared once the server accepts them', () async {
      await connect([true]);
      final data = _FakeDataService(room, {
        'a': [use(lemma: 'uno', ts: at(0))],
        'b': [use(lemma: 'dos', ts: at(1))],
      });

      await updateService(
        data,
      ).sendLocalAnalyticsToAnalyticsRoom(l2Override: _spanish);

      expect(data.clearedKeys, ['a', 'b']);
    });

    test('a refused upload keeps every batch and leaves no failed copy in the '
        'room', () async {
      await connect([false]);
      final data = _FakeDataService(room, {
        'a': [use(lemma: 'uno', ts: at(0))],
      });

      await updateService(
        data,
      ).sendLocalAnalyticsToAnalyticsRoom(l2Override: _spanish);

      expect(server.sentUses, hasLength(1));
      expect(data.clearedKeys, isEmpty);
      expect(await room.getRoomAnalyticsEvents(), isEmpty);
      expect(
        (await client.database.getEventList(
          room,
        )).where((e) => e.type == PangeaEventTypes.construct),
        isEmpty,
        reason: 'a failed send must not leave a copy that reads as sent',
      );
    });

    test('a partly refused upload clears only the accepted batches', () async {
      await connect([true, false]);
      final data = _FakeDataService(room, {
        'a': [thirdOfCapUse(0), thirdOfCapUse(1)],
        'b': [thirdOfCapUse(2), thirdOfCapUse(3)],
      });

      await updateService(
        data,
      ).sendLocalAnalyticsToAnalyticsRoom(l2Override: _spanish);

      expect(server.sentUses, hasLength(2));
      expect(data.clearedKeys, ['a']);
    });

    test('batches are cleared only after the server copy arrives', () async {
      await connect([true]);
      server.syncCopies = false;
      final data = _FakeDataService(room, {
        'a': [use(lemma: 'uno', ts: at(0))],
      });

      final flush = updateService(
        data,
      ).sendLocalAnalyticsToAnalyticsRoom(l2Override: _spanish);
      await pumpEventQueue();
      expect(server.sentUses, hasLength(1));
      expect(data.clearedKeys, isEmpty);

      server.syncServerCopy('\$construct1');
      await flush;
      expect(data.clearedKeys, ['a']);
    });
  });

  group('while the connection is lost', () {
    test('a flush sends nothing and keeps every batch', () async {
      await connect([true]);
      connection.value = ConnectionStatus.offline;
      final data = _FakeDataService(room, {
        'a': [use(lemma: 'uno', ts: at(0))],
      });

      await updateService(
        data,
      ).sendLocalAnalyticsToAnalyticsRoom(l2Override: _spanish);

      expect(server.sentUses, isEmpty);
      expect(data.clearedKeys, isEmpty);
    });

    test('what built up is sent once the connection returns', () async {
      await connect([true]);
      MatrixState.pangeaController = _FakePangeaController();
      connection.value = ConnectionStatus.offline;
      final data = _FakeDataService(room, {
        'a': [use(lemma: 'uno', ts: at(0))],
      });
      final service = updateService(data)..start();
      addTearDown(service.dispose);

      connection.value = ConnectionStatus.unreachable;
      await pumpEventQueue();
      expect(server.sentUses, isEmpty, reason: 'still lost');

      connection.value = ConnectionStatus.backOnline;
      await pumpEventQueue();
      expect(server.sentUses, hasLength(1));
      expect(data.clearedKeys, ['a']);
    });
  });

  test('a failed send is not read back as analytics', () async {
    await connect([false]);
    // The pending copy the SDK shows by default, which a failed send leaves
    // behind with an error status.
    await room.sendEvent({
      'uses': <dynamic>[],
    }, type: PangeaEventTypes.construct);
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(
          join: {
            _analyticsRoomId: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    type: PangeaEventTypes.construct,
                    content: {'uses': <dynamic>[]},
                    senderId: testUserId,
                    eventId: '\$fromServer',
                    originServerTs: DateTime.now(),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );

    final events = await room.getRoomAnalyticsEvents();

    expect(events.map((e) => e.eventId), ['\$fromServer']);
  });

  test('a server copy that never arrives is reported as late', () async {
    await connect([]);
    final arrivals = ServerEventArrivals(room);
    addTearDown(arrivals.cancel);

    expect(
      await arrivals.waitFor('\$missing', const Duration(milliseconds: 10)),
      isFalse,
    );
  });
}
