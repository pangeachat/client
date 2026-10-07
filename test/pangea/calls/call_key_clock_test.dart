import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_key_clock.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

const _me = '@me:server';
const _peer = '@peer:server';
const _key = r'$caller-membership';

/// The call id is the room id: one live call per direct chat.
const _room = '!r:server';

Future<Client> _client() async => Client(
  'call-key-clock-test',
  database: await MatrixSdkDatabase.init(
    'call-key-clock-test',
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  ),
);

Event _membership(
  Room room, {
  required String id,
  String sender = _me,
  String device = 'DEVA',
  String callId = _room,
  String type = EventTypes.GroupCallMember,
}) => Event(
  type: type,
  content: {
    'memberships': [
      {'call_id': callId, 'device_id': device, 'application': 'm.call'},
    ],
  },
  eventId: id,
  senderId: sender,
  originServerTs: DateTime.utc(2026, 10, 7),
  room: room,
);

MatrixEvent _clockEvent({
  required String id,
  required String sender,
  required int epoch,
  required String device,
  required String anchor,
  DateTime? ts,
  String key = _key,
}) => MatrixEvent(
  type: CallClockContent.type,
  content: CallClockContent(
    callKey: key,
    epochSfuMs: epoch,
    writerDeviceId: device,
    writerAnchorId: anchor,
  ).toContent(),
  eventId: id,
  senderId: sender,
  originServerTs: ts ?? DateTime.utc(2026, 10, 7, 12),
);

CallClockCandidate _candidate({
  required String id,
  required ClockProvenance provenance,
  required String anchor,
  DateTime? ts,
  int epoch = 1000,
}) => CallClockCandidate(
  eventId: id,
  senderId: _me,
  originServerTs: ts ?? DateTime.utc(2026, 10, 7, 12),
  content: CallClockContent(
    callKey: _key,
    epochSfuMs: epoch,
    writerDeviceId: 'DEVA',
    writerAnchorId: anchor,
  ),
  provenance: provenance,
);

