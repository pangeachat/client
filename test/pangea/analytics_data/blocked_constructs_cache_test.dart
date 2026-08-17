import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/features/analytics_data/blocked_constructs_cache.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import '../get_test_client.dart';

/// [BlockedConstructsCache] must hand back the current blocked set after every
/// kind of change it memoizes across — settings event replaced, L2 switched,
/// analytics room replaced or joined/left, or `clear()` — while doing no
/// re-parse and no room re-resolution when nothing changed.
void main() {
  late Client client;

  setUpAll(() async {
    client = await getTestClient();
  });

  tearDownAll(() => client.dispose(closeDatabase: true));

  ConstructIdentifier vocab(String lemma) => ConstructIdentifier(
    lemma: lemma,
    type: ConstructTypeEnum.vocab,
    category: 'noun',
  );

  var eventCounter = 0;

  /// Install a fresh analytics-settings state event on [room].
  void setBlocked(Room room, Set<ConstructIdentifier> blocked) {
    eventCounter++;
    room.setState(
      Event(
        type: PangeaEventTypes.analyticsSettings,
        stateKey: '',
        content: AnalyticsSettingsModel(blockedConstructs: blocked).toJson(),
        eventId: '\$settings_$eventCounter',
        senderId: client.userID!,
        originServerTs: DateTime.now(),
        room: room,
      ),
    );
  }

  /// A read helper that also counts how often the room had to be resolved.
  ({Set<ConstructIdentifier> Function() read, int Function() resolves}) harness(
    BlockedConstructsCache cache, {
    required String? Function() l2,
    required List<Room> Function() rooms,
    required Room? Function() resolve,
  }) {
    var resolves = 0;
    return (
      read: () => cache.read(
        l2: l2(),
        roomCount: rooms().length,
        roomById: (id) {
          for (final r in rooms()) {
            if (r.id == id) return r;
          }
          return null;
        },
        resolveAnalyticsRoom: () {
          resolves++;
          return resolve();
        },
      ),
      resolves: () => resolves,
    );
  }

  test('memoizes: same event → same set instance, room resolved once', () {
    final room = Room(id: '!es:x', client: client);
    setBlocked(room, {vocab('casa')});
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => [room],
      resolve: () => room,
    );

    final a = h.read();
    final b = h.read();
    expect(a, {vocab('casa')});
    expect(identical(a, b), isTrue);
    expect(h.resolves(), 1);
    expect(() => a.add(vocab('x')), throwsUnsupportedError);
  });

  test('a replaced settings event re-parses', () {
    final room = Room(id: '!es:x', client: client);
    setBlocked(room, {vocab('casa')});
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => [room],
      resolve: () => room,
    );
    expect(h.read(), {vocab('casa')});

    setBlocked(room, {vocab('casa'), vocab('perro')});
    expect(h.read(), {vocab('casa'), vocab('perro')});
    setBlocked(room, {});
    expect(h.read(), isEmpty);
    // still the same room; no re-resolution needed for a settings change
    expect(h.resolves(), 1);
  });

  test('no settings event yet → empty, then picks the event up', () {
    final room = Room(id: '!es:x', client: client);
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => [room],
      resolve: () => room,
    );
    expect(h.read(), isEmpty);
    setBlocked(room, {vocab('gato')});
    expect(h.read(), {vocab('gato')});
  });

  test('an L2 change re-resolves the room and reads that room set', () {
    final es = Room(id: '!es:x', client: client);
    final fr = Room(id: '!fr:x', client: client);
    setBlocked(es, {vocab('casa')});
    setBlocked(fr, {vocab('maison')});
    var l2 = 'es';
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => l2,
      rooms: () => [es, fr],
      resolve: () => l2 == 'es' ? es : fr,
    );
    expect(h.read(), {vocab('casa')});
    l2 = 'fr';
    expect(h.read(), {vocab('maison')});
    expect(h.resolves(), 2);
    l2 = 'es';
    expect(h.read(), {vocab('casa')});
    expect(h.resolves(), 3);
  });

  test('null L2 → empty without resolving', () {
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => null,
      rooms: () => [],
      resolve: () => fail('must not resolve without an L2'),
    );
    expect(h.read(), isEmpty);
    expect(h.resolves(), 0);
  });

  test('a room join/leave (room count change) re-resolves', () {
    final old = Room(id: '!old:x', client: client);
    final older = Room(id: '!older:x', client: client);
    setBlocked(old, {vocab('a')});
    setBlocked(older, {vocab('b')});
    var rooms = [old];
    var canonical = old;
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => rooms,
      resolve: () => canonical,
    );
    expect(h.read(), {vocab('a')});
    // an older analytics room syncs in and becomes canonical
    rooms = [old, older];
    canonical = older;
    expect(h.read(), {vocab('b')});
    expect(h.resolves(), 2);
  });

  test('the cached room disappearing (left / replaced object) re-resolves', () {
    final room1 = Room(id: '!es:x', client: client);
    setBlocked(room1, {vocab('a')});
    // same id, different object (as after a client rebuild), different state
    final room2 = Room(id: '!es:x', client: client);
    setBlocked(room2, {vocab('b')});
    var current = room1;
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => [current],
      resolve: () => current,
    );
    expect(h.read(), {vocab('a')});
    current = room2;
    expect(h.read(), {vocab('b')});
    expect(h.resolves(), 2);
  });

  test('clear() drops both memos', () {
    final room = Room(id: '!es:x', client: client);
    setBlocked(room, {vocab('a')});
    final cache = BlockedConstructsCache();
    final h = harness(
      cache,
      l2: () => 'es',
      rooms: () => [room],
      resolve: () => room,
    );
    final first = h.read();
    cache.clear();
    final second = h.read();
    expect(second, {vocab('a')});
    expect(identical(first, second), isFalse); // re-parsed
    expect(h.resolves(), 2); // re-resolved
  });
}
