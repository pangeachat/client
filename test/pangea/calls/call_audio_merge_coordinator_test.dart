import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/expiring_storage_box.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merge_coordinator.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

/// The P3b coordinator's orchestration -- election, triggers, durable
/// reconciliation -- driven end-to-end over fakes: a shared relations backend,
/// a controllable download/upload/mix/send, a real (temp-backed)
/// [ExpiringStorageBox] index, and a fully manual clock + timer scheduler. No
/// homeserver, no real time.
///
/// Every governing rule the design pins is exercised by at least one test whose
/// green depends on that rule; the load-bearing ones (firstSeenAt-anchored
/// expiry, re-validate-before-send, permit-until-settle, drain-until-clean,
/// terminal-vs-transient) were additionally mutation-proven to flip red when
/// their rule is reverted.

const _room = '!room:example.com';
const _callKey = '\$membership:example.com';
const _alice = '@alice:example.com';
const _bob = '@bob:example.com';
const _carol = '@carol:example.com';
const _deviceA = 'A1';
const _deviceB = 'B1';
const _deviceC = 'C1';

const _boxTtl = Duration(days: 30);
const _indexTtl = Duration(days: 7);
const _settleDelay = Duration(seconds: 8);
const _baseBackoff = Duration(seconds: 10);
const _stageTimeout = Duration(seconds: 30);
const _drainInterval = Duration(minutes: 1);

const _aliceEvent = '\$alice_half:example.com';
const _bobEvent = '\$bob_half:example.com';
const _carolEvent = '\$carol_half:example.com';

Future<void> _pump() => pumpEventQueue(times: 80);

// -----------------------------------------------------------------------------
// Builders.
// -----------------------------------------------------------------------------

/// One placeable-by-default `pangea.call_audio` half event, as the relations
/// API would return it.
MatrixEvent _half(
  String sender,
  String device, {
  required String eventId,
  String callKey = _callKey,
  int fileStartSfuMs = 1000,
  bool truncated = false,
  String codec = kCallAudioCodec,
  int channels = 1,
  DateTime? ts,
}) => MatrixEvent(
  type: CallAudioContent.relType,
  eventId: eventId,
  senderId: sender,
  originServerTs: ts ?? DateTime.fromMillisecondsSinceEpoch(0),
  content: CallAudioContent(
    callKey: callKey,
    deviceId: device,
    url: 'mxc://example.com/audio_$device',
    mimetype: 'audio/wav',
    size: 4096,
    durationMs: 30000,
    sampleRate: 16000,
    channels: channels,
    codec: codec,
    clockAnchor: ClockAnchor(sfuMs: fileStartSfuMs, deviceMs: fileStartSfuMs),
    recordingStartedOffsetFromDeviceJoinMs: 0,
    truncated: truncated,
  ).toJson(),
);

// -----------------------------------------------------------------------------
// Shared relations backend (one room; keyed by call key).
// -----------------------------------------------------------------------------

class _Backend {
  final Map<String, List<MatrixEvent>> _halves = {};
  final Map<String, List<MatrixEvent>> _merged = {};
  var _mergedSeq = 0;

  /// Optional hook awaited before serving a fetch, so a test can gate or hang a
  /// specific `(relType, callKey)` read.
  Future<void> Function(String relType, String callKey)? beforeFetch;

  void setHalves(String callKey, List<MatrixEvent> halves) =>
      _halves[callKey] = List<MatrixEvent>.from(halves);

  void addHalf(String callKey, MatrixEvent half) =>
      _halves.putIfAbsent(callKey, () => []).add(half);

  void addMergedContent(String callKey, Map<String, dynamic> content) {
    _merged
        .putIfAbsent(callKey, () => [])
        .add(
          MatrixEvent(
            type: CallAudioMergedContent.relType,
            eventId: '\$merged_${_mergedSeq++}:example.com',
            senderId: content['sender'] as String? ?? _alice,
            originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
            content: content,
          ),
        );
  }

