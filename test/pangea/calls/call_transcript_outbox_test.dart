import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/routes/chat/calls/call_half_in_flight.dart';
import 'package:fluffychat/routes/chat/calls/call_transcript_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallTranscriptOutbox.guard', () {
    test('a publish that lands is remembered then dropped', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      final send = outbox.guard(
        '!r:server',
        '@a:server',
        (content, txnId) async => r'$evt',
      );

      await send({'a': 1}, 'txn-1');

      expect(
        await store.readAll(),
        isEmpty,
        reason: 'a half the homeserver confirmed needs no replay',
      );
    });

    test('the send cannot start until the half is persisted', () async {
      // A store whose write does not complete until the test releases it, so
      // the ordering is pinned even against a genuinely async write: the send
      // must not run until `remember` has finished. An in-memory store whose
      // write mutates synchronously would pass this even if `guard` dropped its
      // `await` -- this one does not.
      final writeGate = Completer<void>();
      final store = _GatedWriteStore(writeGate.future);
      final outbox = CallTranscriptOutbox(store: store);

      var sendStarted = false;
      final send = outbox.guard('!r:server', '@a:server', (
        content,
        txnId,
      ) async {
        sendStarted = true;
        // Null (not confirmed), so the record is not forgotten and stays
        // visible for the assertion below.
        return null;
      });

      final done = send({'a': 1}, 'txn-1');
      // Let every microtask settle; the write is still gated, so if the send
      // were reached it would have run by now.
      await Future<void>.delayed(Duration.zero);
      expect(
        sendStarted,
        isFalse,
        reason: 'the send must wait for the persist to complete',
      );

      writeGate.complete();
      await done;
      expect(sendStarted, isTrue, reason: 'and then it sends');
      expect(store.written.single['txn_id'], 'txn-1');
    });

    test('a publish dropped at hangup is retained for replay', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      // The exact observed failure: the app backgrounds and the late send is
      // dropped. Modelled as a throw so the in-session retry path still sees it.
      final send = outbox.guard(
        '!r:server',
        '@a:server',
        (content, txnId) async => throw StateError('backgrounded'),
      );

      await expectLater(
        send({'a': 1}, 'txn-1'),
        throwsA(isA<StateError>()),
        reason: 'the throw still propagates so the in-session retry runs',
      );

      final pending = await store.readAll();
      expect(pending, hasLength(1));
      expect(pending.single['room_id'], '!r:server');
      expect(pending.single['txn_id'], 'txn-1');
      expect(pending.single['owner'], '@a:server');
      expect(pending.single['content'], {'a': 1});
    });

    test('a send the homeserver does not confirm is retained', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      // Room.sendEvent returns null when the send did not durably land.
      final send = outbox.guard(
        '!r:server',
        '@a:server',
        (content, txnId) async => null,
      );

      await send({'a': 1}, 'txn-1');

      expect(
        await store.readAll(),
        hasLength(1),
        reason: 'a null event id means it did not land, so keep it for replay',
      );
    });
  });

  group('CallTranscriptOutbox.flush', () {
    test(
      'replays a retained half with identical room, txn and content, then drops it',
      () async {
        final store = InMemoryPendingCallTranscriptStore();
        final outbox = CallTranscriptOutbox(store: store);
        await outbox.remember('!r:server', 'txn-1', '@a:server', {
          'segments': [1, 2],
        });

        final sent = <(String, String, Map<String, dynamic>)>[];
        await outbox.flush((roomId, txnId, content) async {
          sent.add((roomId, txnId, content));
          return r'$evt';
        }, owner: '@a:server');

        expect(sent, hasLength(1));
        expect(sent.single.$1, '!r:server');
        expect(sent.single.$2, 'txn-1');
        expect(
          sent.single.$3,
          equals({
            'segments': [1, 2],
          }),
          reason:
              'the same bytes, so the deterministic txn id dedups the resend',
        );
        expect(await store.readAll(), isEmpty);

        final again = <String>[];
        await outbox.flush((roomId, txnId, content) async {
          again.add(txnId);
          return r'$evt';
        }, owner: '@a:server');
        expect(again, isEmpty, reason: 'a drained half is not resent');
      },
    );

    test('replays only the flushing account\'s own halves', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      await outbox.remember('!r:server', 'txn-a', '@a:server', {'x': 1});
      await outbox.remember('!r:server', 'txn-b', '@b:server', {'y': 2});

      final sent = <String>[];
      await outbox.flush((roomId, txnId, content) async {
        sent.add(txnId);
        return r'$evt';
      }, owner: '@a:server');

      expect(sent, ['txn-a'], reason: 'B\'s half is not A\'s to publish');
      final pending = await store.readAll();
      expect(
        pending.map((r) => r['txn_id']),
        ['txn-b'],
        reason: 'B\'s half is left for B, never deleted by A',
      );
    });

    test('an ownerless record is never replayed, whoever flushes', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      // A record carrying no owner -- crafted, or written before an owner could
      // be named. It belongs to no account and must never be resent or dropped.
      await store.write('txn-x', {
        'room_id': '!r:server',
        'txn_id': 'txn-x',
        'owner': null,
        'content': {'x': 1},
      });
      await outbox.remember('!r:server', 'txn-a', '@a:server', {'a': 1});

      // A signed-in account replays only its own half, not the ownerless one.
      final byA = <String>[];
      await outbox.flush((roomId, txnId, content) async {
        byA.add(txnId);
        return r'$evt';
      }, owner: '@a:server');
      expect(byA, ['txn-a'], reason: 'A does not own the ownerless record');

      // A caller with no account identity (null owner) claims nothing -- it must
      // NOT match the ownerless record via null == null.
      final byNobody = <String>[];
      await outbox.flush((roomId, txnId, content) async {
        byNobody.add(txnId);
        return r'$evt';
      }, owner: null);
      expect(byNobody, isEmpty, reason: 'a null-owner flush owns nothing');

      expect(
        (await store.readAll()).map((r) => r['txn_id']),
        contains('txn-x'),
        reason: 'the ownerless record is left untouched throughout',
      );
    });

    test(
      'a replay the homeserver does not confirm is kept for next time',
      () async {
        final store = InMemoryPendingCallTranscriptStore();
        final outbox = CallTranscriptOutbox(store: store);
        await outbox.remember('!r:server', 'txn-1', '@a:server', {'a': 1});

        var attempts = 0;
        await outbox.flush((roomId, txnId, content) async {
          attempts++;
          return null; // an unknown room / an unconfirmed send
        }, owner: '@a:server');
        expect(attempts, 1);
        expect(
          await store.readAll(),
          hasLength(1),
          reason: 'kept because it did not land',
        );

        await outbox.flush(
          (roomId, txnId, content) async => r'$evt',
          owner: '@a:server',
        );
        expect(
          await store.readAll(),
          isEmpty,
          reason: 'the next launch lands it',
        );
      },
    );

    test('one half throwing on replay does not strand the others', () async {
      final store = InMemoryPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);
      await outbox.remember('!r:a', 'txn-a', '@a:server', {'x': 1});
      await outbox.remember('!r:b', 'txn-b', '@a:server', {'y': 2});

      final landed = <String>[];
      await outbox.flush((roomId, txnId, content) async {
        if (txnId == 'txn-a') throw StateError('boom');
        landed.add(txnId);
        return r'$evt';
      }, owner: '@a:server');

      expect(landed, ['txn-b']);
      final pending = await store.readAll();
      expect(
        pending.map((r) => r['txn_id']),
        ['txn-a'],
        reason: 'the one that threw is kept, the one that landed is drained',
      );
    });

    test(
      'two overlapping flushes send each pending half at most once',
      () async {
        final store = InMemoryPendingCallTranscriptStore();
        final outbox = CallTranscriptOutbox(store: store);
        await outbox.remember('!r:server', 'txn-1', '@a:server', {'a': 1});

        // The first flush's send is held in flight, so the second flush overlaps
        // it. Without a single-flight guard both would read the still-pending
        // record and send it, so the half would go out twice.
        final sendGate = Completer<void>();
        final sent = <String>[];
        Future<String?> send(
          String roomId,
          String txnId,
          dynamic content,
        ) async {
          sent.add(txnId);
          await sendGate.future;
          return r'$evt';
        }

        final first = outbox.flush(send, owner: '@a:server');
        final second = outbox.flush(send, owner: '@a:server');
        await Future<void>.delayed(Duration.zero);
        sendGate.complete();
        await Future.wait([first, second]);

        expect(
          sent,
          ['txn-1'],
          reason:
              'the overlapping flush joins the first; the half is sent once',
        );
      },
    );
  });

  group('SharedPreferencesPendingCallTranscriptStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'a remembered half survives a new store instance (a restart)',
      () async {
        const store = SharedPreferencesPendingCallTranscriptStore();
        await store.write('txn-1', {
          'room_id': '!r:server',
          'txn_id': 'txn-1',
          'owner': '@a:server',
          'content': {'a': 1},
        });

        // The next launch constructs a fresh instance and must still find it.
        const reborn = SharedPreferencesPendingCallTranscriptStore();
        final all = await reborn.readAll();
        expect(all, hasLength(1));
        expect(all.single['content'], {'a': 1});

        await reborn.remove('txn-1');
        expect(await reborn.readAll(), isEmpty);
      },
    );

    test('a malformed or unrelated record is skipped, not thrown', () async {
      SharedPreferences.setMockInitialValues({
        'pangea.call_transcript.pending.txn-bad': '{not json',
        'pangea.call_transcript.pending.txn-ok':
            '{"room_id":"!r:server","txn_id":"txn-ok","content":{"a":1}}',
        'unrelated.key': 'x',
      });
      const store = SharedPreferencesPendingCallTranscriptStore();

      final all = await store.readAll();
      expect(
        all.map((r) => r['txn_id']),
        ['txn-ok'],
        reason: 'only well-formed pending halves of ours are returned',
      );
    });

    test('a non-string prefixed value does not strand valid records', () async {
      // A prefixed key whose value is not a string -- a future version, or
      // corruption, that wrote an int there. getString throws on it; the read
      // must skip that one key without discarding the valid record beside it.
      SharedPreferences.setMockInitialValues({
        'pangea.call_transcript.pending.txn-bad': 42,
        'pangea.call_transcript.pending.txn-ok':
            '{"room_id":"!r:server","txn_id":"txn-ok",'
            '"owner":"@a:server","content":{"a":1}}',
      });
      const store = SharedPreferencesPendingCallTranscriptStore();

      final all = await store.readAll();
      expect(
        all.map((r) => r['txn_id']),
        ['txn-ok'],
        reason: 'the non-string value is skipped, the valid record survives',
      );
    });

    test('a record whose txn id does not match its key cannot delete another '
        'account\'s genuine half', () async {
      // Account B's genuine unsent half, correctly keyed by its own txn id;
      // and a crafted entry stored under its OWN key but DECLARING B's txn id
      // (and A's owner) -- aimed at making A's flush call remove('txn-B') and
      // erase B's half, since the store drops a record by its own txn id.
      SharedPreferences.setMockInitialValues({
        'pangea.call_transcript.pending.txn-B':
            '{"room_id":"!b:server","txn_id":"txn-B",'
            '"owner":"@b:server","content":{"b":1}}',
        'pangea.call_transcript.pending.txn-crafted':
            '{"room_id":"!x:server","txn_id":"txn-B",'
            '"owner":"@a:server","content":{"x":1}}',
      });
      const store = SharedPreferencesPendingCallTranscriptStore();
      final outbox = CallTranscriptOutbox(store: store);

      // Account A replays; every send confirms.
      await outbox.flush(
        (roomId, txnId, content) async => r'$evt',
        owner: '@a:server',
      );

      // B's genuine half must survive: the crafted entry's txn id disagrees
      // with its key, so it is rejected on read and never drives a
      // remove('txn-B') against B's real entry.
      final all = await store.readAll();
      expect(
        all.any((r) => r['owner'] == '@b:server'),
        isTrue,
        reason: 'a crafted mismatched entry must not delete B\'s genuine half',
      );
    });
  });

  group('read the room before every resend (#9302)', () {
    setUp(CallHalfInFlight.resetForTest);

    Future<InMemoryPendingCallTranscriptStore> seeded() async {
      final store = InMemoryPendingCallTranscriptStore();
      await CallTranscriptOutbox(
        store: store,
      ).remember('!r:server', 'txn-1', '@a:server', {'call_key': r'$k'});
      return store;
    }

    test('a half already in the room is dropped without a resend', () async {
      final store = await seeded();
      final sends = <String>[];
      await CallTranscriptOutbox(store: store).flush(
        (roomId, txnId, content) async {
          sends.add(txnId);
          return r'$evt';
        },
        owner: '@a:server',
        inRoom: (roomId, content) async => true,
      );
      expect(sends, isEmpty);
      expect(await store.readAll(), isEmpty);
    });

    test('a half not in the room is resent under its original id', () async {
      final store = await seeded();
      final sends = <String>[];
      await CallTranscriptOutbox(store: store).flush(
        (roomId, txnId, content) async {
          sends.add(txnId);
          return r'$evt';
        },
        owner: '@a:server',
        inRoom: (roomId, content) async => false,
      );
      expect(sends, ['txn-1']);
      expect(await store.readAll(), isEmpty);
    });

    test(
      'a room that cannot be read sends nothing and keeps the half',
      () async {
        final store = await seeded();
        final sends = <String>[];
        await CallTranscriptOutbox(store: store).flush(
          (roomId, txnId, content) async {
            sends.add(txnId);
            return r'$evt';
          },
          owner: '@a:server',
          inRoom: (roomId, content) async => null,
        );
        expect(sends, isEmpty);
        expect(await store.readAll(), hasLength(1));
      },
    );

    test('a half the live finish is publishing is skipped', () async {
      final store = await seeded();
      final live = CallHalfInFlight.claim('txn-1');
      final sends = <String>[];
      await CallTranscriptOutbox(store: store).flush(
        (roomId, txnId, content) async {
          sends.add(txnId);
          return r'$evt';
        },
        owner: '@a:server',
        inRoom: (roomId, content) async => false,
      );
      expect(sends, isEmpty);
      expect(await store.readAll(), hasLength(1));
      CallHalfInFlight.release(live);
    });

    test('a record remembers when it was held back', () async {
      final store = await seeded();
      expect((await store.readAll()).single['remembered_at'], isA<int>());
    });

    test(
      'a send that confirms after its attempt was parked leaves the record',
      () async {
        final store = InMemoryPendingCallTranscriptStore();
        final outbox = CallTranscriptOutbox(store: store);
        final confirm = Completer<String?>();
        final send = outbox.guard(
          '!r:server',
          '@a:server',
          (content, txnId) => confirm.future,
        );
        final attempt = AttemptToken();
        final sending = attempt.run(() => send({'a': 1}, 'txn-1'));
        await pumpEventQueue();
        attempt.live = false; // the attempt's deadline won
        confirm.complete(r'$late');
        await sending;
        expect(
          await store.readAll(),
          hasLength(1),
          reason: 'only a live attempt may drop the record',
        );
      },
    );
  });
}

/// A store whose `write` does not complete until [_gate] does -- a genuinely
/// async write, so a test can prove the send waits for the persist rather than
/// relying on an in-memory write that happens to finish synchronously.
class _GatedWriteStore implements PendingCallTranscriptStore {
  _GatedWriteStore(this._gate);

  final Future<void> _gate;
  final List<Map<String, dynamic>> written = [];

  @override
  Future<void> write(String txnId, Map<String, dynamic> record) async {
    await _gate;
    written.add(Map<String, dynamic>.of(record));
  }

  @override
  Future<List<Map<String, dynamic>>> readAll() async =>
      written.map(Map<String, dynamic>.of).toList();

  @override
  Future<void> remove(String txnId) async {
    written.removeWhere((r) => r['txn_id'] == txnId);
  }
}
