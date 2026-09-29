import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';

/// Wiring-only coverage for the two pieces of logic [CallService] extracts from
/// its sync subscriptions: [dispatchSyncedCallAudioEvents] (which synced events
/// route to which merge trigger) and [SyncReconnectDetector] (which sync-status
/// transition is a reconnect). Both are exercised with hand-built SDK objects
/// and a spy -- no CallService, Client, coordinator or homeserver -- exactly
/// because that is the part a compile-clean seam cannot prove. The one-line SDK
/// seam adapters (send / upload / isDmRoom) are covered by `flutter analyze`,
/// and the coordinator's own orchestration by its own suite.
void main() {
  MatrixEvent event({
    required String type,
    required Map<String, Object?> content,
    String senderId = '@user:server',
    String eventId = '\$event:server',
  }) => MatrixEvent(
    type: type,
    content: content,
    senderId: senderId,
    eventId: eventId,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// A sync whose joined rooms each carry the given timeline events; a null
  /// value builds a joined room with a null timeline.
  SyncUpdate sync(Map<String, List<MatrixEvent>?> rooms) => SyncUpdate(
    nextBatch: 'next',
    rooms: RoomsUpdate(
      join: {
        for (final entry in rooms.entries)
          entry.key: JoinedRoomUpdate(
            timeline: entry.value == null
                ? null
                : TimelineUpdate(events: entry.value),
          ),
      },
    ),
  );

  group('dispatchSyncedCallAudioEvents', () {
    late List<(String, String)> halves;
    late List<(String, String)> merged;

    void run(SyncUpdate update) => dispatchSyncedCallAudioEvents(
      update,
      onHalf: (roomId, callKey) => halves.add((roomId, callKey)),
      onMerged: (roomId, callKey) => merged.add((roomId, callKey)),
    );

    setUp(() {
      halves = [];
      merged = [];
    });

    test('a pangea.call_audio half routes to onHalf with its room + key', () {
      run(
        sync({
          '!room:server': [
            event(
              type: CallAudioContent.relType,
              content: {'call_key': '\$call:server'},
            ),
          ],
        }),
      );
      expect(halves, [('!room:server', '\$call:server')]);
      expect(merged, isEmpty);
    });

    test('a pangea.call_audio_merged event routes to onMerged only', () {
      run(
        sync({
          '!room:server': [
            event(
              type: CallAudioMergedContent.relType,
              content: {'call_key': '\$call:server'},
            ),
          ],
        }),
      );
      expect(merged, [('!room:server', '\$call:server')]);
      expect(halves, isEmpty);
    });

    test('a missing call_key routes NEITHER, on either event type', () {
      // Both routable types in one page, each missing its key: the guard runs
      // ahead of the type branch, so it must skip a bad key for BOTH.
      run(
        sync({
          '!room:server': [
            event(type: CallAudioContent.relType, content: {}),
            event(type: CallAudioMergedContent.relType, content: {}),
          ],
        }),
      );
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('a non-String call_key routes NEITHER (type-check), on either type', () {
      // Mutation guard: drop the `is! String` half of the check and a numeric
      // call_key would be routed (or crash the cast); it must be skipped -- for
      // a half AND a merged event, so a branch-specific regression cannot hide.
      run(
        sync({
          '!room:server': [
            event(type: CallAudioContent.relType, content: {'call_key': 42}),
            event(
              type: CallAudioMergedContent.relType,
              content: {'call_key': 42},
            ),
          ],
        }),
      );
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('an empty call_key routes NEITHER (isEmpty check), on either type', () {
      // Mutation guard: drop the `|| callKey.isEmpty` half and an empty key
      // would be routed as a real call -- checked for a half AND a merged event.
      run(
        sync({
          '!room:server': [
            event(type: CallAudioContent.relType, content: {'call_key': ''}),
            event(
              type: CallAudioMergedContent.relType,
              content: {'call_key': ''},
            ),
          ],
        }),
      );
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('an unrelated event type routes NEITHER', () {
      run(
        sync({
          '!room:server': [
            event(
              type: 'm.room.message',
              content: {'call_key': '\$call:server'},
            ),
          ],
        }),
      );
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('events across two joined rooms each route with their own roomId', () {
      run(
        sync({
          '!a:server': [
            event(
              type: CallAudioContent.relType,
              content: {'call_key': '\$callA:server'},
            ),
          ],
          '!b:server': [
            event(
              type: CallAudioMergedContent.relType,
              content: {'call_key': '\$callB:server'},
            ),
          ],
        }),
      );
      expect(halves, [('!a:server', '\$callA:server')]);
      expect(merged, [('!b:server', '\$callB:server')]);
    });

    test('a null timeline yields no calls and does not throw', () {
      run(sync({'!room:server': null}));
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('an empty join and a null rooms yield no calls and no throw', () {
      run(
        SyncUpdate(
          nextBatch: 'next',
          rooms: RoomsUpdate(join: {}),
        ),
      );
      run(SyncUpdate(nextBatch: 'next', rooms: null));
      expect(halves, isEmpty);
      expect(merged, isEmpty);
    });

    test('one room mixing halves, merges, and noise routes each correctly', () {
      run(
        sync({
          '!room:server': [
            event(
              type: CallAudioContent.relType,
              content: {'call_key': '\$one:server'},
            ),
            event(type: 'm.room.message', content: {'call_key': '\$noise'}),
            event(
              type: CallAudioMergedContent.relType,
              content: {'call_key': '\$two:server'},
            ),
            event(type: CallAudioContent.relType, content: {'call_key': ''}),
          ],
        }),
      );
      expect(halves, [('!room:server', '\$one:server')]);
      expect(merged, [('!room:server', '\$two:server')]);
    });
  });

  group('SyncReconnectDetector', () {
    /// Counts the reconnect edges a status sequence produces.
    int reconnects(List<SyncStatus> sequence) {
      final detector = SyncReconnectDetector();
      return sequence.where(detector.step).length;
    }

    test('error -> finished is a reconnect, exactly once', () {
      final detector = SyncReconnectDetector();
      expect(detector.step(SyncStatus.error), isFalse);
      expect(detector.step(SyncStatus.finished), isTrue);
      // The next finished, with no error since, is NOT a second reconnect.
      expect(detector.step(SyncStatus.finished), isFalse);
    });

    test('finished -> finished is not a reconnect', () {
      expect(reconnects([SyncStatus.finished, SyncStatus.finished]), 0);
    });

    test('processing -> finished with no prior error is not a reconnect', () {
      expect(reconnects([SyncStatus.processing, SyncStatus.finished]), 0);
    });

    test('error -> error is not a reconnect', () {
      expect(reconnects([SyncStatus.error, SyncStatus.error]), 0);
    });

    test('error -> error -> finished still reconnects once (a repeated error '
        'preserves the armed latch)', () {
      // A second error while already latched must NOT clear the latch: a
      // detector that reset its armed state on a repeated error would pass the
      // "error -> error" case above yet silently drop this recovery. The
      // finished after two errors is exactly one reconnect.
      expect(
        reconnects([SyncStatus.error, SyncStatus.error, SyncStatus.finished]),
        1,
      );
    });

    test('error -> processing -> finished IS a reconnect', () {
      // The realistic recovery loop: the SDK runs processing/cleaningUp between
      // the error and the finished, so the edge must survive the intermediate
      // statuses -- proving they are skipped, not treated as "not error".
      expect(
        reconnects([
          SyncStatus.error,
          SyncStatus.waitingForResponse,
          SyncStatus.processing,
          SyncStatus.cleaningUp,
          SyncStatus.finished,
        ]),
        1,
      );
    });

    test('a fresh error after a recovery re-arms the edge', () {
      expect(
        reconnects([
          SyncStatus.error,
          SyncStatus.finished,
          SyncStatus.error,
          SyncStatus.processing,
          SyncStatus.finished,
        ]),
        2,
      );
    });

    test('a leading finished before any error is not a reconnect', () {
      expect(reconnects([SyncStatus.finished]), 0);
    });
  });
}
