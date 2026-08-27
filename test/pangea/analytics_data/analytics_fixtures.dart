import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_event.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

/// Deterministic fixture builders for the analytics data layer tests and the
/// micro-benchmark. Everything here is pure data — no widgets, no network.

const testLang = 'es';
const testUserId = '@test:fakeServer.notExisting';

/// A fixed origin so timestamps in fixtures are stable across runs.
final t0 = DateTime.utc(2026, 1, 1);

DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

OneConstructUse use({
  required String lemma,
  String category = 'noun',
  ConstructTypeEnum type = ConstructTypeEnum.vocab,
  ConstructUseTypeEnum useType = ConstructUseTypeEnum.corPA,
  int? xp,
  required DateTime ts,
  String? roomId,
  String? eventId,
  String? id,
}) => OneConstructUse(
  useType: useType,
  lemma: lemma,
  form: lemma,
  category: category,
  constructType: type,
  metadata: ConstructUseMetaData(
    roomId: roomId,
    eventId: eventId,
    timeStamp: ts,
  ),
  xp: xp ?? useType.pointValue,
  id: id,
);

ConstructUses constructUses(
  String lemma, {
  String category = 'noun',
  ConstructTypeEnum type = ConstructTypeEnum.vocab,
  List<OneConstructUse> uses = const [],
}) => ConstructUses(
  uses: uses,
  constructType: type,
  lemma: lemma,
  category: category,
);

/// `count` uses for `lemma`, `xpEach` XP apiece, spaced one minute apart
/// starting at `startMinute` (chronological order in the returned list).
List<OneConstructUse> usesFor(
  String lemma, {
  required int count,
  int xpEach = 5,
  int startMinute = 0,
  String category = 'noun',
  ConstructTypeEnum type = ConstructTypeEnum.vocab,
  String? roomId,
  ConstructUseTypeEnum useType = ConstructUseTypeEnum.corPA,
}) => List.generate(
  count,
  (i) => use(
    lemma: lemma,
    category: category,
    type: type,
    useType: useType,
    xp: xpEach,
    ts: at(startMinute + i),
    roomId: roomId,
    eventId: '\$${lemma}_${startMinute + i}',
  ),
);

/// Opens a fresh, empty in-memory database. Each call gets its own sqlite
/// connection so tests never share state.
/// [name] distinguishes stores WITHIN one test file: the underlying box
/// collection is keyed by name, so two calls sharing it also share their data —
/// which silently leaks one test's seed into the next.
Future<AnalyticsDatabase> freshDatabase({
  String name = 'analytics_test',
}) async {
  // singleInstance:false or sqflite hands the same open ':memory:' database
  // back to every caller, so "fresh" stores would share their contents and one
  // test's seed would silently leak into the next.
  final sqlite = await databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(singleInstance: false),
  );
  return AnalyticsDatabase.init(
    name,
    database: sqlite,
    sqfliteFactory: databaseFactoryFfi,
  );
}

class ServerEventFactory {
  final Client client;
  final Room room;
  int _n = 0;

  ServerEventFactory._(this.client, this.room);

  static Future<ServerEventFactory> create() async {
    final client = await getTestClient();
    final room = Room(id: '!analytics:fakeServer.notExisting', client: client);
    return ServerEventFactory._(client, room);
  }

  Future<void> dispose() => client.dispose(closeDatabase: true);

  /// One synced construct event carrying [uses], stamped [ts].
  ConstructAnalyticsEvent event(
    List<OneConstructUse> uses, {
    required DateTime ts,
    String? eventId,
  }) {
    _n++;
    return ConstructAnalyticsEvent(
      event: Event(
        content: ConstructAnalyticsModel(uses: uses).toJson(),
        type: PangeaEventTypes.construct,
        eventId: eventId ?? '\$server_event_$_n',
        senderId: client.userID ?? testUserId,
        originServerTs: ts,
        room: room,
        status: EventStatus.synced,
      ),
    );
  }
}
