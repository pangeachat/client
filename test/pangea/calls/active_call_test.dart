import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

import 'package:pangea_call_capture/pangea_call_capture.dart'
    show CallForegroundControl;

/// Records the order every step ran in, which is the property under test: the
/// call comes up in one order and down in the reverse, and the failure paths
/// have to preserve that.
class Trace {
  final List<String> steps = [];
  void call(String step) => steps.add(step);
}

class FakeCalls extends CallService {
  /// Whether the PEER still claims a place in the call, per room state. The
  /// authority on departure: leaving retracts it, and the SFU's participant
  /// list can lag that by its whole retention window.
  bool peerMembershipPresent = true;

  /// Whether the device that rang is still holding a call. False is the
  /// "they rang, gave up, and their ring is still valid" case.
  bool callerHoldsMembership = true;

  /// Set when a test needs the third answer for the CALLER: their state has
  /// not synced, which is neither calling nor gone.
  PeerPresence? callerPresenceOverride;

  @override
  PeerPresence callerPresence(
    matrix.Room room,
    String callerId, {
    String? deviceId,
  }) =>
      callerPresenceOverride ??
      (callerHoldsMembership ? PeerPresence.live : PeerPresence.gone);

  /// Whether the membership a rejoin was offered against is still standing.
  /// False is the crashed-device case, where the server's delayed leave has
  /// already emptied it.
  bool anchorStillCurrent = true;

  @override
  bool membershipEventIsCurrent(
    matrix.Room room,
    String userId,
    String eventId,
  ) => anchorStillCurrent;

  /// Set when a test needs the third answer: state that has not synced yet,
  /// which is neither presence nor departure.
  PeerPresence? peerPresenceOverride;

  @override
  PeerPresence peerPresenceInCurrentCall(
    matrix.Room room,
    String peerId, {
    DateTime? notBefore,
  }) =>
      peerPresenceOverride ??
      (peerMembershipPresent ? PeerPresence.live : PeerPresence.gone);

  /// Whether the account already holds a call, for the start-entry read.
  bool busy = false;

  @override
  bool get isBusy => busy;

  final Trace trace;

  /// The SFU's roster, which is now the only source of presence. The knobs
  /// below write into it, so a test still describes the world in terms of
  /// "my devices" and "is the peer here".
  FakeRoster? roster;

  List<String> _devices = const [];
  bool _remote = false;

  /// Devices of THIS account in the call, this one included — the way a test
  /// naturally describes it. Our own id is dropped on the way in, because the
  /// SFU only ever lists other participants.
  List<String> get devicesInCall => _devices;
  set devicesInCall(List<String> value) {
    _devices = value;
    _syncRoster();
  }

  bool get remotePresent => _remote;
  set remotePresent(bool value) {
    _remote = value;
    _syncRoster();
  }

  void _syncRoster() {
    final r = roster;
    if (r == null) return;
    final me = client.deviceID;
    r.identities = {
      for (final device in _devices)
        if (device != me) '${client.userID}:$device',
      if (_remote) '@peer:server:PEERDEVICE',
    };
    // A real roster notifies the moment the SFU's list changes.
    r.recompute();
  }

  final _declines = StreamController<Event>.broadcast();
  String? ringedNotificationId;

  /// Held open to reproduce a hangup landing mid-step.
  Completer<void>? holdRing;
  Completer<void>? holdJoin;
  Completer<void>? holdAnnounce;

  /// Whether anything is still subscribed for declines. A subscription made
  /// after teardown has nothing left able to cancel it.
  bool get watchingForDeclines => _declines.hasListener;

  @override
  Future<String?> ring(
    matrix.Room room, {
    required String membershipEventId,
    required bool video,
  }) async {
    trace('ring');
    if (holdRing != null) await holdRing!.future;
    return ringedNotificationId ??= '\$notification';
  }

  @override
  Stream<Event> declinesIn(matrix.Room room) => _declines.stream;

  final _rings = StreamController<Event>.broadcast();

  @override
  Stream<Event> ringsIn(matrix.Room room) => _rings.stream;

