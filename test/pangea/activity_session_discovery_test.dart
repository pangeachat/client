import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_session_discovery.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

/// #7982: the world map and activity start page missed coursemate sessions in
/// courses with >100 rooms because the shared discovery read only fetched the
/// first hierarchy page. The fix fully paginates that read and caches the scan
/// per space (so the map's ~3s loop doesn't re-page every cycle).
///
/// These exercise the fix's three seams directly — pagination, the scoped
/// filter, and the scan cache — which is where the bug lived and where the
/// regression risk is; the extension method that wires them together is thin
/// glue over these.
void main() {
  const spaceId = '!course:fakeServer.notExisting';
  const act = 'activity-abc';
  final sessionType = '${PangeaRoomTypes.activitySession}:$act';

  // A minimal valid space-hierarchy room chunk. Only room_id / room_type carry
  // the signal we test; the rest are the response's required fields.
  SpaceRoomsChunk$2 chunk(String roomId, {String? roomType}) =>
      SpaceRoomsChunk$2.fromJson({
        'room_id': roomId,
        'room_type': ?roomType,
        'num_joined_members': 1,
        'guest_can_join': false,
        'world_readable': false,
        'children_state': <Map<String, Object?>>[],
      });

  GetSpaceHierarchyResponse page(
    List<SpaceRoomsChunk$2> rooms, {
    String? nextBatch,
  }) => GetSpaceHierarchyResponse(rooms: rooms, nextBatch: nextBatch);

  group('paginateActivitySessionRooms', () {
    test('finds a session on page 2 (the #7982 regression)', () async {
      // Page 1 is all non-session rooms (analytics + the space root) with a
      // continuation token; the session room only appears on page 2. The old
      // single-page read stopped at page 1 and never saw it.
      final pages = <GetSpaceHierarchyResponse>[
        page([
          chunk(spaceId), // the space root itself — skipped
          chunk(
            '!analytics:fakeServer.notExisting',
            roomType: PangeaRoomTypes.analytics,
          ),
          chunk('!chat:fakeServer.notExisting'),
        ], nextBatch: 'token-1'),
        page([chunk('!session:fakeServer.notExisting', roomType: sessionType)]),
      ];

      var calls = 0;
      final result = await paginateActivitySessionRooms(
        spaceId: spaceId,
        fetchPage: (from) async {
          // Page 1 requested with from==null, page 2 with the returned token.
          expect(from, calls == 0 ? isNull : 'token-1');
          return pages[calls++];
        },
      );

      expect(calls, 2, reason: 'should keep paging until nextBatch is null');
      expect(result, {'!session:fakeServer.notExisting': sessionType});
    });

    test(
      'keeps only activity-session rooms, dropping others and the root',
      () async {
        final result = await paginateActivitySessionRooms(
          spaceId: spaceId,
          fetchPage: (from) async => page([
            chunk(spaceId, roomType: 'm.space'),
            chunk('!analytics:x', roomType: PangeaRoomTypes.analytics),
            chunk('!plainchat:x'), // no room type
            chunk('!s1:x', roomType: sessionType),
            chunk(
              '!s2:x',
              roomType: '${PangeaRoomTypes.activitySession}:other',
            ),
          ]),
        );
        expect(result, {
          '!s1:x': sessionType,
          '!s2:x': '${PangeaRoomTypes.activitySession}:other',
        });
      },
    );

    test(
      'stops at the page cap and logs rather than looping forever',
      () async {
        // A pathological server that always returns another page. The cap must
        // bound the number of reads; we assert it stopped at maxCalls.
        var calls = 0;
        final result = await paginateActivitySessionRooms(
          spaceId: spaceId,
          maxCalls: 3,
          fetchPage: (from) async {
            calls++;
            return page([
              chunk('!s$calls:x', roomType: sessionType),
            ], nextBatch: 'always-more');
          },
        );
        expect(calls, 3);
        expect(result, hasLength(3));
      },
    );

    test('returns null on a failed read so the caller retries', () async {
      final result = await paginateActivitySessionRooms(
        spaceId: spaceId,
        fetchPage: (from) async => throw Exception('network down'),
      );
      expect(result, isNull);
    });
  });

  group('activitySessionIdsMatching', () {
    final scan = {
      '!a:x': sessionType,
      '!b:x': '${PangeaRoomTypes.activitySession}:other',
    };

    test('unscoped returns every room id', () {
      expect(activitySessionIdsMatching(scan), {'!a:x', '!b:x'});
    });

    test('scoped keeps only the matching activity id', () {
      expect(activitySessionIdsMatching(scan, activityId: act), {'!a:x'});
    });
  });

  group('scan cache TTL', () {
    setUp(debugResetActivitySessionScanCache);
    tearDown(debugResetActivitySessionScanCache);

    test('a fresh entry is reused; an expired one is not', () {
      const t0 = 1000000;
      final ttlMs = debugActivitySessionScanTtl.inMilliseconds;
      debugStoreActivitySessionScan(spaceId, {'!a:x': sessionType}, t0);

      // Within the TTL: reused (so the ~3s loop skips a re-scan).
      expect(debugFreshActivitySessionScan(spaceId, t0 + ttlMs), {
        '!a:x': sessionType,
      });
      // Past the TTL: a miss, so the caller re-paginates.
      expect(debugFreshActivitySessionScan(spaceId, t0 + ttlMs + 1), isNull);
    });

    test('a reset clears the cache', () {
      debugStoreActivitySessionScan(spaceId, {'!a:x': sessionType}, 0);
      debugResetActivitySessionScanCache();
      expect(debugFreshActivitySessionScan(spaceId, 0), isNull);
    });
  });
}