  void addMergedEvent(String callKey) {
    final content = CallAudioMergedContent(
      callKey: callKey,
      url: 'mxc://example.com/merged',
      mimetype: 'audio/wav',
      size: 8192,
      durationMs: 60000,
      sampleRate: 48000,
      channels: 1,
      codec: kCallAudioCodec,
      sourceEventIds: const [_aliceEvent, _bobEvent],
    ).toJson();
    addMergedContent(callKey, content);
  }

  RelationsFetcher get fetch =>
      ({
        required String roomId,
        required String eventId,
        required String relType,
        String? from,
      }) async {
        expect(roomId, _room);
        final hook = beforeFetch;
        if (hook != null) await hook(relType, eventId);
        final source = relType == CallAudioMergedContent.relType
            ? _merged[eventId]
            : _halves[eventId];
        return (
          chunk: List<MatrixEvent>.from(source ?? const <MatrixEvent>[]),
          nextBatch: null,
        );
      };
}

// -----------------------------------------------------------------------------
// Manual clock + timer scheduler (no real time).
// -----------------------------------------------------------------------------

class _FakeTimer implements Timer {
  _FakeTimer(this._scheduler, this.due, this.callback, this.period);

  final _Scheduler _scheduler;
  DateTime due;
  final void Function() callback;
  final Duration? period;
  bool _active = true;