  /// The other person calling us at the same moment we call them.
  ///
  /// A real notification, because only a live one counts: sync replays old
  /// events, and a call from an hour ago is not somebody calling now.
  Future<void> peerAlsoCalls({Duration age = Duration.zero}) async {
    final sentAt = DateTime.now().subtract(age);
    _rings.add(
      Event(
        type: PangeaEventTypes.callNotification,
        content: {
          'application': {
            'type': 'm.call',
            'notification_type': 'ring',
            'sender_ts': sentAt.millisecondsSinceEpoch,
            'lifetime': 30000,
          },
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': '\$theirmembership',
          },
        },
        eventId: '\$theirs',
        senderId: '@peer:server',
        originServerTs: sentAt,
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  @override
  String? declineTarget(Event event) =>
      (event.content['m.relates_to'] as Map?)?['event_id'] as String?;

  /// A decline from an earlier call, replayed out of the room's history the way
  /// sync replays one.
  Future<void> peerDeclinedLongAgo() async {
    _declines.add(
      Event(
        type: 'decline',
        content: const {
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': '\$someoldcall',
          },
        },
        eventId: '\$old',
        senderId: '@peer:server',
        originServerTs: DateTime.now().subtract(const Duration(hours: 1)),
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  /// The other person turning down the call this device rang. [reason] is
  /// what a DEVICE says when it cannot take the call, as opposed to a person
  /// choosing not to.
  Future<void> peerDeclines({String? reason}) async {
    _declines.add(
      Event(
        type: 'decline',
        content: {
          'm.relates_to': {
            'rel_type': 'm.reference',
            'event_id': ringedNotificationId ?? '\$notification',
          },
          CallService.declineReasonField: ?reason,
        },
        eventId: '\$d',
        senderId: '@peer:server',
        originServerTs: DateTime.now(),
        room: matrix.Room(id: '!r:server', client: client),
      ),
    );
    await pumpEventQueue();
  }

  /// Publishes a new participant list, the way a join or leave would.
  Future<void> participantsBecome(List<String> ids) async {
    devicesInCall = ids;
    await pumpEventQueue();
  }

  Object? joinError;

  /// Modelled because it is the thing under test: the service holds a claim on
  /// this account's one call from before the join returns until it is given
  /// back, and a double that ignored it could not show it being released.
  bool joinClaimed = false;

  @override
  void abandonJoin(int attempt) => joinClaimed = false;
  Object? announceError;
  Object? retractError;
  bool retractFails = false;

  FakeCalls(super.client, this.trace);

  @override
  @override
  int get joinAttempt => 0;

  @override
  Future<CallToken> join(matrix.Room room) async {
    trace('join');
    // Claimed before the first await, as the real one does: the claim exists
    // precisely to cover the window this hold stands in for.
    joinClaimed = true;
    if (holdJoin != null) await holdJoin!.future;
    if (joinError != null) throw joinError!;
    return const CallToken(jwt: 'jwt', url: 'ws://sfu');
  }

  /// The membership this account holds, as the room would report it. Overridden
  /// because the real one reaches into the SDK, which a unit test has no
  /// business standing up.
  bool _retracted = false;

  /// What the ROOM reports, which is not the same as what announcing returned:
  /// the wait for the echo is deliberately short, so it can time out while the
  /// membership is perfectly well there a moment later.
  String? roomMembershipId = '\$membership';

  @override
  String? membershipEventIdIn(matrix.Room room) =>
      _retracted ? null : roomMembershipId;

  @override
  Future<String?> announce() async {
    trace('announce');
    if (holdAnnounce != null) await holdAnnounce!.future;
    if (announceError != null) throw announceError!;
    return membershipId;
  }

  String? membershipId = '\$membership';

  @override
  Future<bool> retract() async {
    trace('retract');
    _retracted = true;
    if (retractError != null) throw retractError!;
    return !retractFails;
  }
}

class FakeMedia extends CallMedia {
  final Trace trace;
  Object? connectError;
  bool hasTrack;
  Object? disposeError;

  FakeMedia(this.trace, {this.hasTrack = true});

  /// Held open to reproduce a hangup landing mid-connect.
  Future<void>? beforeConnect;

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {
    if (beforeConnect != null) await beforeConnect;
    trace('connect(video: $video)');
    if (connectError != null) throw connectError!;
  }

  final _track = FakeTrack();

  /// Supplied by the test rather than built from a live connection.
  FakeRoster? fakeRoster;

  @override
  CallRoster roster({required String myUserId}) => fakeRoster!;

  @override
  AudioTrack? get publishedAudio => hasTrack ? _track : null;

  @override
  Future<void> dispose() async {
    trace('media.dispose');
    if (disposeError != null) throw disposeError!;
  }
}

class FakeCapture extends CallCaptureService {
  final Trace trace;
  Object? stopError;
  Object? startError;
  Completer<void>? holdStop;
  Completer<void>? holdStart;
  FakeCapture(this.trace) : super(sink: _NullSink());

  /// Modelled, not assumed. The recorder reads this back after starting to
  /// learn whether a tap actually attached, so a double that ignored it would
  /// hide exactly the case that reading it exists to catch.
  bool _recording = false;

  /// A device with no point to record from: starting succeeds, and nothing is
  /// recording afterwards.
  bool attachesNothing = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start(covariant Object track) async {
    trace('capture.start');
    if (holdStart != null) await holdStart!.future;
    if (startError != null) throw startError!;
    _recording = !attachesNothing;
  }

  /// Whether each stop was asked to wait for deliveries, in order. A list, not
  /// a single value: finish() also stops without settling, so recording only
  /// the LAST one cannot tell teardown's choice from finish's.
  final List<bool> stopSettledDeliveries = [];

  /// The stop in flight, so a second caller JOINS the first rather than
  /// returning while it is still unwinding -- which is what the real service
  /// does (`_stopped ??= _stop()`). Without modelling that here, a fake stop
  /// that had already set `_recording = false` let a later caller straight
  /// through, and teardown looked finished while a flush was still running.
  Future<void>? _stopping;

  @override
  Future<void> stop({bool settleDeliveries = true}) async {
    stopSettledDeliveries.add(settleDeliveries);
    await (_stopping ??= _stop().whenComplete(() => _stopping = null));
  }

  Future<void> _stop() async {
    // Silent when there is nothing to stop, as the real one is. Tracing it
    // regardless made teardown look like it was stopping a recording that had
    // never started.
    if (!_recording) return;
    trace('capture.stop');
    _recording = false;
    if (holdStop != null) await holdStop!.future;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> finish() async {
    // Without settling, as the real one does: finish is the caller that settles.
    await stop(settleDeliveries: false);
    trace('capture.finish');
  }
}

/// The SFU's participant list, without an SFU.
///
/// Overrides only the two reads that need a live connection, so everything the
/// real roster decides — who is a peer, who is a sibling device, and the freeze
/// while disconnected — is the code under test rather than a stub.
class FakeRoster extends CallRoster {
  FakeRoster({required super.room, required super.myUserId});

  Set<String> identities = {};
  bool connected = true;
  bool disposed = false;

  /// Modelled because the two ways of not being connected mean opposite things:
  /// while the connection is coming back the roster holds its last picture, and
  /// once it has gone for good it clears. A double with only one of them turned
  /// a reconnect into everybody hanging up.
  bool recovering = false;

  @override
  Iterable<String> get remoteIdentities => identities;

  @override
  bool get roomConnected => connected;

  @override
  bool get roomRecovering => !connected && recovering;

  @override
  void recompute() {
    // A disposed roster is detached from its room and notifies nobody. Pinning
    // it here means a teardown that forgot to dispose shows up as a test that
    // keeps receiving presence after the call ended.
    if (disposed) return;
    super.recompute();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// The Android foreground service, without Android.
class FakeForeground extends CallForegroundControl {
  final Trace trace;
  bool startReturns;

  /// Held open so a test can hang up WHILE the platform is still answering.
  Completer<void>? holdStart;
  FakeForeground(this.trace, {this.startReturns = true});

  @override
  Future<bool> start({required String peer, required bool video}) async {
    trace('fgs.start(video: $video)');
    final hold = holdStart;
    if (hold != null) await hold.future;
    return startReturns;
  }

  int _epoch = 0;

  @override
  Future<void> stop() async => trace('fgs.stop');

  @override
  Future<void> setCamera(bool on) async => trace('fgs.camera($on)');

  @override
  int onAction(void Function(String action) handle) => ++_epoch;

  @override
  void clearActionHandler(int epoch) {}
}

/// Only [addAudioRenderer] is ever reached, and the recorder is faked here, so
/// nothing on this needs a real implementation.
class FakeTrack implements AudioTrack {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NullSink implements CallAudioSink {
  @override
  Future<void> deliver(PcmChunk chunk, {Duration? within}) async {}
  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Trace trace;

  /// Logged in, because the recording election ranks this device against its
  /// siblings by device id and a client that never logged in has none.
  Future<Client> bareClient() async {
    final client = Client(
      'active-call-test',
      httpClient: FakeMatrixApi(),
      database: await MatrixSdkDatabase.init(
        'active-call-test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.login(
      LoginType.mLoginPassword,
      token: 'abcd',
      identifier: AuthenticationUserIdentifier(
        user: '@test:fakeServer.notExisting',
      ),
      deviceId: 'GHTYAJCE',
    );
    return client;
  }

  setUp(() => trace = Trace());

  Future<(ActiveCall, FakeCalls, FakeMedia, FakeCapture)> build({
    bool hasTrack = true,
  }) async {
    final calls = FakeCalls(await bareClient(), trace);
    final media = FakeMedia(trace, hasTrack: hasTrack);
    final capture = FakeCapture(trace);
    final roster = FakeRoster(
      room: media.room,
      myUserId: calls.client.userID ?? '',
    );
    media.fakeRoster = roster;
    calls.roster = roster;
    return (
      ActiveCall(calls: calls, media: media, capture: capture),
      calls,
      media,
      capture,
    );
  }

  matrix.Room roomStub(Client c) => matrix.Room(id: '!r:server', client: c);

  group('how long the call is recorded as having lasted', () {
    test('does not charge the conversation for its own teardown', () async {
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.hadPeer, isTrue);

      // Teardown held open, standing in for the flush, the upload and the wait
      // for a transcript that follow a real hangup.
      final teardown = Completer<void>();
      capture.holdStop = teardown;
      final ending = call.hangUp();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      teardown.complete();
      await ending;

      // The window closed when the call was asked to end. Measured after
      // teardown instead, this reads at least the 60ms the flush was held for.
      expect(call.talkDuration, lessThan(const Duration(milliseconds: 60)));
    });

    test('counts a peer who arrived and left before the stage moved', () async {
      final (call, calls, media, _) = await build();
      // Present before this device even looks: the ordinary case for whoever
      // answers, since the caller is already in the room.
      calls.remotePresent = true;
      // Held at the announce so the call cannot reach connected, and they leave
      // inside that window — somebody was genuinely on the call, but the stage
      // never moved.
      final announce = Completer<void>();
      calls.holdAnnounce = announce;
      final starting = call.start(
        roomStub(calls.client),
        video: false,
        answering: true,
      );
      await Future<void>.delayed(Duration.zero);
      calls.remotePresent = false;
      announce.complete();
      await starting;

      // They were here, so this was a conversation and not a missed call —
      // and it has to have lasted something, or it is written as answered with
      // nothing in it.
      expect(call.hadPeer, isTrue);
      expect(call.talkStartedAt, isNotNull);
      expect(call.talkDuration, greaterThan(Duration.zero));
      expect(media, isNotNull);
    });

    test('a call nobody answered lasted no time at all', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      expect(call.hadPeer, isFalse);
      expect(call.talkStartedAt, isNull);
      expect(call.talkDuration, Duration.zero);
    });
  });

  group('what is recorded, and from when', () {
    test('nothing is recorded while the call is still ringing', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      // Their phone is ringing. Anything said here is said to nobody, and
      // crediting it to the call would put words in an analytics record that
      // no learner ever heard.
      expect(trace.steps, isNot(contains('capture.start')));
    });

    test('recording begins when they answer', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await Future<void>.delayed(Duration.zero);
      expect(trace.steps, contains('capture.start'));
    });

    test('whoever answers records from the first word', () async {
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false, answering: true);
      // The caller is already there, so there is no waiting for an arrival that
      // has already happened — the roster is read rather than listened for.
      expect(trace.steps, contains('capture.start'));
    });
  });

  group('a connection that drops mid-call', () {
    test('stops recording, and starts again when it comes back', () async {
      final (call, calls, media, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      // The roster deliberately holds its last picture across a reconnect, so
      // they still read as present — but nothing this learner says is reaching
      // them, and none of it should be credited as call speech.
      media.fakeRoster!.connected = false;
      media.fakeRoster!.recovering = true;
      media.fakeRoster!.recompute();
      await pumpEventQueue();
      expect(
        call.isRecording,
        isFalse,
        reason: 'words that went nowhere are not part of the conversation',
      );

      media.fakeRoster!.connected = true;
      media.fakeRoster!.recovering = false;
      media.fakeRoster!.recompute();
      await pumpEventQueue();
      expect(call.isRecording, isTrue, reason: 'and it picks back up');
    });
  });

  group('what a joiner anchors its analytics to', () {
    test('survives a hangup landing inside the announce', () async {
      // The id comes back and the hangup lands before it is kept. A device with
      // no ring of its own — anyone who JOINED the call — then has nothing to
      // attach its learner's words to, and the whole call goes uncredited.
      final (call, calls, _, _) = await build();
      calls.roomMembershipId = null; // the room has not echoed it yet
      final announcing = Completer<void>();
      calls.holdAnnounce = announcing;

      final starting = call.start(
        roomStub(calls.client),
        video: false,
        answering: true,
      );
      await pumpEventQueue();
      final ending = call.hangUp();
      announcing.complete();
      await starting;
      await ending;

      expect(call.membershipEventId, '\$membership');
    });

    test('is taken while the call runs, not once at the end', () async {
      // A device that JOINED a call has no ring of its own to point at, so its
      // membership is the only thing its speaking analytics can hang on. That
      // can only be read while the session is here.
      final (call, calls, _, _) = await build();
      calls.membershipId = null; // announce's own echo timed out
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false, answering: true);

      // The echo lands during the call, as it does in practice.
      calls.roomMembershipId = '\$membership';
      await call.tickReelectionForTest();

      // And by the time it ends, the room no longer answers — the single read
      // at teardown would come back with nothing, and every word this learner
      // spoke would be dropped for want of something to attach it to.
      calls.roomMembershipId = null;
      await call.hangUp();

      expect(call.membershipEventId, '\$membership');
    });
  });

  group('hanging up while the call is still coming up', () {
    test('gives the account its calling back at once', () async {
      final (call, calls, _, _) = await build();
      calls.holdJoin = Completer<void>();
      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(calls.joinClaimed, isTrue);

      // The screen is closed while the join is still out on the network. Held,
      // the claim suppressed every incoming ring and refused every new call
      // until the network finally answered.
      await call.hangUp();
      expect(
        calls.joinClaimed,
        isFalse,
        reason: 'a call nobody is waiting for must not hold the account',
      );

      calls.holdJoin!.complete();
      await starting;
    });
  });

  group('waiting for an answer', () {
    test('does not start the clock before they have been rung', () async {
      final (call, calls, _, _) = await build();
      calls.holdRing = Completer<void>();
      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      // Their phone has not rung yet, so there is nothing to be waiting on.
      // Started earlier, the caller's patience was spent on announcing and
      // ringing — on a slow network it could give up and write a missed call
      // while the callee was still being asked.
      await call.waitForPeerTimeoutForTest();
      expect(
        call.stage,
        isNot(CallStage.ended),
        reason: 'nobody has been asked yet, so nobody has failed to answer',
      );

      calls.holdRing!.complete();
      await starting;
      await call.waitForPeerTimeoutForTest();
      expect(call.stage, CallStage.ended, reason: 'and now it is running');
    });
  });

  group('answering a call whose caller is already in the room', () {
    // The answerer's very first roster snapshot already has the caller in it,
    // so the first CHANGE it sees can be the caller leaving. The peer's
    // identity used to be derived only on a change where they were present,
    // so it was never learned -- and every read that asks whether they
    // retracted answered "no peer, no opinion", turning a deliberate hangup
    // back into a 20-second wait for someone who had already gone.
    test(
      'a hangup by that caller ends the call at once, not after the grace',
      () async {
        final (call, calls, _, _) = await build();
        calls.devicesInCall = [calls.client.deviceID!];
        calls.remotePresent = true;
        await call.start(roomStub(calls.client), video: false, answering: true);
        expect(call.stage, CallStage.connected);

        // They hang up: the roster drops them AND their membership is retracted.
        calls.peerMembershipPresent = false;
        calls.remotePresent = false;
        await calls.participantsBecome([calls.client.deviceID!]);
        await call.tickReelectionForTest();

        expect(
          call.peerReconnecting,
          isFalse,
          reason: 'a retraction is a departure, not a disconnection',
        );
        expect(call.stage, CallStage.ended);
      },
    );
  });

  group('a retraction that is the FIRST state we ever see of them', () {
    // The answerer's hardest case: the caller is already in the SFU when we
    // join, and their Matrix state has not reached us yet -- so we never see
    // them "live" in state at all. Then they hang up, and the first state we
    // ever see for them is the retraction. Requiring a prior sighting before
    // believing a departure swallowed exactly this, and the answerer waited
    // out a 20-second grace for someone who had already gone.
    test('is believed without having seen them live first', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      // Their state has not synced: neither presence nor departure.
      calls.peerPresenceOverride = PeerPresence.unknown;
      await call.start(roomStub(calls.client), video: false, answering: true);
      expect(call.stage, CallStage.connected);

      // They hang up. The retraction is the first thing we ever see.
      calls.peerPresenceOverride = PeerPresence.gone;
      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      await call.tickReelectionForTest();

      expect(
        call.peerReconnecting,
        isFalse,
        reason: 'a retraction is a departure, whoever saw what first',
      );
      expect(call.stage, CallStage.ended);
    });
  });

  group('a decline that arrives before the ring has returned', () {
    // The subscription is deliberately older than the id it matches, so a
    // busy line can answer before our own send does. Remembering only THAT it
    // happened lost the reason, and the caller was told they had been turned
    // down when the truth was the other line was engaged: no engaged tone, and
    // the wrong line in their history.
    test('is replayed with the reason it carried', () async {
      final (call, calls, _, _) = await build();
      calls.holdRing = Completer<void>();
      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      await calls.peerDeclines(reason: CallService.declineBusy);
      expect(call.peerWasBusy, isFalse, reason: 'nothing to match it to yet');

      calls.holdRing!.complete();
      await starting;
      await pumpEventQueue();
      expect(
        call.peerWasBusy,
        isTrue,
        reason: 'the reason has to survive the wait for our own ring id',
      );
    });

    test(
      'a person turning it down still reads as an ordinary decline',
      () async {
        final (call, calls, _, _) = await build();
        calls.holdRing = Completer<void>();
        final starting = call.start(roomStub(calls.client), video: false);
        await pumpEventQueue();
        await calls.peerDeclines();
        calls.holdRing!.complete();
        await starting;
        await pumpEventQueue();
        expect(call.peerWasBusy, isFalse);
      },
    );
  });

  group('bringing a call up', () {
    test('placing into an empty call rings the other side', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, contains('ring'));
      expect(call.placedCall, isTrue);
    });

    test('a stale membership cannot silence a new call', () async {
      // Placing is decided by who is actually in the call, per the SFU. Matrix
      // membership is not consulted at all — it holds a crashed peer's entry
      // for around twelve minutes, and reading it would send a genuine new call
      // out silent.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, contains('ring'));
    });

    test(
      'this account own second device joining does not ring again',
      () async {
        // The caller's second device is a different device of the same user.
        // Anyone already in the call — peer or sibling — means this is a join.
        final (call, calls, _, _) = await build();
        calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
        await call.start(roomStub(calls.client), video: false);
        expect(trace.steps, isNot(contains('ring')));
        expect(call.placedCall, isFalse);
      },
    );

    test('a call the user ended is not reported as failed', () async {
      // Teardown running underneath a step in flight is what made it throw.
      // Reporting that as a failure showed an error for a call the user had
      // deliberately ended.
      final (call, calls, media, _) = await build();
      final gate = Completer<void>();
      media.beforeConnect = gate.future;
      media.connectError = StateError('socket closed by teardown');

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await call.hangUp();
      gate.complete();
      await starting;
      await call.settled;

      expect(call.stage, isNot(CallStage.failed));
      expect(call.stage, CallStage.ended);
    });

    test('answering never rings, even if the caller already left', () async {
      // The callee reaches the SFU after the caller gave up, so the room looks
      // empty. Deriving placing from that made the answerer ring the caller
      // back — a call nobody placed, from the wrong side.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false, answering: true);

      expect(trace.steps, isNot(contains('ring')));
      expect(
        call.placedCall,
        isFalse,
        reason: 'someone who was rung is never the one placing',
      );
    });

    test('joining an existing call does not ring the caller back', () async {
      // A call someone is already in is one this device is joining, and a ring
      // from it would ring the caller who is already there. This holds however
      // the join is reached — the banner, the header button, or a deep link.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, isNot(contains('ring')));
      expect(call.stage, CallStage.connected);
      expect(
        call.placedCall,
        isFalse,
        reason: 'the answering side must not also write the call to the room',
      );
    });

    test('media and recording start before the peer is told', () async {
      final (call, calls, _, _) = await build();
      // Somebody is already on the call, so this is joining one rather than
      // placing one — hence no ring — and there is somebody to record with from
      // the first moment.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      // Recording is running before this device announces itself, so the peer
      // never learns we are here ahead of us being able to hear them.
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'capture.start',
        'announce',
      ]);
      expect(call.stage, CallStage.connected);
      expect(call.isRecording, isTrue);
    });

    test('video is published when asked for', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: true);
      expect(trace.steps, contains('connect(video: true)'));
    });

    test('a call with no publishable audio still connects', () async {
      // Losing analytics is worse than nothing; refusing the call is worse still.
      final (call, calls, _, _) = await build(hasTrack: false);
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);
      expect(call.isRecording, isFalse);
      expect(trace.steps, isNot(contains('capture.start')));
    });
  });

  group('a failure while coming up', () {
    test('a refused join leaves nothing behind', () async {
      final (call, calls, _, _) = await build();
      calls.joinError = StateError('no focus');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(call.error, isStateError);
      expect(trace.steps, [
        'join',
        'media.dispose',
        'capture.finish',
      ], reason: 'nothing was announced and no membership to retract');
    });

    test('a call the account has no room for fails without stranding '
        'itself or the call already up', () async {
      final (call, calls, _, _) = await build();
      // The account is already in a call, so the service refuses this join.
      calls.joinError = const AlreadyInACall();
      await call.start(roomStub(calls.client), video: false);

      // The screen must be able to close. A start that leaves the stage at
      // connecting is a call the user can only sit and stare at.
      expect(call.stage, CallStage.failed);

      // A ring landing after the failure must not stir the dead call: the
      // subscription it opened before the join has to be gone.
      await calls.peerAlsoCalls();
      expect(
        call.peerAlsoPlaced,
        isFalse,
        reason: 'a failed call must not keep listening for rings',
      );

      // And it must not have given back the claim it never held — that one
      // belongs to the call already up. joinClaimed stands in for that claim;
      // abandonJoin would clear it.
      await call.hangUp();
      await pumpEventQueue();
      expect(
        calls.joinClaimed,
        isTrue,
        reason: 'the other call still holds the account',
      );
    });

    test('media that will not connect retracts the join', () async {
      final (call, calls, media, _) = await build();
      media.connectError = StateError('sfu unreachable');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'media.dispose',
        'retract',
        'capture.finish',
      ]);
    });

    test('a failure to announce tears the whole call down', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.announceError = StateError('state event rejected');
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.failed);
      expect(trace.steps, [
        'join',
        'connect(video: false)',
        'capture.start',
        'announce',
        'media.dispose',
        'retract',
        'capture.stop',
        'capture.finish',
      ], reason: 'the recording is flushed even on a failed call');
    });
  });

  group('hanging up', () {
    // The order is the contract, and each position was paid for:
    //   media.dispose  first, so the peer stops hearing a learner who has
    //                  hung up -- nothing in the recording teardown may
    //                  delay it.
    //   retract        immediately after, because it is the ONLY thing that
    //                  tells the other side this was deliberate rather than
    //                  a crash, and they decide that within seconds. Behind
    //                  the recorder teardown -- a tap detach is allowed five
    //                  -- it could arrive after they had already started
    //                  waiting for someone who was never coming back.
    //   capture.stop   with the devices already free.
    //   capture.finish last, the only wait on the transcription service.
    test('unwinds in reverse', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'media.dispose',
        'retract',
        'capture.stop',
        'capture.finish',
      ]);
      expect(call.stage, CallStage.ended);
    });

    test('twice tears down once', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await Future.wait([call.hangUp(), call.hangUp()]);
      expect(trace.steps, [
        'media.dispose',
        'retract',
        'capture.stop',
        'capture.finish',
      ]);
    });

    test('a recording that will not flush still frees the microphone '
        'and retracts the membership', () async {
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      capture.stopError = StateError('flush failed');
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'media.dispose',
        'retract',
        'capture.stop',
        'capture.finish',
      ]);
      expect(call.stage, CallStage.ended);
    });

    test('a recording that HANGS still frees the microphone at once', () async {
      // Stopping the recording detaches the tap — a platform round-trip that can
      // stall — and waits on chunks still uploading. The peer stops hearing us
      // only when the media is released, and that must NOT wait behind any of
      // it: gating the release behind a stalled stop kept the microphone live to
      // the other side long after the learner had hung up.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      // The stop never completes. Teardown must reach the media release anyway.
      capture.holdStop = Completer<void>();
      trace.steps.clear();
      final hangingUp = call.hangUp();

      await pumpEventQueue();
      expect(
        trace.steps,
        contains('media.dispose'),
        reason: 'the peer is freed without waiting for the recording to stop',
      );

      // And once the recording does finish, the rest of teardown follows.
      capture.holdStop!.complete();
      await hangingUp;
      expect(trace.steps, contains('capture.finish'));
      expect(call.stage, CallStage.ended);
    });

    test('a stalled recorder handover does not delay freeing the mic', () async {
      // The recorder election runs on the handover chain, and a reconcile is a
      // platform start/stop that can stall. Freeing the peer must not wait
      // behind THAT either — not just behind the teardown's own stop.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!]; // this device records
      await call.start(roomStub(calls.client), video: false);

      // A sibling sorting lower arrives, so this device is displaced and its
      // reconcile calls capture.stop — held here, so the handover is stuck.
      capture.holdStop = Completer<void>();
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);
      await pumpEventQueue();

      trace.steps.clear();
      final hangingUp = call.hangUp();
      await pumpEventQueue();
      expect(
        trace.steps,
        contains('media.dispose'),
        reason: 'the mic is freed even with the recorder handover stalled',
      );

      capture.holdStop!.complete();
      await hangingUp;
      expect(call.stage, CallStage.ended);
    });

    test('media that will not close does not strand the rest', () async {
      final (call, calls, media, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      media.disposeError = StateError('socket stuck');
      trace.steps.clear();
      await call.hangUp();

      expect(trace.steps, [
        'media.dispose',
        'retract',
        'capture.stop',
        'capture.finish',
      ], reason: 'a stuck socket must not strand the rest of teardown');
      expect(call.stage, CallStage.ended);
    });

    test('a retract that reports failure stays retryable', () async {
      // The service releases the session either way so calling is not blocked,
      // so a failure that did not throw would otherwise be taken for success and
      // the one retry that could help would never happen.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);

      calls.retractFails = true;
      await call.hangUp();
      expect(trace.steps, contains('retract'));

      calls.retractFails = false;
      trace.steps.clear();
      await call.hangUp();
      expect(
        trace.steps,
        contains('retract'),
        reason: 'the second hangup tries again',
      );
    });

    test('a failed retract stays retryable', () async {
      // Memoizing a teardown that could not retract would make every later
      // hangup return that same finished future, so the membership would stay
      // advertised until it expired with nothing able to take it back.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);

      calls.retractError = StateError('server refused');
      await call.hangUp();
      expect(trace.steps, contains('retract'));

      calls.retractError = null;
      trace.steps.clear();
      await call.hangUp();
      expect(
        trace.steps,
        contains('retract'),
        reason: 'the second hangup actually tries again',
      );
    });

    test('a membership that will not retract still ends the call', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.retractError = StateError('server refused');
      await call.hangUp();
      expect(call.stage, CallStage.ended);
    });
  });

  test('disposing hangs up without notifying a disposed listener', () async {
    // Teardown is asynchronous, so the transition to ended lands after dispose
    // has returned. Notifying then throws — on the ordinary path of closing the
    // call screen.
    final (call, calls, _, _) = await build();
    // A call has to have somebody on it to be recorded: nothing is
    // captured while it is still ringing.
    calls.remotePresent = true;
    await call.start(roomStub(calls.client), video: false);
    trace.steps.clear();

    call.dispose();
    await pumpEventQueue();

    expect(trace.steps, [
      'media.dispose',
      'retract',
      'capture.stop',
      'capture.finish',
    ]);
    expect(call.stage, CallStage.ended);
  });

  test('the peer stops hearing us before anything slow runs', () async {
    // What the other person sees is the SFU, not Matrix room state: their
    // client reads who is present from the roster. So leaving the media session
    // is what tells them we have gone, and it is also what closes the
    // microphone. Everything slow — retracting a membership nobody is watching,
    // then waiting on uploads and transcription — belongs after it. The other
    // way round, which is how this once was, left them hearing a learner who
    // had already hung up for as long as a state write takes.
    final (call, calls, _, _) = await build();
    // A call has to have somebody on it to be recorded: nothing is
    // captured while it is still ringing.
    calls.remotePresent = true;
    await call.start(roomStub(calls.client), video: false);
    trace.steps.clear();

    await call.hangUp();
    expect(
      trace.steps.indexOf('media.dispose'),
      lessThan(trace.steps.indexOf('retract')),
      reason: 'the peer sees us go before the bookkeeping',
    );
    expect(
      trace.steps.indexOf('media.dispose'),
      lessThan(trace.steps.indexOf('capture.finish')),
      reason: 'and long before the uploads settle',
    );
  });

  test('a hangup during connect stops the call coming up', () async {
    final (call, calls, media, _) = await build();
    final connecting = Completer<void>();
    media.beforeConnect = connecting.future;

    final starting = call.start(roomStub(calls.client), video: false);
    await pumpEventQueue();
    final hangingUp = call.hangUp();

    connecting.complete();
    await Future.wait([starting, hangingUp]);

    expect(call.stage, CallStage.ended);
    expect(
      trace.steps,
      isNot(contains('announce')),
      reason: 'a call the user abandoned must not finish assembling itself',
    );
    expect(trace.steps, contains('retract'));
  });

  group('when the other person leaves', () {
    // The transition table under test, row by row. A vanished peer gets the
    // SFU's departure timeout to come back; the old behaviour — routing every
    // absence into the same immediate hangUp — is exactly what these used to
    // pin, and a mid-call browser refresh killed the call for both sides.

    Future<(ActiveCall, FakeCalls, FakeCapture)> connectedCall() async {
      final (call, calls, _, capture) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);
      return (call, calls, capture);
    }

    test('their place is held instead of the call ending', () async {
      final (call, calls, _) = await connectedCall();

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.stage, CallStage.connected, reason: 'grace, not gone');
      expect(call.peerReconnecting, isTrue);
      expect(
        trace.steps,
        isNot(contains('retract')),
        reason: 'nothing torn down while their return is possible',
      );
    });

    test('the microphone captures nothing while nobody can hear it', () async {
      final (call, calls, _) = await connectedCall();
      expect(trace.steps, contains('capture.start'));

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);

      // The latched _peerArrived alone used to satisfy the election, so the
      // recording ran on into an empty call. Presence is live now.
      expect(call.peerReconnecting, isTrue);
      expect(trace.steps, contains('capture.stop'));
    });

    test(
      'the peer coming back resumes the call, once it is believed',
      () async {
        // The return is confirmed rather than taken at first sight -- see the
        // SFU-echo test below for the device failure that bought that rule.
        final (call, calls, _) = await connectedCall();

        calls.remotePresent = false;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(call.peerReconnecting, isTrue);
        final stops = trace.steps.where((s) => s == 'capture.stop').length;

        calls.remotePresent = true;
        await calls.participantsBecome([calls.client.deviceID!]);
        await call.confirmPeerReturnForTest();

        expect(call.peerReconnecting, isFalse);
        expect(call.stage, CallStage.connected);
        // Recording resumes for the resumed conversation.
        expect(
          trace.steps.where((s) => s == 'capture.start').length,
          greaterThan(stops > 0 ? 1 : 0),
        );
      },
    );

    test('time they spent vanished is not talking time', () async {
      final (call, calls, _) = await connectedCall();

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      final paused = call.talkDuration;
      // The clock is paused: real time passes, the sum does not move.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(call.talkDuration, paused);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);
      await call.hangUp();
      // Both talking stretches counted, the 120ms hole between them not.
      expect(call.talkDuration, lessThan(const Duration(milliseconds: 120)));
    });

    test('the grace running out ends it as a call that happened', () async {
      final (call, calls, _) = await connectedCall();

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.peerReconnecting, isTrue);

      await call.peerGraceLapseForTest();

      expect(call.stage, CallStage.ended);
      expect(call.hadPeer, isTrue, reason: 'answered, not missed');
      expect(call.wasDeclined, isFalse);
      expect(trace.steps, contains('retract'));
    });

    test(
      "the SFU's echo of a departed peer does not cancel the grace",
      () async {
        // THE DEVICE BUG, pinned. The SFU holds a departed participant for its
        // own departure timeout and can re-report them; taking that for a
        // return cancelled the grace, and since nothing changed afterwards the
        // call hung open for good -- microphone live, membership heartbeating,
        // nobody there. A return must survive peerReturnConfirmed.
        final (call, calls, _) = await connectedCall();

        calls.remotePresent = false;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(call.peerReconnecting, isTrue);

        // The echo: present again, immediately.
        calls.remotePresent = true;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(
          call.peerReconnecting,
          isTrue,
          reason:
              'an unconfirmed sighting must not cancel the only bounded '
              'thing in this machine',
        );
        expect(
          trace.steps.where((s) => s == 'capture.start').length,
          1,
          reason: 'and it must not restart the microphone either',
        );

        // The echo dies again, as a real departure does.
        calls.remotePresent = false;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(call.peerReconnecting, isTrue, reason: 'the grace runs on');

        await call.peerGraceLapseForTest();
        expect(
          call.stage,
          CallStage.ended,
          reason: 'bounded, whatever the SFU said',
        );
      },
    );

    test(
      'a peer who really returns resumes once their presence holds',
      () async {
        final (call, calls, _) = await connectedCall();

        calls.remotePresent = false;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(call.peerReconnecting, isTrue);

        calls.remotePresent = true;
        await calls.participantsBecome([calls.client.deviceID!]);
        expect(call.peerReconnecting, isTrue, reason: 'not yet believed');

        // Still there when we look again, past the confirmation window.
        await call.confirmPeerReturnForTest();

        expect(call.peerReconnecting, isFalse);
        expect(call.stage, CallStage.connected);
        expect(
          trace.steps.where((s) => s == 'capture.start').length,
          greaterThan(1),
          reason: 'recording resumes for the resumed conversation',
        );
      },
    );

    test(
      'a peer the room says has LEFT is gone, whatever the SFU lists',
      () async {
        // The device failure. LiveKit keeps a departed participant for its
        // departure timeout and re-lists them when OUR connection reconnects;
        // on the phone the list then never dropped them again, and the call
        // stayed open for good with a live microphone. The room's retraction
        // is the authority the SFU cannot override -- and because a
        // retraction IS the other person ending the call, it ends here at
        // once rather than promising a reconnection nobody will make.
        final (call, calls, _) = await connectedCall();

        // A tick while they are genuinely here: their membership is SEEN, so
        // its later absence means something (the transition rule -- room
        // state lags a join, and "not synced yet" must never read as "left").
        await call.tickReelectionForTest();

        calls.peerMembershipPresent = false;
        await call.tickReelectionForTest();

        expect(call.stage, CallStage.ended);
        expect(
          call.peerReconnecting,
          isFalse,
          reason: 'no window is held open for a call they ended',
        );
        expect(call.hadPeer, isTrue);
      },
    );

    test('hanging up during the grace ends it immediately', () async {
      final (call, calls, _) = await connectedCall();

      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.peerReconnecting, isTrue);

      await call.hangUp();

      expect(call.stage, CallStage.ended);
      expect(call.peerReconnecting, isFalse, reason: 'the wait died with it');
    });

    test('a peer who has not answered yet does not end it', () async {
      // Their absence only means the call is over if they were ever there.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.stage, CallStage.connected, reason: 'still ringing out');
      expect(call.peerReconnecting, isFalse, reason: 'grace is post-answer');
    });

    test('a peer who crashes without a leave event gets the same grace', () async {
      // A membership lapses on a timer, not an event, so a crashed peer fires no
      // participant change. The periodic re-check is what notices they are gone;
      // a crash IS the case most worth a grace, since their app may relaunch.
      final (call, calls, _) = await connectedCall();

      // The peer's membership expires; NO participant event fires.
      calls.remotePresent = false;
      await call.tickReelectionForTest();

      expect(
        call.peerReconnecting,
        isTrue,
        reason: 'the check armed the grace',
      );
      await call.peerGraceLapseForTest();
      expect(call.stage, CallStage.ended);
    });

    test('our own connection gone for good still ends it at once', () async {
      // The grace is for THEIR absence over OUR healthy connection. With our
      // own session dead and not recovering there is nothing to wait in.
      final (call, calls, _) = await connectedCall();

      calls.roster!.connected = false;
      calls.roster!.recovering = false;
      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.stage, CallStage.ended);
      expect(call.peerReconnecting, isFalse);
    });
  });

  group('the background-survival service', () {
    Future<(ActiveCall, FakeCalls, FakeForeground)> withForeground({
      bool startReturns = true,
    }) async {
      final calls = FakeCalls(await bareClient(), trace);
      final media = FakeMedia(trace, hasTrack: true);
      final fgs = FakeForeground(trace, startReturns: startReturns);
      final roster = FakeRoster(
        room: media.room,
        myUserId: calls.client.userID ?? '',
      );
      media.fakeRoster = roster;
      calls.roster = roster;
      final call = ActiveCall(
        calls: calls,
        media: media,
        capture: FakeCapture(trace),
        foreground: fgs,
      );
      return (call, calls, fgs);
    }

    // The leak this pins shut: the start is fired unawaited, so a hangup can
    // land while the platform is still answering. Teardown read the claim as
    // false, skipped the stop, and the ongoing-call service outlived the call.
    test('a start that lands after teardown stops itself', () async {
      final (call, calls, fgs) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      fgs.holdStart = Completer<void>();

      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      expect(
        trace.steps,
        isNot(contains('fgs.stop')),
        reason: 'nothing has claimed the service yet',
      );

      fgs.holdStart!.complete();
      await pumpEventQueue();
      expect(
        trace.steps,
        contains('fgs.stop'),
        reason: 'the late start must take itself down',
      );
    });

    test('starts before anything is awaited, and stops in teardown', () async {
      final (call, calls, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      final startAt = trace.steps.indexOf('fgs.start(video: false)');
      final joinAt = trace.steps.indexOf('join');
      expect(startAt, isNot(-1));
      expect(
        startAt,
        lessThan(joinAt),
        reason:
            'the earliest guaranteed-foreground moment is before the '
            'first network await, or Android may already consider us '
            'background',
      );

      await call.hangUp();
      expect(trace.steps, contains('fgs.stop'));
    });

    test('a failed call still stops the service', () async {
      final (call, calls, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.joinError = StateError('no focus');
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.failed);
      expect(
        trace.steps,
        contains('fgs.stop'),
        reason: 'every teardown path converges in _unwind',
      );
    });

    test('a refused start is retried once media proves the grant', () async {
      // The service cannot run before the microphone permission exists; media
      // connecting IS the proof the dialog was answered.
      final (call, calls, fgs) = await withForeground(startReturns: false);
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      fgsRetriesAfterGrant() =>
          trace.steps.where((s) => s == 'fgs.start(video: false)').length;
      await call.start(roomStub(calls.client), video: false);
      expect(
        fgsRetriesAfterGrant(),
        2,
        reason: 'the entry attempt plus the post-connect retry',
      );
      await call.hangUp();
    });

    test('a start the account will refuse never touches the service', () async {
      // The service is the LIVE call's; a second start is about to be
      // refused with AlreadyInACall, and firing the service first would
      // overwrite the standing call's notification with this one's name.
      final (call, calls, _) = await withForeground();
      calls.busy = true;
      calls.joinError = const AlreadyInACall();
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.failed);
      expect(trace.steps.where((s) => s.startsWith('fgs.start')), isEmpty);

      // And its teardown must not stop the LIVE call's service either: it
      // never claimed the service, so it has no claim to end.
      call.dispose();
      await pumpEventQueue();
      expect(trace.steps, isNot(contains('fgs.stop')));
    });

    test('a call started with video escalates the service type', () async {
      final (call, calls, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: true);
      expect(
        trace.steps,
        contains('fgs.camera(true)'),
        reason: 'site (a): the camera opened inside connect',
      );
      await call.hangUp();
    });
  });

  group('returning to a call after a reload', () {
    test('a rejoin never rings and never announces a new call', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      // The peer is still on the call the reload interrupted.
      calls.remotePresent = true;

      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
      );

      expect(call.stage, CallStage.connected);
      expect(trace.steps, isNot(contains('ring')));
      expect(trace.steps, isNot(contains('announce')));
      expect(call.placedCall, isFalse);
      // The call keeps the identity it already had: the membership written
      // when it was first joined, not something minted for the re-entry.
      expect(call.membershipEventId, r'$original-membership');
      expect(call.rejoinedCall, isTrue);
    });

    test('an empty room at rejoin does not read as placing a call', () async {
      // The peer may have dropped in the same window. An empty roster used to
      // be the definition of "placing" — a rejoin ringing the peer for their
      // own call's past is the failure this pins against.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;

      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
      );

      expect(call.placedCall, isFalse);
      expect(trace.steps, isNot(contains('ring')));
      expect(trace.steps, isNot(contains('announce')));
    });

    // The crashed-device case. Our membership was not retracted by us -- the
    // SERVER did it, when the delayed leave it was holding ran out -- so the
    // anchor the breadcrumb points at is gone. Rejoining on it published
    // nothing, and the other side, which reads an empty list as a departure,
    // sat out its grace and hung up on somebody who was right there.
    test('a rejoin whose membership the server already retracted announces '
        'itself again', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      calls.anchorStillCurrent = false;

      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
        rejoinSince: DateTime.now().subtract(const Duration(minutes: 2)),
      );

      expect(trace.steps, contains('announce'));
      expect(trace.steps, isNot(contains('ring')), reason: 'still a rejoin');
      expect(
        call.callStartedAt!.isBefore(
          DateTime.now().subtract(const Duration(seconds: 90)),
        ),
        isTrue,
        reason: 'the clock still continues the call it returned to',
      );
    });

    test('a peer who never comes back means a quiet leave', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;

      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
      );
      expect(call.stage, CallStage.connected, reason: 'joined, waiting');

      // The bounded wait lapses with the roster still empty.
      await call.waitForPeerTimeoutForTest();

      expect(call.stage, CallStage.ended);
      expect(call.hadPeer, isFalse, reason: 'nobody was ever on this rejoin');
      expect(trace.steps, contains('retract'), reason: 'left cleanly');
    });

    test('the peer arriving during the wait resumes the call', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;

      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
      );

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.hadPeer, isTrue);
      expect(call.stage, CallStage.connected);
      expect(trace.steps, contains('capture.start'), reason: 'recording again');
    });
  });

  group('when the other person declines', () {
    test('the caller stops ringing and is told why', () async {
      // Ringing at someone who has already said no is what every other calling
      // app avoids, and leaving the caller to wonder is the other half of it.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.connected);

      await calls.peerDeclines();
      // A decline waits a moment to see whether somebody answers on another of
      // their devices. Nobody does here, so it stands.
      await call.declineTimeoutForTest();

      expect(call.stage, CallStage.declined);
      expect(call.wasDeclined, isTrue);
      expect(trace.steps, contains('retract'));
    });

    test('loses to somebody answering on their other device', () async {
      // A phone and a laptop both ring. Turning it down on one while answering
      // on the other sends a decline that can reach us before the answer does —
      // the decline is a timeline event, the answer is a join the SFU has to
      // report. Acted on at once, it hung up a call that had just been
      // answered and wrote it down as turned down.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);

      await calls.peerDeclines();
      // They answer inside the window the decline is waiting out.
      calls.remotePresent = true;
      await pumpEventQueue();
      await call.declineTimeoutForTest();

      expect(call.wasDeclined, isFalse);
      expect(call.stage, isNot(CallStage.declined));
      expect(call.hadPeer, isTrue);
    });

    test('landing as the call gives up is still a decline', () async {
      // The wait a decline serves can be overtaken by the call ending on its
      // own. Only the WAIT is abandoned then, not the fact: written as nobody
      // answering, it says the learner was ignored when they were turned down.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);

      await calls.peerDeclines();
      // Nobody answers, and the call gives up while the decline is still
      // waiting to see whether anyone would.
      await call.waitForPeerTimeoutForTest();

      expect(call.wasDeclined, isTrue);
      expect(call.stage, CallStage.declined);
    });

    test('a decline after they answered is ignored', () async {
      // They are in the call. A stray decline event must not end a conversation
      // that is actually happening.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      await calls.peerDeclines();

      expect(call.stage, CallStage.connected);
      expect(call.wasDeclined, isFalse);
    });
  });

  group('when nobody is on the other end', () {
    test('the call gives up rather than waiting forever', () async {
      // Covers a callee who never answers and a caller who gave up moments
      // before this device joined. Either leaves a learner in an open call,
      // with an open microphone, and nobody there.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected, reason: 'still ringing out');
      await call.waitForPeerTimeoutForTest();

      expect(call.stage, CallStage.ended);
      expect(trace.steps, contains('retract'));
    });

    test('an unanswered call is not treated as a conversation', () async {
      // Reaching the SFU is not a call. Writing one would put a conversation in
      // the timeline that never happened and credit talking to nobody.
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected);
      expect(call.hadPeer, isFalse, reason: 'nobody answered');
    });

    test('answering makes it a conversation, and says so', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      var notified = 0;
      call.addListener(() => notified++);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(call.hadPeer, isTrue);
      expect(
        notified,
        greaterThan(0),
        reason: 'the stage does not change, so the screen must be told',
      );
    });

    test('answering in time stops the giving up', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = false;
      await call.start(roomStub(calls.client), video: false);

      calls.remotePresent = true;
      await calls.participantsBecome([calls.client.deviceID!]);
      await call.waitForPeerTimeoutForTest();

      expect(call.stage, CallStage.connected, reason: 'they answered');
    });
  });

  group('which device records', () {
    test('this one, when it is alone in the call', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);
    });

    test(
      'not this one, when a device sorting lower is already there',
      () async {
        final (call, calls, _, _) = await build();
        calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
        await call.start(roomStub(calls.client), video: false);

        expect(call.isRecording, isFalse);
        expect(
          trace.steps,
          isNot(contains('capture.start')),
          reason: 'the other device is recording; this one would double-count',
        );
      },
    );

    test('this one takes over when the other device leaves', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse);

      await calls.participantsBecome([calls.client.deviceID!]);
      expect(call.isRecording, isTrue, reason: 'it is alone now');
      expect(trace.steps, contains('capture.start'));
    });

    test('this one stops when a device sorting lower arrives', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);
      trace.steps.clear();

      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);
      expect(call.isRecording, isFalse);
      expect(
        trace.steps,
        contains('capture.stop'),
        reason: 'and what was already said is flushed, not dropped',
      );
    });

    test('a device sorting higher does not displace this one', () async {
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();

      await calls.participantsBecome(['zzzzzzzzzz', calls.client.deviceID!]);
      expect(call.isRecording, isTrue);
      expect(trace.steps, isNot(contains('capture.stop')));
    });

    test('a recorder that will not start does not fail the call', () async {
      // Recording is not the call. A tap that cannot open costs analytics; it
      // must never stop someone placing a voice call.
      final (call, calls, _, capture) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      capture.startError = StateError('no renderer available');

      await call.start(roomStub(calls.client), video: false);

      expect(call.stage, CallStage.connected);
      expect(trace.steps, contains('announce'));
    });

    test('a handover is not overtaken by the one before it', () async {
      // A device can be displaced and reinstated faster than a flush completes.
      // Starting the new recording while the old stop is still unwinding would
      // let that stop cancel the new tap and close its sink underneath it.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();

      capture.holdStop = Completer<void>();
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(trace.steps, [
        'capture.stop',
      ], reason: 'the restart waits for the stop it follows');

      capture.holdStop!.complete();
      await pumpEventQueue();
      expect(trace.steps, ['capture.stop', 'capture.start']);
    });

    test('hanging up waits for a flush already in progress', () async {
      // A device displaced moments before the hangup has a stop still unwinding
      // while it no longer counts as capturing. Finishing teardown then would
      // let the call be written before the last words were transcribed.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);

      capture.holdStop = Completer<void>();
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      var torn = false;
      final hangingUp = call.hangUp().then((_) => torn = true);
      await pumpEventQueue();
      expect(torn, isFalse, reason: 'teardown is waiting on the flush');

      capture.holdStop!.complete();
      await hangingUp;
      expect(torn, isTrue);
    });

    test('hanging up asks the recorder not to wait for choreo', () async {
      // The one place this is decided. Teardown must release the microphone and
      // the membership without waiting on a transcription, because until the
      // membership is back this account reads as busy -- which refuses the next
      // call AND silently swallows an incoming ring.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);

      await call.hangUp();

      expect(
        capture.stopSettledDeliveries.first,
        isFalse,
        reason: 'teardown must not hold the call open for choreo',
      );
    });

    test('a start that threw is retried by the next election', () async {
      // Recording state must follow what actually happened, not what was
      // intended, or a failed tap is remembered as open and never reattempted.
      final (call, calls, _, capture) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      capture.startError = StateError('no renderer');
      await call.start(roomStub(calls.client), video: false);

      expect(call.isRecording, isFalse, reason: 'it did not actually start');

      capture.startError = null;
      trace.steps.clear();
      await calls.participantsBecome([calls.client.deviceID!, 'zzzzzzzzzz']);
      expect(trace.steps, contains('capture.start'));
      expect(call.isRecording, isTrue);
    });

    test('a phantom sibling is dropped by the periodic re-election', () async {
      // A sibling device that crashed leaves a membership that lapses on a
      // timer, not an event. This device deferred to it; the periodic tick is
      // what lets it notice the phantom is gone and take over recording.
      final (call, calls, _, _) = await build();
      // A call has to have somebody on it to be recorded: nothing is
      // captured while it is still ringing.
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse, reason: 'deferred to the lower id');

      // The phantom expires and leaves room state.
      calls.devicesInCall = [calls.client.deviceID!];
      await call.tickReelectionForTest();

      expect(call.isRecording, isTrue, reason: 'it took over');
    });

    test('participant changes after hangup are ignored', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      trace.steps.clear();

      await calls.participantsBecome(['AAAAAAAAAA']);
      expect(trace.steps, isEmpty, reason: 'the call is over');
    });
  });

  test('notifies listeners as the stage changes', () async {
    final (call, calls, _, _) = await build();
    var notifications = 0;
    call.addListener(() => notifications++);
    await call.start(roomStub(calls.client), video: false);
    await call.hangUp();
    expect(
      notifications,
      3,
      reason:
          'connected, then the outcome the moment ending begins, then '
          'ended once teardown finishes',
    );
  });
  group('the outcome', () {
    test('is decided and notified the INSTANT ending begins, not after '
        'teardown', () async {
      // The receiver's screen closes off this. The stage only reaches ended
      // after the whole unwind — a held flush here stands in for the seconds
      // of tap detach and upload settling — and waiting for it is exactly the
      // 5-10s dead screen the user reported.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      CallOutcome? seenOutcome;
      call.addListener(() => seenOutcome ??= call.outcome);

      final teardown = Completer<void>();
      capture.holdStop = teardown;
      final hangingUp = call.hangUp();
      expect(
        seenOutcome,
        CallOutcome.ended,
        reason: 'the outcome must be known before teardown even starts',
      );
      expect(
        call.stage,
        isNot(CallStage.ended),
        reason:
            'stage lags — that '
            'is the point of the outcome',
      );

      teardown.complete();
      await hangingUp;
      expect(call.stage, CallStage.ended);
    });

    test('is failed when the account is already in a call', () async {
      // The refusal must be a FAILED outcome, not a stage alone: the session
      // and the start guard both key off the outcome, and without it this sat
      // as a live-looking call that blocked every later start.
      final (call, calls, _, _) = await build();
      calls.joinError = const AlreadyInACall();
      await call.start(roomStub(calls.client), video: false);
      expect(call.outcome, CallOutcome.failed);
    });

    test('is declined when the peer turned the call down', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      await calls.peerDeclines();
      // A decline waits a beat for an answer on the peer's other device;
      // nobody answers here, so it stands.
      await call.declineTimeoutForTest();
      expect(call.outcome, CallOutcome.declined);
    });

    test(
      'is failed, with the error, before the failure teardown runs',
      () async {
        final (call, calls, _, _) = await build();
        calls.remotePresent = true;
        calls.announceError = StateError('state event rejected');

        CallOutcome? seen;
        Object? seenError;
        call.addListener(() {
          if (seen == null && call.outcome != null) {
            seen = call.outcome;
            seenError = call.error;
          }
        });
        await call.start(roomStub(calls.client), video: false);
        expect(seen, CallOutcome.failed);
        expect(
          seenError,
          isStateError,
          reason: 'the screen shows WHAT failed the moment it fails',
        );
      },
    );
  });

  group('a hangup landing while the call is still coming up', () {
    test('does not report the call connected after it was torn down', () async {
      // start() checks for a hangup after every await for a reason: without the
      // check after ringing, teardown runs, then start() resumes and moves the
      // stage to connected. The screen then shows a live call that no longer
      // exists, and the microphone is already released.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      await call.hangUp();
      held.complete();
      await starting;

      expect(call.stage, isNot(CallStage.connecting));
      expect(
        call.stage,
        anyOf(CallStage.ended, CallStage.declined),
        reason: 'a torn-down call must not come back as connected',
      );
    });

    test('leaves nothing subscribed for a decline', () async {
      // Teardown cancels the decline subscription, then start() resumed and
      // made a NEW one — after the only thing that could cancel it had already
      // run. It then outlived the call for the lifetime of the client.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await call.hangUp();
      held.complete();
      await starting;
      await pumpEventQueue();

      expect(
        calls.watchingForDeclines,
        isFalse,
        reason: 'an abandoned call must leave nothing subscribed',
      );
    });

    test('a decline that beats the ring home is not lost', () async {
      // The subscription is older than the id it matches, so a decline can
      // arrive while our own send is still returning. Dropping it left the
      // caller ringing at someone who had already turned them down.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      // Turned down before ring() has even returned.
      await calls.peerDeclines();
      held.complete();
      await starting;
      await call.settled;
      await call.declineTimeoutForTest();

      expect(call.wasDeclined, isTrue);
      expect(call.stage, CallStage.declined);
    });

    test('still remembers that the other side was rung', () async {
      // Their phone rang. A hangup a moment later must still leave a record —
      // otherwise a call someone saw and missed leaves no trace at all.
      final (call, calls, _, _) = await build();
      final held = Completer<void>();
      calls.holdRing = held;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      final hangingUp = call.hangUp();
      held.complete();
      await starting;
      await hangingUp;

      expect(call.notificationEventId, isNotNull);
    });

    test('a call joined with no ring can still be credited', () async {
      // Neither rang nor was rung — a device joining a call already under way.
      // Its membership is the only event in the room it can anchor to, and
      // without it every word its learner spoke went uncredited.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      expect(call.placedCall, isFalse);
      expect(call.notificationEventId, isNull);
      expect(call.membershipEventId, isNotNull);
    });
  });
  group('a hangup during the LAST step of coming up', () {
    test('abandons rather than reporting the call connected', () async {
      // The final step is the one a missing guard actually shows up in: every
      // earlier step is masked by the NEXT step's check, so only here can an
      // unguarded await let a torn-down call report itself connected.
      final (call, calls, _, capture) = await build();
      final ringGate = Completer<void>();
      final stopGate = Completer<void>();
      calls.holdRing = ringGate;
      capture.holdStop = stopGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      // The peer ANSWERS while our ring is still sending — recording starts
      // (nothing records until somebody is on the call), and then a sibling
      // that outranks us appears, so the election queues a held handover that
      // the final step will wait on. Without the peer the displacement stops
      // nothing and the race this test exists to arrange is not arranged (it
      // passed vacuously for a while exactly that way).
      calls.remotePresent = true;
      await pumpEventQueue();
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await pumpEventQueue();
      ringGate.complete();
      await pumpEventQueue();

      // Every stage this call ever reports. Asserting only the final one cannot
      // see the defect: the hangup's own transition to ended lands afterwards
      // and overwrites it, so a call that briefly announced itself connected
      // looks identical to one that never did.
      final seen = <CallStage>[];
      call.addListener(() => seen.add(call.stage));

      // Now the hangup lands, with only the final await left to catch it.
      final hangingUp = call.hangUp();
      stopGate.complete();
      await starting;
      await hangingUp;

      expect(
        seen,
        isNot(contains(CallStage.connected)),
        reason:
            'a torn-down call must never report itself connected, even once',
      );
      expect(call.stage, CallStage.ended);
    });
  });

  group('a hangup during any step of coming up', () {
    // Coming up is a sequence of network round-trips and a hangup can land
    // inside any of them. Every step must abandon the call, and this covers
    // them ALL rather than the one a review happened to name — a step added
    // later that forgets the guard fails here.
    for (final step in const ['join', 'connect', 'announce', 'ring']) {
      test('a hangup during $step abandons the call', () async {
        final (call, calls, media, _) = await build();
        final gate = Completer<void>();
        switch (step) {
          case 'join':
            calls.holdJoin = gate;
          case 'connect':
            media.beforeConnect = gate.future;
          case 'announce':
            calls.holdAnnounce = gate;
          case 'ring':
            calls.holdRing = gate;
        }

        final starting = call.start(roomStub(calls.client), video: false);
        await pumpEventQueue();
        final hangingUp = call.hangUp();
        gate.complete();
        await starting;
        await hangingUp;

        expect(
          call.stage,
          CallStage.ended,
          reason: 'a hangup during $step must abandon, not connect or fail',
        );
      });
    }
  });
  group('when both people call at the same moment', () {
    test('a caller alone does not think the peer also called', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('the peer ringing us while we ring them is noticed', () async {
      // Both then believe they placed the call, so both would write it to the
      // room. Noticing it is what lets exactly one of them do so — and noticing
      // it from their ring rather than from an ordering keeps a call nobody
      // answered written, since only the caller runs that teardown.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      ringGate.complete();
      await starting;

      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isTrue);
    });

    // The failure a skew allowance cannot fix: glare used to compare OUR local
    // start against a timestamp from THEIR device (or from the server), so a
    // device two minutes out fell outside a three-second window. One side saw
    // the glare and the other did not, they both wrote the call, and the
    // conversation carried two cards for one call. Nothing here reads their
    // clock at all now.
    // Their ring is a timeline event and their membership is room state; the
    // two arrive independently, and the ring routinely wins. Requiring the
    // state to be there ALREADY meant a ring that beat it was dropped and
    // never revisited: neither side saw the glare, both wrote the call, and
    // the conversation carried it twice.
    test('a ring that beats their membership state is still glare', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await pumpEventQueue();
      // Nothing of theirs has synced yet: neither presence nor absence.
      calls.callerPresenceOverride = PeerPresence.unknown;

      await calls.peerAlsoCalls();
      expect(
        call.peerAlsoPlaced,
        isTrue,
        reason: 'silence from room state is not proof they are not calling',
      );
    });

    test('a caller whose clock is hours out is still glare', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await pumpEventQueue();

      await calls.peerAlsoCalls(age: const Duration(hours: -2));
      expect(
        call.peerAlsoPlaced,
        isTrue,
        reason: 'their ring reached us as we began; their clock is not ours',
      );
    });

    test('a ring placed later is a new call of theirs, not this one', () async {
      // A ring sent well after this call began belongs to a call they placed
      // while we were already in one. Counted, this side believes the other
      // also placed THIS call; the write is then settled by comparing ids, and
      // the side that actually placed it can stand aside — so nobody writes it
      // and the call is missing from the conversation.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await pumpEventQueue();
      expect(call.hadPeer, isTrue);

      // Their ring REACHES us thirty seconds after we began, which is how a
      // call they placed while we were already in one actually arrives.
      // (Backdating our start is the same thing measured from the other end,
      // and does not need the test to wait thirty seconds.)
      call.backdateStartForTest(const Duration(seconds: 30));
      await calls.peerAlsoCalls();
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('names who else was calling, for deciding who writes', () async {
      // The room cannot always say who the other person is — a direct chat
      // whose peer has not resolved — and both sides then defaulted to writing,
      // putting two cards in the conversation for one call. Their ring is proof
      // of who it was, and it is only ever needed when that ring exists.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      await calls.peerAlsoCalls();

      expect(call.peerAlsoPlaced, isTrue);
      expect(call.peerRingSenderId, '@peer:server');
    });

    test('an answerer does not mistake the caller ring for glare', () async {
      // Answering shows a banner from the caller's own ring, and a quick answer
      // lands inside the glare window of it. That ring is not evidence the peer
      // ALSO placed a call — this side placed nothing — so it must not set the
      // flag the who-writes decision reads. Glare is only ever between two
      // callers, and an answerer is not one.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true; // the caller is already on the call
      await call.start(roomStub(calls.client), video: false, answering: true);
      await calls.peerAlsoCalls(); // the caller's own ring, landing now

      expect(call.placedCall, isFalse);
      expect(
        call.peerAlsoPlaced,
        isFalse,
        reason: 'an answered call has no glare to detect',
      );
    });

    test('is noticed even when they get here before their ring', () async {
      // Each side joins the SFU before it rings, so in a genuine simultaneous
      // call their presence routinely reaches us BEFORE their ring does.
      // Standing the ring down because they were already here left both sides
      // believing they alone had placed the call, so both wrote it and the
      // conversation carried two cards for one call.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      calls.remotePresent = true;
      await pumpEventQueue();
      expect(call.hadPeer, isTrue, reason: 'they are here first');

      await calls.peerAlsoCalls();
      expect(call.peerAlsoPlaced, isTrue);
    });

    test('a ring from a call of theirs that ended is not glare', () async {
      // A ring stays valid for up to a minute and a half. One from a call that
      // already ended — they rang, nobody answered, they hung up — is still
      // unexpired when we call them back moments later. Counted, this side
      // stands aside from writing a call the other side is not writing either,
      // and it is missing from the conversation.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      // Sent twenty seconds ago and still well inside its lifetime -- but
      // they hung up, so the device that rang holds no call any more. That,
      // not the timestamp, is what tells the two apart: an old ring and a
      // fresh one arrive the same way.
      calls.callerHoldsMembership = false;
      await calls.peerAlsoCalls(age: const Duration(seconds: 20));
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('an old call of theirs is not somebody calling now', () async {
      // Sync replays events. Counting a stale one would make this side stand
      // aside from writing the call, while the other side — not in a call at
      // all — never writes it either, and the call would vanish.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls(age: const Duration(hours: 1));
      ringGate.complete();
      await starting;

      expect(call.peerAlsoPlaced, isFalse);
    });
  });
  group('when both people call at the same moment', () {
    test('a caller alone does not think the peer also called', () async {
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isFalse);
    });

    test('the peer ringing us while we ring them is noticed', () async {
      // Both then believe they placed the call, so both would write it to the
      // room. Noticing it is what lets exactly one of them do so — and noticing
      // it from their ring rather than from an ordering keeps a call nobody
      // answered written, since only the caller runs that teardown.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      ringGate.complete();
      await starting;

      expect(call.placedCall, isTrue);
      expect(call.peerAlsoPlaced, isTrue);
    });
  });
  group('a device where no tap could be attached', () {
    test('is tried again by the next election', () async {
      // Starting succeeds and records nothing — no point to read from, or the
      // platform side not up yet. Treating that as recording would stop every
      // later election from trying, and the call would go uncredited for a
      // failure that may have been momentary.
      final (call, calls, _, capture) = await build();
      capture.attachesNothing = true;
      await call.start(roomStub(calls.client), video: false);

      final first = trace.steps.where((s) => s == 'capture.start').length;
      capture.attachesNothing = false;
      // A real change to who is in the call, so an election actually runs.
      calls.remotePresent = true;
      await pumpEventQueue();

      expect(
        trace.steps.where((s) => s == 'capture.start').length,
        greaterThan(first),
        reason: 'a tap that did not attach must be attempted again',
      );
      expect(call.isRecording, isTrue);
    });
  });
  group('a peer who leaves while the call is still coming up', () {
    test('is still remembered as having been there', () async {
      // Someone already here can go while the first handover settles. Reading
      // their presence afterwards had this call believe nobody ever answered —
      // no teardown when they left, and the conversation recorded as unanswered.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      // Hold the first handover open, which is the window this is about.
      final handover = Completer<void>();
      capture.holdStart = handover;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      // They go while the first handover is still settling.
      calls.remotePresent = false;
      handover.complete();
      await starting;
      await call.settled;

      expect(
        call.hadPeer,
        isTrue,
        reason: 'they were here, so the call was answered',
      );
    });
  });

  group('when the microphone is released', () {
    test('before anything waits on uploads or transcription', () async {
      // Finishing waits for what has been recorded to be sent and transcribed,
      // which can take a minute. Holding the devices through that meant the
      // learner hung up and was still being heard.
      final (call, calls, _, _) = await build();
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      await call.hangUp();

      expect(
        trace.steps.indexOf('media.dispose'),
        lessThan(trace.steps.indexOf('capture.finish')),
        reason: 'the microphone goes first; sending audio does not need one',
      );
    });
  });

  group('a hangup landing the instant a join returns', () {
    test('still gives the call back', () async {
      // The service holds the call from the moment joining returns. Giving up
      // without writing that down skipped the retract, and the service then
      // believed it was still in a call and refused every later one — the
      // learner could not call again at all.
      final (call, calls, _, _) = await build();
      final joinGate = Completer<void>();
      calls.holdJoin = joinGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      final hangingUp = call.hangUp();
      joinGate.complete();
      await starting;
      await hangingUp;

      expect(
        trace.steps,
        contains('retract'),
        reason: 'a call that was joined must always be given back',
      );
    });
  });

  group('the anchor a joining device credits its speech to', () {
    test('is read before the call is given up, not after', () async {
      // Retracting releases what identifies the call, and the membership can no
      // longer be matched to it afterwards — which is exactly the device that
      // needs it: one that joined a call already under way and so has no ring of
      // its own to point at.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      // The echo did not arrive in time, so announcing returned nothing — the
      // case the late read exists for.
      calls.membershipId = null;
      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();

      expect(call.placedCall, isFalse);
      expect(call.notificationEventId, isNull);
      expect(
        call.membershipEventId,
        isNotNull,
        reason: 'without this the whole call goes uncredited',
      );
    });
  });

  group('a ring arriving before our media is up', () {
    test('still counts as the two of us calling at once', () async {
      // The window starts when our call does, not when our media happens to be
      // ready. Watching only from there let a simultaneous call through, and
      // both sides would write the call to the room.
      final (call, calls, media, _) = await build();
      final connecting = Completer<void>();
      media.beforeConnect = connecting.future;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerAlsoCalls();
      connecting.complete();
      await starting;

      expect(call.peerAlsoPlaced, isTrue);
    });
  });
  group('a decline replayed out of the room history', () {
    test('does not end a call that has only just started', () async {
      // Sync replays events. A decline from an earlier call arriving as this one
      // begins would end it on the spot, and the learner would watch their call
      // hang up by itself.
      final (call, calls, _, _) = await build();
      final ringGate = Completer<void>();
      calls.holdRing = ringGate;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await calls.peerDeclinedLongAgo();
      ringGate.complete();
      await starting;
      await call.settled;

      expect(call.wasDeclined, isFalse);
      expect(call.stage, CallStage.connected);
    });
  });
}