void main() {
  group('pangea.call_in_progress', () {
    test('round-trips, and a partial record names no call', () {
      const record = CallInProgress(
        callKey: _key,
        callerId: _peer,
        writerDeviceId: 'DEVA',
        writerMembershipEventId: r'$m',
      );
      final back = CallInProgress.fromJson(record.toJson())!;
      expect(back.callKey, _key);
      expect(back.callerId, _peer);
      expect(back.writerDeviceId, 'DEVA');
      expect(back.writerMembershipEventId, r'$m');
      expect(
        CallInProgress.fromJson({'call_key': _key, 'writer_device_id': 'D'}),
        isNull,
      );
      expect(CallInProgress.fromJson(null), isNull);
    });

    const record = CallInProgress(
      callKey: _key,
      callerId: _peer,
      writerDeviceId: 'DEVA',
      writerMembershipEventId: r'$m',
    );

    test('a joiner adopts it only from a sibling present now whose '
        'membership is current', () {
      bool accepts({
        Iterable<String> siblings = const ['DEVA'],
        bool current = true,
      }) => CallInProgress.accepts(
        data: record,
        siblingDeviceIdsInSfu: siblings,
        isCurrentOwnMembership: (id) => current && id == r'$m',
        myDeviceId: 'DEVB',
        rejoinAnchor: null,
      );
      expect(accepts(), isTrue);
      expect(
        accepts(siblings: const ['DEVC']),
        isFalse,
        reason: 'the writer is not in the call now',
      );
      expect(
        accepts(current: false),
        isFalse,
        reason: 'a membership that is no longer current is an earlier call',
      );
    });

    test('a rejoin adopts its OWN record written with the anchor it returns '
        'to, and nothing else on that road', () {
      bool rejoin(String anchor, {String me = 'DEVA'}) =>
          CallInProgress.accepts(
            data: record,
            siblingDeviceIdsInSfu: const [],
            isCurrentOwnMembership: (_) => false,
            myDeviceId: me,
            rejoinAnchor: anchor,
          );
      expect(rejoin(r'$m'), isTrue);
      expect(rejoin(r'$other'), isFalse);
      expect(rejoin(r'$m', me: 'DEVB'), isFalse);
    });
  });

  group('the current-ring fallback', () {
    late Room room;
    setUp(() async => room = Room(id: '!r:server', client: await _client()));

    Event ring(String id, String membership, DateTime at, {String? kind}) =>
        Event(
          type: PangeaEventTypes.callNotification,
          content: {
            'application': {
              'type': 'm.call',
              'notification_type': kind ?? 'ring',
            },
            'm.relates_to': {'rel_type': 'm.reference', 'event_id': membership},
          },
          eventId: id,
          senderId: _peer,
          originServerTs: at,
          room: room,
        );

    test('takes the latest ring whose membership is still current', () {
      final events = [
        ring(r'$r1', r'$old', DateTime.utc(2026, 10, 7, 10)),
        ring(r'$r2', r'$live', DateTime.utc(2026, 10, 7, 11)),
        ring(r'$r3', r'$stale', DateTime.utc(2026, 10, 7, 12)),
        ring(r'$r4', r'$notify', DateTime.utc(2026, 10, 7, 13), kind: 'x'),
      ];
      final found = keyFromCurrentRing(
        events,
        (sender, id) => sender == _peer && (id == r'$live' || id == r'$old'),
      );
      expect(found?.key, r'$live');
      expect(found?.caller, _peer);
      expect(keyFromCurrentRing(events, (_, _) => false), isNull);
    });
  });

  group('pangea.call_clock content', () {
    test('the transaction id is length-framed over every interior field', () {
      expect(
        CallClockContent.txnId('a:b', 'c', 'd'),
        isNot(CallClockContent.txnId('a', 'b:c', 'd')),
      );
      expect(
        CallClockContent.txnId('a', 'b:c', 'd'),
        isNot(CallClockContent.txnId('a', 'b', 'c:d')),
      );
      expect(
        CallClockContent.txnId(_key, _me, 'DEVA'),
        CallClockContent.txnId(_key, _me, 'DEVA'),
        reason: 'a retry is the same transaction',
      );
    });

    test('parses only a whole, self-consistent event', () {
      const content = CallClockContent(
        callKey: _key,
        epochSfuMs: 1700000000000,
        writerDeviceId: 'DEVA',
        writerAnchorId: _key,
      );
      final json = content.toContent();
      expect(CallClockContent.fromJson(json)?.epochSfuMs, 1700000000000);
      expect(
        CallClockContent.fromJson({
          ...json,
          'm.relates_to': {'rel_type': CallClockContent.type, 'event_id': 'x'},
        }),
        isNull,
        reason: 'relating to a different call than it names',
      );
      expect(CallClockContent.fromJson({...json, 'epoch_sfu_ms': 0}), isNull);
      expect(
        CallClockContent.fromJson({...json, 'writer_device_id': ''}),
        isNull,
      );
    });

    test('the epoch is the later of the two accounts\' earliest joins', () {
      expect(CallClockContent.epochFromJoins([500, 300], [900, 700]), 700);
      expect(CallClockContent.epochFromJoins([800], [100, 400]), 800);
      expect(
        CallClockContent.epochFromJoins([300, 900], [500]),
        500,
        reason: "an account's LATER device does not move the start",
      );
      expect(CallClockContent.epochFromJoins([], [100]), isNull);
      expect(CallClockContent.epochFromJoins([100], []), isNull);
    });

    test(
      'a join reads at the millisecond only where it refines the second',
      () {
        expect(
          CallClockContent.sfuJoinMs((secondsMs: 5000, ms: 5250), null),
          5250,
        );
        expect(
          CallClockContent.sfuJoinMs((secondsMs: 5000, ms: 0), null),
          5000,
          reason: 'an older SFU sends no millisecond half',
        );
        expect(
          CallClockContent.sfuJoinMs(
            null,
            DateTime.fromMillisecondsSinceEpoch(7000),
          ),
          7000,
        );
        expect(CallClockContent.sfuJoinMs(null, null), isNull);
      },
    );

    test('only the device whose own membership IS the key writes, '
        'and never from a rejoin', () {
      expect(
        CallClockContent.isPrimaryWriter(
          callKey: _key,
          ownAnchorId: _key,
          rejoined: false,
        ),
        isTrue,
      );
      expect(
        CallClockContent.isPrimaryWriter(
          callKey: _key,
          ownAnchorId: r'$sibling-membership',
          rejoined: false,
        ),
        isFalse,
      );
      expect(
        CallClockContent.isPrimaryWriter(
          callKey: _key,
          ownAnchorId: _key,
          rejoined: true,
        ),
        isFalse,
      );
    });

    test('the fallback writer is the first device of the account that did '
        'NOT place the call, with a current membership', () {
      bool fallback({
        String me = _peer,
        String device = 'DEVA',
        List<String> siblings = const ['DEVB'],
        bool current = true,
        bool rejoined = false,
      }) => CallClockContent.isFallbackWriter(
        rejoined: rejoined,
        callerId: _me,
        myUserId: me,
        myDeviceId: device,
        siblingDeviceIds: siblings,
        ownMembershipCurrent: current,
      );
      expect(fallback(), isTrue);
      expect(fallback(me: _me), isFalse, reason: 'the caller account');
      expect(fallback(device: 'DEVC'), isFalse, reason: 'not first by id');
      expect(fallback(current: false), isFalse);
      expect(fallback(rejoined: true), isFalse);
    });
  });

  group('clock provenance', () {
    late Room room;
    setUp(() async => room = Room(id: '!r:server', client: await _client()));

    const content = CallClockContent(
      callKey: _key,
      epochSfuMs: 1000,
      writerDeviceId: 'DEVA',
      writerAnchorId: _key,
    );

    ClockProvenance judge({
      String sender = _me,
      Event? membership,
      bool useDefault = true,
      bool failed = false,
      String? callId = _room,
    }) => judgeClockProvenance(
      clockSenderId: sender,
      content: content,
      dmMembers: const {_me, _peer},
      callId: callId,
      membership: useDefault
          ? (membership ?? _membership(room, id: _key))
          : membership,
      fetchFailed: failed,
    );

    test(
      'a writer membership that matches sender, device and call is valid',
      () {
        expect(judge(), ClockProvenance.valid);
      },
    );

    test('anything that does not check out is invalid', () {
      expect(judge(sender: '@stranger:server'), ClockProvenance.invalid);
      expect(judge(useDefault: false), ClockProvenance.invalid);
      expect(
        judge(
          membership: _membership(room, id: _key, sender: _peer),
        ),
        ClockProvenance.invalid,
        reason: 'the membership is somebody else\'s',
      );
      expect(
        judge(
          membership: _membership(room, id: _key, device: 'DEVB'),
        ),
        ClockProvenance.invalid,
        reason: 'the named device did not hold that membership',
      );
      expect(
        judge(
          membership: _membership(room, id: _key, callId: 'other'),
        ),
        ClockProvenance.invalid,
      );
      expect(
        judge(
          membership: _membership(room, id: _key, type: 'm.room.message'),
        ),
        ClockProvenance.invalid,
      );
    });

    test('a lookup that failed is pending, not invalid', () {
      expect(judge(failed: true), ClockProvenance.pending);
      expect(judge(callId: null), ClockProvenance.pending);
    });
  });

  group('the total order', () {
    test('a valid primary beats an earlier fallback', () {
      final chosen = chooseCallClock([
        _candidate(
          id: r'$fallback',
          provenance: ClockProvenance.valid,
          anchor: r'$peer-membership',
          ts: DateTime.utc(2026, 10, 7, 11),
        ),
        _candidate(
          id: r'$primary',
          provenance: ClockProvenance.valid,
          anchor: _key,
          ts: DateTime.utc(2026, 10, 7, 12),
        ),
      ]);
      expect(chosen?.eventId, r'$primary');
    });

    test('then the earliest timestamp, then the smallest event id', () {
      final early = DateTime.utc(2026, 10, 7, 11);
      expect(
        chooseCallClock([
          _candidate(id: r'$b', provenance: ClockProvenance.valid, anchor: 'x'),
          _candidate(
            id: r'$c',
            provenance: ClockProvenance.valid,
            anchor: 'x',
            ts: early,
          ),
        ])?.eventId,
        r'$c',
      );
      expect(
        chooseCallClock([
          _candidate(
            id: r'$b',
            provenance: ClockProvenance.valid,
            anchor: _key,
          ),
          _candidate(
            id: r'$a',
            provenance: ClockProvenance.valid,
            anchor: _key,
          ),
        ])?.eventId,
        r'$a',
      );
    });

    test('an invalid or pending event is never chosen, whatever it claims', () {
      expect(
        chooseCallClock([
          _candidate(
            id: r'$forged',
            provenance: ClockProvenance.invalid,
            anchor: _key,
          ),
          _candidate(
            id: r'$pending',
            provenance: ClockProvenance.pending,
            anchor: _key,
          ),
        ]),
        isNull,
      );
      expect(
        _candidate(
          id: r'$forged',
          provenance: ClockProvenance.invalid,
          anchor: _key,
        ).isPrimary,
        isFalse,
      );
    });
  });

  group('the coordinator', () {
    late Room room;
    setUp(() async => room = Room(id: '!r:server', client: await _client()));

    ({
      CallKeyClock clock,
      List<Map<String, Object?>> accountData,
      List<(Map<String, Object?>, String)> sent,
      List<int> epochs,
      List<MatrixEvent> relations,
      Map<String, Event> memberships,
      StreamController<void> arrivals,
      List<bool> failFetch,
    })
    build() {
      final accountData = <Map<String, Object?>>[];
      final sent = <(Map<String, Object?>, String)>[];
      final epochs = <int>[];
      final relations = <MatrixEvent>[];
      final memberships = <String, Event>{};
      final arrivals = StreamController<void>.broadcast();
      final failFetch = <bool>[false];
      final clock = CallKeyClock(
        writeCallInProgress: (content) async => accountData.add(content),
        sendClock: (content, txn) async => sent.add((content, txn)),
        fetchClockEvents: (key) async => List.of(relations),
        fetchEvent: (id) async {
          if (failFetch.first) throw StateError('offline');
          return memberships[id];
        },
        clockArrivals: arrivals.stream,
        onEpoch: epochs.add,
        dmMembers: () => {_me, _peer},
        callId: () => _room,
      );
      return (
        clock: clock,
        accountData: accountData,
        sent: sent,
        epochs: epochs,
        relations: relations,
        memberships: memberships,
        arrivals: arrivals,
        failFetch: failFetch,
      );
    }

    void arrive(
      CallKeyClock clock, {
      required bool primary,
      bool fallback = false,
      int? Function()? epoch,
      String anchor = _key,
    }) => clock.peerArrived(
      callKey: _key,
      isPrimaryWriter: primary,
      isFallbackWriter: () => fallback,
      epochSfuMs: epoch ?? () => 5000,
      writerSenderId: _me,
      writerDeviceId: 'DEVA',
      writerAnchorId: () => anchor,
    );

    test('records the key once per membership, again after a rejoin', () {
      fakeAsync((async) {
        final t = build();
        for (var i = 0; i < 3; i++) {
          t.clock.keyResolved(
            callKey: _key,
            callerId: _me,
            writerDeviceId: 'DEVA',
            writerMembershipEventId: r'$m1',
          );
        }
        t.clock.keyResolved(
          callKey: _key,
          callerId: _me,
          writerDeviceId: 'DEVA',
          writerMembershipEventId: r'$m2',
        );
        async.flushMicrotasks();
        expect(t.accountData.map((c) => c['writer_membership_event_id']), [
          r'$m1',
          r'$m2',
        ]);
        expect(t.accountData.first['call_key'], _key);
        t.clock.dispose();
      });
    });

    test('the primary writer sends its epoch once, under the framed id', () {
      fakeAsync((async) {
        final t = build();
        arrive(t.clock, primary: true);
        arrive(t.clock, primary: true);
        async.flushMicrotasks();
        expect(t.sent, hasLength(1));
        final (content, txn) = t.sent.single;
        expect(content['epoch_sfu_ms'], 5000);
        expect(content['writer_anchor_id'], _key);
        expect(txn, CallClockContent.txnId(_key, _me, 'DEVA'));
        t.clock.dispose();
      });
    });

    test('a primary with no epoch yet writes once one can be formed', () {
      fakeAsync((async) {
        final t = build();
        int? epoch;
        arrive(t.clock, primary: true, epoch: () => epoch);
        async.flushMicrotasks();
        expect(t.sent, isEmpty);
        epoch = 7000;
        arrive(t.clock, primary: true, epoch: () => epoch);
        async.flushMicrotasks();
        expect(t.sent.single.$1['epoch_sfu_ms'], 7000);
        t.clock.dispose();
      });
    });

    test('a non-writer never sends; the fallback writer sends only when no '
        'valid clock arrived in its window', () {
      fakeAsync((async) {
        final t = build();
        arrive(t.clock, primary: false, fallback: true, anchor: r'$peer-m');
        async.elapse(const Duration(seconds: 29));
        expect(t.sent, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(t.sent.single.$1['writer_anchor_id'], r'$peer-m');
        t.clock.dispose();
      });

      fakeAsync((async) {
        final t = build();
        t.relations.add(
          _clockEvent(
            id: r'$c1',
            sender: _me,
            epoch: 4000,
            device: 'DEVA',
            anchor: _key,
          ),
        );
        t.memberships[_key] = _membership(room, id: _key);
        arrive(t.clock, primary: false, fallback: true);
        async.elapse(const Duration(seconds: 31));
        expect(t.sent, isEmpty, reason: 'a valid clock is already in force');
        expect(t.epochs, [4000]);
        t.clock.dispose();
      });

      fakeAsync((async) {
        final t = build();
        arrive(t.clock, primary: false);
        async.elapse(const Duration(seconds: 31));
        expect(t.sent, isEmpty, reason: 'not the fallback writer');
        t.clock.dispose();
      });
    });

    test('a fallback writer that cannot form an epoch at its window keeps '
        'trying, and writes once it can', () {
      fakeAsync((async) {
        final t = build();
        int? epoch;
        arrive(
          t.clock,
          primary: false,
          fallback: true,
          epoch: () => epoch,
          anchor: r'$peer-m',
        );
        async.elapse(const Duration(seconds: 31));
        expect(t.sent, isEmpty);
        epoch = 6000;
        async.elapse(const Duration(seconds: 10));
        expect(t.sent.single.$1['epoch_sfu_ms'], 6000);
        async.elapse(const Duration(seconds: 60));
        expect(t.sent, hasLength(1), reason: 'written once');
        t.clock.dispose();
      });
    });

    test('readers snap to the chosen clock and re-choose when a better one '
        'arrives', () {
      fakeAsync((async) {
        final t = build();
        t.memberships[r'$peer-m'] = _membership(
          room,
          id: r'$peer-m',
          sender: _peer,
          device: 'PEERDEV',
        );
        t.memberships[_key] = _membership(room, id: _key);
        t.relations.add(
          _clockEvent(
            id: r'$fallback',
            sender: _peer,
            epoch: 4000,
            device: 'PEERDEV',
            anchor: r'$peer-m',
            ts: DateTime.utc(2026, 10, 7, 11),
          ),
        );
        arrive(t.clock, primary: false);
        async.flushMicrotasks();
        expect(t.epochs, [4000]);

        t.relations.add(
          _clockEvent(
            id: r'$primary',
            sender: _me,
            epoch: 3900,
            device: 'DEVA',
            anchor: _key,
            ts: DateTime.utc(2026, 10, 7, 12),
          ),
        );
        t.arrivals.add(null);
        async.flushMicrotasks();
        expect(t.epochs, [4000, 3900]);
        expect(t.clock.chosenEpochSfuMs, 3900);
        t.clock.dispose();
      });
    });

    test(
      'a forged primary (sibling or stranger claiming the key) is ignored',
      () {
        fakeAsync((async) {
          final t = build();
          // A sibling writes claiming the key as its anchor, but the key's
          // membership belongs to a different device.
          t.memberships[_key] = _membership(room, id: _key, device: 'DEVA');
          t.relations.add(
            _clockEvent(
              id: r'$forged',
              sender: _me,
              epoch: 1,
              device: 'DEVB',
              anchor: _key,
            ),
          );
          // A stranger to the chat writes one whose membership checks out on
          // every other count -- it is still not a member of this chat.
          t.memberships[r'$stranger-m'] = _membership(
            room,
            id: r'$stranger-m',
            sender: '@stranger:server',
            device: 'SDEV',
          );
          t.relations.add(
            _clockEvent(
              id: r'$stranger',
              sender: '@stranger:server',
              epoch: 2,
              device: 'SDEV',
              anchor: r'$stranger-m',
            ),
          );
          arrive(t.clock, primary: false);
          async.flushMicrotasks();
          expect(t.epochs, isEmpty);
          t.clock.dispose();
        });
      },
    );

    test('a failed writer lookup keeps the current value and retries', () {
      fakeAsync((async) {
        final t = build();
        t.memberships[r'$peer-m'] = _membership(
          room,
          id: r'$peer-m',
          sender: _peer,
          device: 'PEERDEV',
        );
        t.memberships[_key] = _membership(room, id: _key);
        t.relations.add(
          _clockEvent(
            id: r'$fallback',
            sender: _peer,
            epoch: 4000,
            device: 'PEERDEV',
            anchor: r'$peer-m',
          ),
        );
        arrive(t.clock, primary: false);
        async.flushMicrotasks();
        expect(t.epochs, [4000]);

        // The primary lands, but its writer cannot be looked up right now.
        t.relations.add(
          _clockEvent(
            id: r'$primary',
            sender: _me,
            epoch: 3900,
            device: 'DEVA',
            anchor: _key,
          ),
        );
        t.failFetch[0] = true;
        t.arrivals.add(null);
        async.flushMicrotasks();
        expect(t.epochs, [4000], reason: 'nothing chosen is dropped');
        expect(t.clock.chosenEpochSfuMs, 4000);

        t.failFetch[0] = false;
        async.elapse(const Duration(seconds: 11));
        expect(t.epochs, [4000, 3900]);
        t.clock.dispose();
      });
    });
  });
}