  @override
  void cancel() {
    _active = false;
    _scheduler._timers.remove(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

class _Scheduler {
  _Scheduler(this._now);

  DateTime _now;
  final List<_FakeTimer> _timers = [];

  DateTime now() => _now;

  Timer oneShot(Duration d, void Function() cb) => _add(d, cb, null);
  Timer periodic(Duration d, void Function() cb) => _add(d, cb, d);

  _FakeTimer _add(Duration d, void Function() cb, Duration? period) {
    final timer = _FakeTimer(this, _now.add(d), cb, period);
    _timers.add(timer);
    return timer;
  }

  /// Advances virtual time by [d], firing every due timer in order and draining
  /// microtasks + real (GetStorage) async between each fire.
  Future<void> elapse(Duration d) async {
    final target = _now.add(d);
    while (true) {
      _timers.removeWhere((t) => !t.isActive);
      _FakeTimer? next;
      for (final timer in _timers) {
        if (timer.isActive &&
            !timer.due.isAfter(target) &&
            (next == null || timer.due.isBefore(next.due))) {
          next = timer;
        }
      }
      if (next == null) break;
      _now = next.due;
      final cb = next.callback;
      if (next.period != null) {
        next.due = _now.add(next.period!);
      } else {
        next._active = false;
        _timers.remove(next);
      }
      cb();
      await _pump();
    }
    _now = target;
  }
}

// -----------------------------------------------------------------------------
// Harness: one coordinator over the backend, with controllable seams.
// -----------------------------------------------------------------------------

class _Harness {
  _Harness({
    required this.backend,
    required this.scheduler,
    required this.index,
    required String myUserId,
    required String? myDeviceId,
    this.maxConcurrent = 2,
    bool? Function(String roomId)? isDmRoom,
    Duration indexTtl = _indexTtl,
    Duration drainInterval = _drainInterval,
    int attemptCap = 2,
  }) : _myUserId = myUserId {
    coordinator = CallAudioMergeCoordinator(
      relationsFetch: backend.fetch,
      download: _download,
      upload: _upload,
      send: _send,
      mix: _mix,
      index: index,
      isDmRoom: isDmRoom ?? (_) => true,
      myUserId: () => myUserId,
      myDeviceId: () => myDeviceId,
      clock: scheduler.now,
      oneShotTimer: scheduler.oneShot,
      periodicTimer: scheduler.periodic,
      settleDelay: _settleDelay,
      baseBackoff: _baseBackoff,
      attemptCap: attemptCap,
      stageTimeout: _stageTimeout,
      drainInterval: drainInterval,
      indexTtl: indexTtl,
      mergeCeiling: const Duration(minutes: 30),
      maxConcurrent: maxConcurrent,
    );
  }

  final _Backend backend;
  final _Scheduler scheduler;
  final ExpiringStorageBox index;
  final int maxConcurrent;
  final String _myUserId;
  late final CallAudioMergeCoordinator coordinator;

  // Controls.
  Completer<void>? gateDownload;
  Completer<void>? gateUpload;
  Object? mixThrows;
  bool mixComplete = true;
  bool sendReturnsNull = false;
  Object? sendThrows;

  final List<Uri> downloadCalls = [];
  final List<Uint8List> uploadCalls = [];
  final List<CallAudioMergeRequest> mixCalls = [];
  final List<({Map<String, dynamic> content, String txnId})> sendCalls = [];

  Future<Uint8List> _download(Uri mxc) async {
    downloadCalls.add(mxc);
    final gate = gateDownload;
    if (gate != null) await gate.future;
    return Uint8List.fromList(const [0, 1, 2, 3]);
  }

  Future<Uri> _upload(
    Uint8List bytes, {
    required String filename,
    required String contentType,
  }) async {
    uploadCalls.add(bytes);
    final gate = gateUpload;
    if (gate != null) await gate.future;
    return Uri.parse('mxc://example.com/merged_upload');
  }

  Future<CallAudioMergeResult> _mix(CallAudioMergeRequest request) async {
    mixCalls.add(request);
    final err = mixThrows;
    if (err != null) throw err;
    return CallAudioMergeResult(
      wav: Uint8List.fromList(List<int>.filled(16, 7)),
      durationMs: 1000,
      sampleRate: 48000,
      channels: 1,
      sourceCoverage: request.sources.map((s) => s.senderId).toList()..sort(),
      complete: mixComplete,
    );
  }

  Future<String?> _send(Map<String, dynamic> content, String txnId) async {
    sendCalls.add((content: content, txnId: txnId));
    final err = sendThrows;
    if (err != null) throw err;
    if (sendReturnsNull) return null;
    final callKey = content['call_key'] as String;
    backend.addMergedContent(callKey, {...content, 'sender': _myUserId});
    return '\$merged_ack_${sendCalls.length}:example.com';
  }

  Map<String, dynamic>? entry(String callKey) => index.read('$_room|$callKey');
}

// -----------------------------------------------------------------------------
// Index construction (real GetStorage in a temp dir, fake clock).
// -----------------------------------------------------------------------------

var _boxSeq = 0;

Future<ExpiringStorageBox> _newIndex(
  _Scheduler scheduler, {
  String? name,
  bool erase = true,
}) async {
  final boxName = name ?? 'merge_coord_${_boxSeq++}';
  await GetStorage.init(boxName);
  if (erase) await GetStorage(boxName).erase();
  return ExpiringStorageBox(
    boxName,
    ttl: _boxTtl,
    payloadKey: 'p',
    now: scheduler.now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('merge_coord_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  _Scheduler freshClock() => _Scheduler(DateTime(2026, 1, 1, 12));

  group('a complete call', () {
    test(
      'posts exactly once with the right coverage and clears the index',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        );

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();

        expect(h.sendCalls, hasLength(1));
        expect(
          h.sendCalls.single.content['source_event_ids'],
          [_aliceEvent, _bobEvent],
          reason: 'coverage is the two sorted half ids',
        );
        expect(h.entry(_callKey), isNull, reason: 'the index entry is cleared');
      },
    );
  });

  group('an already-merged call', () {
    test('posts nothing and clears the index', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ])
        ..addMergedEvent(_callKey);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      );

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();

      expect(h.sendCalls, isEmpty);
      expect(h.entry(_callKey), isNull);
    });
  });

  group('a late second half', () {
    test(
      'completes a call held only in the index, via the onSync handler',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        );

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        expect(h.sendCalls, isEmpty, reason: 'incomplete: only one half');
        expect(h.entry(_callKey), isNotNull, reason: 'held in the index');

        backend.addHalf(_callKey, _half(_bob, _deviceB, eventId: _bobEvent));
        h.coordinator.onSyncedCallAudio(_room, _callKey);
        await _pump();

        expect(h.sendCalls, hasLength(1));
        expect(h.entry(_callKey), isNull);
      },
    );
  });

  group('election between two devices', () {
    test(
      'rank 1 stands down when rank 0 posts within its longer delay',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final rank0 = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        );
        final rank1 = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _bob,
          myDeviceId: _deviceB,
        );

        rank0.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        rank1.coordinator.onCallFinished(_room, _callKey, _bob, _deviceB);
        await _pump();

        // rank 0 (baseBackoff * 0) posts immediately; rank 1 is parked on its
        // baseBackoff wait.
        expect(rank0.sendCalls, hasLength(1));
        expect(rank1.sendCalls, isEmpty);

        // rank 0's merged event reaches rank 1 as a sync, mid-backoff: it stands
        // down without posting.
        rank1.coordinator.onSyncedMergedEvent(_room, _callKey);
        await _pump();
        await scheduler.elapse(_baseBackoff * 2);
        await _pump();

        expect(rank1.sendCalls, isEmpty, reason: 'rank 1 stood down');
        expect(rank1.entry(_callKey), isNull);
      },
    );

    test('rank 1 still posts if rank 0 never does', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final rank1 = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _bob,
        myDeviceId: _deviceB,
      );

      rank1.coordinator.onCallFinished(_room, _callKey, _bob, _deviceB);
      await _pump();
      expect(rank1.sendCalls, isEmpty, reason: 'parked on the rank-1 backoff');

      await scheduler.elapse(_baseBackoff);
      await _pump();

      expect(rank1.sendCalls, hasLength(1), reason: 'no rank 0 appeared');
      expect(rank1.entry(_callKey), isNull);
    });
  });

  group('the settle delay', () {
    test('holds the first attempt until it elapses', () async {
      final scheduler = freshClock();
      final now = scheduler.now();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent, ts: now),
          _half(_bob, _deviceB, eventId: _bobEvent, ts: now),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      );

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();
      expect(h.sendCalls, isEmpty, reason: 'still inside the settle window');

      await scheduler.elapse(_settleDelay);
      await _pump();
      expect(h.sendCalls, hasLength(1));
    });
  });

  group('a call with more than two halves', () {
    test('retires terminal, no post', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
          _half(_carol, _deviceC, eventId: _carolEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      );

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();

      expect(h.sendCalls, isEmpty);
      expect(h.entry(_callKey), isNull, reason: 'terminal: removed from index');
    });
  });

  group('re-validation before upload and send (rule 3)', () {
    test(
      'a coverage change before the before-UPLOAD re-validate aborts',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        )..gateDownload = Completer<void>();

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        // Parked on the (gated) download, after the initial decide but before the
        // before-upload re-validate. Change bob's half id: same shape, new
        // coverage.
        backend.setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: '\$bob_half_2:example.com'),
        ]);
        h.gateDownload!.complete();
        await _pump();

        expect(h.uploadCalls, isEmpty, reason: 'aborted before upload');
        expect(h.sendCalls, isEmpty);
      },
    );

    test(
      'a coverage change before the before-SEND re-validate aborts',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        )..gateUpload = Completer<void>();

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        // The before-upload re-validate passed (coverage unchanged); parked on
        // the gated upload. NOW change coverage, so only the before-SEND
        // re-validate can catch it.
        expect(h.uploadCalls, hasLength(1), reason: 'reached upload');
        backend.setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: '\$bob_half_2:example.com'),
        ]);
        h.gateUpload!.complete();
        await _pump();

        expect(h.sendCalls, isEmpty, reason: 'aborted before send');
      },
    );

    test(
      'a THIRD half arriving before the re-validate retires terminal (a device '
      'switch, out of v1 scope) rather than drifting coverage',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        )..gateDownload = Completer<void>();

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        // Parked on the gated download after the two-half decide. A THIRD half
        // (bob switched devices mid-call) lands before the before-upload
        // re-validate. Unlike a same-count coverage drift, three halves make the
        // call a v2 device switch: the re-validate must RETIRE it terminal (its
        // index entry cleared -- so no drain ever revisits it), not merely abort
        // this attempt, and of course never upload or send.
        backend.setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
          _half(_bob, 'DEVICE_C', eventId: '\$bob_half_2:example.com'),
        ]);
        h.gateDownload!.complete();
        await _pump();

        expect(h.uploadCalls, isEmpty, reason: 'aborted before upload');
        expect(h.sendCalls, isEmpty);
        expect(
          h.entry(_callKey),
          isNull,
          reason: 'a >2-half call is retired terminal by the re-validate',
        );
      },
    );
  });

  group('a merged event mid-backoff', () {
    test('cancels the wait and aborts the attempt', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _bob,
        myDeviceId: _deviceB,
      );

      h.coordinator.onCallFinished(_room, _callKey, _bob, _deviceB);
      await _pump();
      // Parked on the rank-1 backoff.
      h.coordinator.onSyncedMergedEvent(_room, _callKey);
      await _pump();
      await scheduler.elapse(_baseBackoff * 2);
      await _pump();

      expect(h.downloadCalls, isEmpty, reason: 'never got past the backoff');
      expect(h.uploadCalls, isEmpty);
      expect(h.sendCalls, isEmpty);
      expect(h.entry(_callKey), isNull, reason: 'retired by the merged event');
    });
  });

  group('a hung stage (rule 7: timeout + permit-until-settle)', () {
    test('times out into a counted transient and holds its permit until the '
        'underlying future settles', () async {
      final scheduler = freshClock();
      final gate = Completer<void>();
      final started = <String>{};
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ])
        ..setHalves('\$call2', [
          _half(_alice, _deviceA, eventId: '\$a2'),
          _half(_bob, _deviceB, eventId: '\$b2'),
        ])
        ..addMergedEvent('\$call2');
      backend.beforeFetch = (relType, callKey) async {
        started.add(callKey);
        if (callKey == _callKey && relType == CallAudioMergedContent.relType) {
          await gate.future; // hang the first call's first fetch forever.
        }
      };
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
        maxConcurrent: 1,
      );

      h.coordinator.onSyncedCallAudio(_room, _callKey);
      await _pump();
      await scheduler.elapse(_stageTimeout); // the hung fetch times out.
      await _pump();

      final entry = h.entry(_callKey)!;
      expect(entry['attemptCount'], 1, reason: 'a counted transient');

      // The permit is still held by the hung underlying future (permit-until-
      // settle): a second call is admitted to the index (index-before-await)
      // but cannot START its fetch.
      h.coordinator.onSyncedCallAudio(_room, '\$call2');
      await _pump();
      expect(
        started.contains('\$call2'),
        isFalse,
        reason: 'permit held by the hung op; call2 never fetched',
      );

      // Settling the hung future releases the permit; call2's parked attempt
      // now runs and retires (already-merged).
      gate.complete();
      await _pump();
      expect(
        started.contains('\$call2'),
        isTrue,
        reason: 'permit freed -> call2 fetched',
      );
      expect(h.entry('\$call2'), isNull, reason: 'call2 ran + retired merged');
    });
  });

  group('attemptCap exhaustion', () {
    test('quarantines (no further posts) and survives a restart', () async {
      final scheduler = freshClock();
      const boxName = 'merge_coord_quarantine';
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler, name: boxName),
        myUserId: _alice,
        myDeviceId: _deviceA,
        attemptCap: 2,
      )..sendThrows = StateError('send down');

      // Three failing attempts: attemptCount 1, 2, then 3 > cap -> quarantined.
      for (var i = 0; i < 3; i++) {
        h.coordinator.onSyncedCallAudio(_room, _callKey);
        await _pump();
      }
      final entry = h.entry(_callKey)!;
      expect(entry['attemptCount'], 3);
      expect(entry['quarantined'], true);

      final sendsBefore = h.sendCalls.length;
      // A further trigger must NOT attempt a quarantined call.
      h.coordinator.onSyncedCallAudio(_room, _callKey);
      await _pump();
      expect(h.sendCalls.length, sendsBefore, reason: 'no new attempt');

      // Restart: a new coordinator over the SAME persisted index still stands
      // down.
      final restarted = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler, name: boxName, erase: false),
        myUserId: _alice,
        myDeviceId: _deviceA,
        attemptCap: 2,
      );
      restarted.coordinator.start();
      await _pump();
      expect(restarted.sendCalls, isEmpty, reason: 'quarantine persisted');
    });
  });

  group('the mix stage (rule 7: typed terminal vs transient)', () {
    Future<_Harness> harnessForMix(_Scheduler scheduler) async {
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      return _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      );
    }

    test('a decode (FormatException) retires terminal', () async {
      final scheduler = freshClock();
      final h = await harnessForMix(scheduler)
        ..mixThrows = const FormatException('undecodable');

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();

      expect(h.uploadCalls, isEmpty);
      expect(h.sendCalls, isEmpty);
      expect(h.entry(_callKey), isNull, reason: 'terminal: index cleared');
    });

    test('a runtime failure stays transient (counted, kept)', () async {
      final scheduler = freshClock();
      final h = await harnessForMix(scheduler)
        ..mixThrows = StateError('isolate spawn failed');

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();

      expect(h.uploadCalls, isEmpty);
      expect(h.sendCalls, isEmpty);
      expect(
        h.entry(_callKey)?['attemptCount'],
        1,
        reason: 'transient: counted, still in the index',
      );
    });

    test('an incomplete (truncated) result retires terminal', () async {
      final scheduler = freshClock();
      final h = await harnessForMix(scheduler)
        ..mixComplete = false;

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();

      expect(h.uploadCalls, isEmpty);
      expect(h.sendCalls, isEmpty);
      expect(h.entry(_callKey), isNull);
    });
  });

  group('dispose (rule 6)', () {
    test('during the backoff aborts with no download/upload/send', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _bob,
        myDeviceId: _deviceB,
      );

      h.coordinator.onCallFinished(_room, _callKey, _bob, _deviceB);
      await _pump();
      h.coordinator.dispose();
      await scheduler.elapse(_baseBackoff * 2);
      await _pump();

      expect(h.downloadCalls, isEmpty);
      expect(h.uploadCalls, isEmpty);
      expect(h.sendCalls, isEmpty);
    });

    test(
      'during an in-flight download initiates no new upload or send',
      () async {
        final scheduler = freshClock();
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        )..gateDownload = Completer<void>();

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        expect(h.downloadCalls, isNotEmpty, reason: 'parked mid-download');
        h.coordinator.dispose();
        h.gateDownload!.complete();
        await _pump();

        expect(h.uploadCalls, isEmpty, reason: 'no new upload after disposal');
        expect(h.sendCalls, isEmpty);
      },
    );

    test('during an in-flight upload initiates no send', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      )..gateUpload = Completer<void>();

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();
      expect(h.uploadCalls, isNotEmpty, reason: 'parked mid-upload');
      h.coordinator.dispose();
      h.gateUpload!.complete();
      await _pump();

      expect(h.sendCalls, isEmpty, reason: 'no send after disposal');
    });
  });

  group('drain-until-clean coalescing (rule 4)', () {
    test(
      'a trigger during a pass causes exactly one coalesced re-run',
      () async {
        final scheduler = freshClock();
        final gate = Completer<void>();
        var mergedFetches = 0;
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
          ]);
        backend.beforeFetch = (relType, callKey) async {
          if (relType == CallAudioMergedContent.relType) {
            mergedFetches++;
            if (mergedFetches == 1) await gate.future;
          }
        };
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: await _newIndex(scheduler),
          myUserId: _alice,
          myDeviceId: _deviceA,
        );

        h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
        await _pump();
        expect(mergedFetches, 1, reason: 'pass 1 parked on its first fetch');

        // A trigger during the in-flight pass: coalesced, not a second runner.
        h.coordinator.onSyncedCallAudio(_room, _callKey);
        await _pump();
        expect(mergedFetches, 1, reason: 'no concurrent second pass');

        gate.complete();
        await _pump();
        expect(
          mergedFetches,
          2,
          reason: 'exactly one coalesced re-run after pass 1',
        );
      },
    );

    test('an aborted attempt does not run a coalesced re-pass', () async {
      final scheduler = freshClock();
      final gate = Completer<void>();
      var mergedFetches = 0;
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      backend.beforeFetch = (relType, callKey) async {
        if (relType == CallAudioMergedContent.relType) {
          mergedFetches++;
          if (mergedFetches == 1) await gate.future;
        }
      };
      final index = await _newIndex(scheduler);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: index,
        myUserId: _alice,
        myDeviceId: _deviceA,
      );

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();
      expect(mergedFetches, 1, reason: 'pass 1 parked on its first fetch');

      // A merged-event ABORT (which removes the index entry) and a dirty-setting
      // coalescing trigger both land during the parked pass. The abort must win:
      // the runner must run NO coalesced re-pass. onReconnected is the
      // dirty-setter here rather than onSyncedCallAudio precisely because it sets
      // `dirty` WITHOUT itself recreating the index -- so the index-entry check
      // below isolates the runner's `_superseded`-aware dirty-loop guard: without
      // it, the coalesce would re-enter `_onePass`, whose top-of-pass
      // `_keepPending` would RECREATE the just-removed entry with a fresh
      // firstSeenAt (the per-pass `_superseded` check alone would not stop that,
      // because it runs AFTER `_keepPending`).
      h.coordinator.onSyncedMergedEvent(_room, _callKey);
      h.coordinator.onReconnected();
      await _pump();

      gate.complete();
      await _pump();

      expect(h.sendCalls, isEmpty, reason: 'aborted: no post from a re-pass');
      expect(mergedFetches, 1, reason: 'no second fetch after the abort');
      expect(
        index.read('$_room|$_callKey'),
        isNull,
        reason:
            'the merged-event removal stays removed -- the aborted attempt runs '
            'no re-pass whose _keepPending would recreate the entry',
      );
    });
  });

  group('the global concurrency bound (rule 7)', () {
    test('caps simultaneous in-flight passes', () async {
      final scheduler = freshClock();
      final gate = Completer<void>();
      final started = <String>{};
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ])
        ..addMergedEvent(_callKey)
        ..setHalves('\$call2', [_half(_alice, _deviceA, eventId: '\$a2')])
        ..addMergedContent(
          '\$call2',
          CallAudioMergedContent(
            callKey: '\$call2',
            url: 'mxc://example.com/m2',
            mimetype: 'audio/wav',
            size: 8192,
            durationMs: 60000,
            sampleRate: 48000,
            channels: 1,
            codec: kCallAudioCodec,
            sourceEventIds: const ['\$a2', '\$b2'],
          ).toJson(),
        );
      backend.beforeFetch = (relType, callKey) async {
        started.add(callKey);
        if (callKey == _callKey && relType == CallAudioMergedContent.relType) {
          await gate.future;
        }
      };
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
        maxConcurrent: 1,
      );

      h.coordinator.onSyncedCallAudio(_room, _callKey);
      h.coordinator.onSyncedCallAudio(_room, '\$call2');
      await _pump();
      expect(started, {
        _callKey,
      }, reason: 'only one pass admitted under maxConcurrent = 1');

      gate.complete();
      await _pump();
      expect(started, {
        _callKey,
        '\$call2',
      }, reason: 'the second pass runs once the permit frees');
    });
  });

  group('the periodic drain (rule 1)', () {
    test('retries a lone transient with no other trigger', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      )..sendReturnsNull = true;

      // Arm the drain and let its initial (empty-index) scan finish BEFORE the
      // call exists, so the retry below is unambiguously the periodic drain and
      // not the startup scan.
      h.coordinator.start();
      await _pump();

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();
      expect(h.sendCalls, hasLength(1), reason: 'first attempt: send failed');
      expect(h.entry(_callKey)?['attemptCount'], 1);

      // No further external trigger; only the periodic drain wakes it.
      h.sendReturnsNull = false;
      await scheduler.elapse(_drainInterval);
      await _pump();

      expect(
        h.sendCalls.length,
        greaterThanOrEqualTo(2),
        reason: 'the drain retried the transient',
      );
      expect(
        h.entry(_callKey),
        isNull,
        reason: 'the retry succeeded + cleared',
      );
    });
  });

  group('startup reconciliation (rule 2)', () {
    test(
      'the durable index reconciles a call outside the sync window',
      () async {
        final scheduler = freshClock();
        final index = await _newIndex(scheduler);
        // A persisted index entry, with no live sync to re-announce the halves.
        final now = scheduler.now();
        await index.write('$_room|$_callKey', {
          'firstSeenAt': now.toIso8601String(),
          'attemptCount': 0,
          'quarantined': false,
          'nextRetryAt': now.toIso8601String(),
        });
        final backend = _Backend()
          ..setHalves(_callKey, [
            _half(_alice, _deviceA, eventId: _aliceEvent),
            _half(_bob, _deviceB, eventId: _bobEvent),
          ]);
        final h = _Harness(
          backend: backend,
          scheduler: scheduler,
          index: index,
          myUserId: _alice,
          myDeviceId: _deviceA,
        );

        h.coordinator.start();
        await _pump();

        expect(
          h.sendCalls,
          hasLength(1),
          reason: 'start() reconciled the call from the index alone',
        );
        expect(h.entry(_callKey), isNull);
      },
    );
  });

  group('index-before-await (rule 2)', () {
    test('the entry is written before the first fetch resolves', () async {
      final scheduler = freshClock();
      final gate = Completer<void>();
      final backend = _Backend()
        ..setHalves(_callKey, [
          _half(_alice, _deviceA, eventId: _aliceEvent),
          _half(_bob, _deviceB, eventId: _bobEvent),
        ]);
      backend.beforeFetch = (relType, callKey) async => gate.future;
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
      );

      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      // Synchronously, before any pump: the entry already exists.
      expect(h.entry(_callKey), isNotNull, reason: 'written before any await');

      await _pump();
      // The fetch is still gated (unresolved), yet the entry stands.
      expect(h.entry(_callKey), isNotNull);
      gate.complete();
      await _pump();
    });
  });

  group('index boundedness (rule 1: firstSeenAt-anchored expiry)', () {
    test('a perpetually-incomplete call is dropped at firstSeenAt + TTL despite '
        'many drain upserts', () async {
      final scheduler = freshClock();
      final backend = _Backend()
        // Only one half, forever: the peer never posts.
        ..setHalves(_callKey, [_half(_alice, _deviceA, eventId: _aliceEvent)]);
      final h = _Harness(
        backend: backend,
        scheduler: scheduler,
        index: await _newIndex(scheduler),
        myUserId: _alice,
        myDeviceId: _deviceA,
        drainInterval: const Duration(days: 1),
        indexTtl: const Duration(days: 7),
      );

      h.coordinator.start();
      h.coordinator.onCallFinished(_room, _callKey, _alice, _deviceA);
      await _pump();
      expect(h.entry(_callKey), isNotNull, reason: 'held while incomplete');

      // Six days of daily drains -- each re-evaluates (and re-keeps) the entry,
      // but must NOT refresh firstSeenAt.
      await scheduler.elapse(const Duration(days: 6));
      await _pump();
      expect(
        h.entry(_callKey),
        isNotNull,
        reason: 'still inside the 7-day logical TTL',
      );

      // Cross firstSeenAt + 7d: the entry is dropped, the index bounded.
      await scheduler.elapse(const Duration(days: 2));
      await _pump();
      expect(
        h.entry(_callKey),
        isNull,
        reason: 'dropped at firstSeenAt + TTL, not renewed by the drains',
      );
    });
  });
}
