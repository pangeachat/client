import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show AudioTrack;
import 'package:matrix/matrix.dart' as matrix show Room;
import 'package:matrix/matrix.dart' hide Room;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/active_call.dart';
import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';
import 'package:fluffychat/routes/chat/calls/call_capture.dart';
import 'package:fluffychat/routes/chat/calls/call_media.dart';
import 'package:fluffychat/routes/chat/calls/call_roster.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/capture_election.dart';
import 'package:fluffychat/routes/chat/calls/pcm_chunker.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'call_token_repo_test.dart' show jwtWith;

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

  /// When this device's own membership was written. A device that is IN a
  /// call can always date its own join, and a departure is only measured
  /// against that.
  DateTime? ourJoinAt = DateTime.now().subtract(const Duration(seconds: 5));

  /// When each membership event was written, BY EVENT ID, for the tests that
  /// need two of them to be different moments.
  ///
  /// The one answer this used to give every id made a stale anchor and a fresh
  /// one indistinguishable by construction: a floor derived from the previous
  /// call's membership and one derived from this call's came out identical, so
  /// nothing here could see the difference between them. Empty by default, so
  /// every test that does not care still gets [ourJoinAt] for any id.
  Map<String, DateTime> writtenAt = const {};

  @override
  DateTime? membershipWrittenAt(matrix.Room room, String eventId) =>
      writtenAt[eventId] ?? ourJoinAt;

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

  /// The floors the call passed down on the last presence read.
  ///
  /// RECORDED, not acted on. Re-implementing the real filter here would make
  /// the test agree with a copy of the code it is testing; what the call is
  /// answerable for is the floor it computes, and that is asserted directly.
  DateTime? lastNotBefore;
  DateTime? lastGoneAfter;

  @override
  PeerPresence peerPresenceInCurrentCall(
    matrix.Room room,
    String peerId, {
    DateTime? notBefore,
    DateTime? goneAfter,
  }) {
    lastNotBefore = notBefore;
    lastGoneAfter = goneAfter;
    return peerPresenceOverride ??
        (peerMembershipPresent ? PeerPresence.live : PeerPresence.gone);
  }

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

  /// The grant a successful join hands back. Settable so a test can supply a
  /// token whose claims say something, which is what the roster is told.
  CallToken grant = const CallToken(jwt: 'jwt', url: 'ws://sfu');

  @override
  Future<CallToken> join(matrix.Room room) async {
    trace('join');
    // Claimed before the first await, as the real one does: the claim exists
    // precisely to cover the window this hold stands in for.
    joinClaimed = true;
    if (holdJoin != null) await holdJoin!.future;
    if (joinError != null) throw joinError!;
    return grant;
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

  /// Whether this double announces the live microphone the way the real object
  /// does -- from INSIDE connect, with the camera and the rest of coming up
  /// still to come. Turned off, it stands in for a connect that returned
  /// without ever reaching that announcement, which is how a test tells the
  /// grant apart from connect merely finishing.
  bool announcesMicrophone = true;

  @override
  Future<void> connect(CallToken grant, {required bool video}) async {
    if (beforeConnect != null) await beforeConnect;
    trace('connect(video: $video)');
    if (connectError != null) throw connectError!;
    // Untraced deliberately: this is a moment inside connect, not a step of
    // it, and what listens is timed against the call's own steps.
    if (announcesMicrophone) onMicrophoneLive?.call();
  }

  final _track = FakeTrack();

  /// Supplied by the test rather than built from a live connection.
  FakeRoster? fakeRoster;

  /// What the call told the roster about the token it dialled with.
  MetadataGrant? rosterGrant;

  @override
  CallRoster roster({
    required String myUserId,
    MetadataGrant metadataGrant = MetadataGrant.unknown,
  }) {
    rosterGrant = metadataGrant;
    return fakeRoster!;
  }

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

  /// Run immediately after the first frame of a run, inside the window between
  /// it and the next election.
  void Function()? afterFirstFrame;

  /// Whether this device has anywhere to record THROUGH. Modelled rather than
  /// inherited, because it is what the election reads and a double that always
  /// answered true could not stand up the case the ranking exists for.
  ///
  /// [start] is overridden too, so the real answer could never move here
  /// whatever this returned. What actually produces it -- a platform with no
  /// tap point, residue that survived a retry, taps that attached and died --
  /// is pinned in call_capture_test, under 'whether this device can record at
  /// all' and 'a device whose tap keeps dying'. These tests own the other half:
  /// what the election does once the answer is false.
  bool tapWorks = true;

  @override
  bool get canCapture => tapWorks;

  /// Every discard request, in order. A list rather than a flag: the request is
  /// level-triggered on every election, so what matters is the value at the
  /// moment the flush ran, not that one was ever made.
  final List<bool> discardRequests = [];

  @override
  void setDiscardOnStop(bool discard) {
    discardRequests.add(discard);
    super.setDiscardOnStop(discard);
  }

  @override
  bool get isRecording => _recording;

  /// Whether audio is actually reaching this recorder. Modelled as "recording
  /// and not pretending otherwise" because [start] here always delivers; the
  /// real gap between attaching a tap and a frame arriving is pinned in
  /// call_capture_test, under 'whether audio is actually reaching the recorder'.
  bool audioFlows = true;

  @override
  bool get capturingAudio => _recording && audioFlows && !_mutedHere;

  /// The run this fake is in. Bumped by [start] so a stop-restart pair reads as
  /// two runs, exactly as the real one does.
  int _run = 0;

  @override
  String? get captureRun => capturingAudio ? '$_run' : null;

  /// Modelled, because a mute really does end the run and start a new one when
  /// the learner speaks again -- and a double that ignored it could not show a
  /// sibling being told about the gap.
  bool _mutedHere = false;

  @override
  void setMuted(bool muted) {
    _mutedHere = muted;
    if (!muted) _run++;
    super.setMuted(muted);
  }

  @override
  Future<void> start(covariant Object track) async {
    trace('capture.start');
    if (holdStart != null) await holdStart!.future;
    if (startError != null) throw startError!;
    // A device with no working tap point attaches nothing and says so, exactly
    // as the real one does: start returns, and isRecording stays false.
    _recording = !attachesNothing && tapWorks;
    if (_recording) {
      _run++;
      // Modelled, because WHEN the first frame lands is load-bearing: the
      // ledger of what the siblings were doing is opened by it, and a double
      // that never delivered one would open the ledger at the next election
      // instead -- judging a sibling on a reading taken after it changed.
      onCaptureStarted?.call();
      // The window between that frame and the next election, which in a real
      // call is up to a whole presence tick. A test that wants to change what a
      // sibling is doing INSIDE it has nowhere else to stand.
      afterFirstFrame?.call();
    }
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

  /// The tap died and this recorder said so, which is what the real one does:
  /// it stops itself first and reports afterwards, so whoever hears it queues
  /// its restart behind a stop that is already in flight.
  void loseTap() {
    unawaited(stop());
    onCaptureLost?.call();
  }

  /// The tap died and the recorder has concluded it will not attach another
  /// one during this call -- which is what the real one does once the deaths
  /// reach its limit, and the only honest producer of "this device cannot
  /// record" the election has.
  void loseTapForGood() {
    tapWorks = false;
    loseTap();
  }

  /// The recording is gone and NOBODY was told — the callback was never wired,
  /// or was lost in a refactor. What is left is a recorder that answers
  /// isRecording false while its owner still believes it is recording.
  void loseTapUnannounced() => _recording = false;
}

/// A believable SFU join stamp for the tests that are not about join times.
final fakeJoinTime = DateTime.utc(2026, 8, 29, 12);

/// The SFU's participant list, without an SFU.
///
/// Overrides only the two reads that need a live connection, so everything the
/// real roster decides — who is a peer, who is a sibling device, and the freeze
/// while disconnected — is the code under test rather than a stub.
class FakeRoster extends CallRoster {
  FakeRoster({required super.room, required super.myUserId, this.trace});

  /// Shared with the recorder, so a test can assert the ORDER of a write
  /// against the stop it is supposed to precede. Microtask counting cannot say
  /// that; a single ordered list can.
  final Trace? trace;

  /// OFF by default. Most tests in this file assert on the trace by exact
  /// equality, and a double that volunteered extra steps into it would rewrite
  /// what every one of them is checking.
  bool traceWrites = false;

  Set<String> identities = {};
  bool connected = true;
  bool disposed = false;

  /// Modelled because the two ways of not being connected mean opposite things:
  /// while the connection is coming back the roster holds its last picture, and
  /// once it has gone for good it clears. A double with only one of them turned
  /// a reconnect into everybody hanging up.
  bool recovering = false;

  /// identity -> the join stamp the SFU reports, and whether it has described
  /// that participant at all.
  Map<String, (bool, DateTime)> joins = {};

  /// identity -> published attributes, which is how a sibling says whether it
  /// can record.
  Map<String, Map<String, String>> attributes = {};

  /// This device's own membership, once the SFU has given us one.
  (bool, DateTime)? myJoin;

  @override
  RosterRead get read => RosterRead(
    remotes: [
      for (final id in identities)
        RosterMember(
          identity: id,
          described: joins[id]?.$1 ?? true,
          joinedAt: joins[id]?.$2 ?? fakeJoinTime,
          attributes: attributes[id] ?? const {},
        ),
    ],
    me: myJoin == null
        ? null
        : RosterMember(
            identity: myUserId,
            described: myJoin!.$1,
            joinedAt: myJoin!.$2,
          ),
  );

  /// What this device told its siblings about its CAPABILITY, in order.
  ///
  /// Only writes that carry the capability key are recorded. Two facts now
  /// travel in one write, and a list that read every write as a capability
  /// announcement would report one every time this device said something about
  /// what it was doing instead.
  final List<bool> announced = [];

  /// And what it told them it was actually DOING, in order. Null means it said
  /// it was not recording; a string is the run it named.
  final List<String?> announcedCapturing = [];

  /// Every write exactly as it went out. A list of MAPS, because what matters
  /// for the retraction is not only that it was published but that it was not
  /// queued behind another round trip.
  final List<Map<String, String>> publishedMaps = [];

  /// Held open by a test to keep an announcement in flight, which is the state
  /// in which the live answer and the landed one differ.
  Completer<void>? holdAnnounce;

  @override
  Future<bool> publishAttributes(Map<String, String> attributes) async {
    publishedMaps.add(Map.of(attributes));
    final capturingWritten = attributes[CallRoster.capturingAttribute];
    if (traceWrites && capturingWritten != null) {
      trace?.call(
        CaptureReport.of('me', capturingWritten).run == null
            ? 'publish(not recording)'
            : 'publish(recording)',
      );
    }
    final capability = attributes[CallRoster.canCaptureAttribute];
    if (capability != null) announced.add(capability != 'no');
    final capturing = attributes[CallRoster.capturingAttribute];
    if (capturing != null) {
      announcedCapturing.add(CaptureReport.of('me', capturing).run);
    }
    if (holdAnnounce != null) await holdAnnounce!.future;
    // A COMPLETED TURN, not a completed microtask. `setAttributes` is a signal
    // round trip that waits up to five seconds for the SFU; a double that
    // returned without ever yielding to the event loop would make a second
    // write look nearly free, and hide the whole cost of queueing one behind
    // another.
    await Future<void>.delayed(Duration.zero);
    return true;
  }

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

  /// The generation handed out by the last start, so the fake can check that
  /// later instructions carry the SAME one back -- an instruction stamped
  /// with another call's claim is exactly the bug the generation exists for.
  int lastGeneration = 0;

  /// The text the platform would render, recorded so a call that passed
  /// English on a Hindi phone is a test failure rather than something only a
  /// screenshot would catch.
  String lastMuteLabel = '';
  String lastChannelName = '';

  @override
  Future<int> start({
    required String peer,
    required bool video,
    required String muteLabel,
    required String channelName,
  }) async {
    trace('fgs.start(video: $video)');
    lastMuteLabel = muteLabel;
    lastChannelName = channelName;
    final hold = holdStart;
    if (hold != null) await hold.future;
    if (!startReturns) return 0;
    return lastGeneration = lastGeneration + 1;
  }

  int _epoch = 0;

  @override
  Future<void> stop({required int generation}) async =>
      trace('fgs.stop(gen: $generation)');

  @override
  Future<void> setCamera(bool on, {required int generation}) async =>
      trace('fgs.camera($on, gen: $generation)');

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
  void discarded(PcmChunk chunk) {}

  @override
  Future<bool> close() async => true;
}

/// A logged-in client that can be made to forget its device id mid-call.
///
/// The SDK clears the id on logout and offers no way to set one, and a call
/// cannot start without one at all -- so the only window in which an election
/// can see a null is a logout landing while a call is already up. This is the
/// one way to stand a test in that window.
class ForgetfulClient extends Client {
  ForgetfulClient(
    super.clientName, {
    super.httpClient,
    required super.database,
  });

  /// Set to reproduce the logout, from the moment it is set onward.
  bool forgotDevice = false;

  @override
  String? get deviceID => forgotDevice ? null : super.deviceID;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Trace trace;

  /// Logged in, because the recording election ranks this device against its
  /// siblings by device id and a client that never logged in has none.
  Future<ForgetfulClient> bareClient() async {
    final client = ForgetfulClient(
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
      trace: trace,
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

  group('a call cannot outlive the room it is in', () {
    // Leaving the chat goes straight to the SDK and knows nothing about
    // calls: the media, the recording and Android's foreground service all
    // carried on afterwards, and the learner had to notice and hang up
    // separately.
    test('leaving the room ends the call', () async {
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      final room = matrix.Room(
        id: '!r:server',
        client: calls.client,
        membership: Membership.join,
      );
      await call.start(room, video: false);
      expect(call.stage, CallStage.connected);

      room.membership = Membership.leave;
      await Future<void>.delayed(ActiveCall.presenceRecheck * 2);
      await pumpEventQueue();

      expect(
        call.stage,
        CallStage.ended,
        reason: 'the call went on in a room the learner had left',
      );
    });
  });

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

  group('a call that failed', () {
    // A rejoin whose token, focus or SFU connect missed tears down like any
    // other failure. Erasing the breadcrumb there threw away the learner's
    // only way back to a call that is still live, with the peer sitting in it
    // waiting -- and the failed-call screen offers only Close.
    test('keeps the breadcrumb, so returning can be tried again', () async {
      SharedPreferences.setMockInitialValues({});
      await CallBreadcrumb.drop(
        account: 'active-call-test',
        roomId: '!r:server',
        membershipEventId: r'$original-membership',
      );

      final (call, calls, _, _) = await build();
      calls.joinError = StateError('no focus');
      await call.start(
        roomStub(calls.client),
        video: false,
        rejoinAnchor: r'$original-membership',
      );

      expect(call.stage, CallStage.failed);
      await pumpEventQueue();
      expect(
        await CallBreadcrumb.read('active-call-test'),
        isNotNull,
        reason: 'the way back must outlive a failed attempt to take it',
      );
    });

    test('a call that ENDED cleanly erases it', () async {
      SharedPreferences.setMockInitialValues({});
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(
        await CallBreadcrumb.read('active-call-test'),
        isNotNull,
        reason: 'dropped on join',
      );

      await call.hangUp();
      await pumpEventQueue();
      expect(await CallBreadcrumb.read('active-call-test'), isNull);
    });
  });

  group('a membership whose echo is late', () {
    // The ring must name our membership, and the wait for that id is bounded
    // so a caller is never left hanging. When the echo merely arrives LATE,
    // skipping the ring outright meant the callee's phone never rang, no push
    // went out, and the caller sat through the answer timeout for a call the
    // other person was never told about.
    test('still rings, once the id arrives', () async {
      final (call, calls, _, _) = await build();
      calls.membershipId = null; // announce comes back with nothing
      calls.roomMembershipId = null; // and state has not caught up either
      calls.remotePresent = false;

      await call.start(roomStub(calls.client), video: false);
      expect(
        trace.steps,
        isNot(contains('ring')),
        reason: 'there is nothing to name the ring after yet',
      );

      // The echo lands: state now knows our membership.
      calls.roomMembershipId = r'$late-membership';
      call.lookForALateAnchorNow();
      await pumpEventQueue();

      expect(trace.steps, contains('ring'));
      expect(call.rangOut, isTrue);
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
    // ...but not before we can date our own join. Until then the newest thing
    // the peer wrote is the retraction that ended the LAST call, which on a
    // redial is seconds old -- and acting on it tore down calls two seconds
    // after they were answered. The browser suite caught that; nothing in
    // this file could, because the fake always knew when we joined.
    test('but not before this device can date its own join', () async {
      final (call, calls, _, _) = await build();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      calls.ourJoinAt = null; // our membership is not readable yet
      calls.peerPresenceOverride = PeerPresence.unknown;
      await call.start(roomStub(calls.client), video: false, answering: true);
      expect(call.stage, CallStage.connected);

      // The previous call's retraction, still the newest thing they wrote.
      calls.peerPresenceOverride = PeerPresence.gone;
      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);
      await call.tickReelectionForTest();

      expect(
        call.stage,
        isNot(CallStage.ended),
        reason: 'an undateable departure must not end a call that just began',
      );
    });

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

  group('the floors a departure is measured against', () {
    // Both floors are derived from this device's membership event, and that
    // anchor is CORRECTABLE: it is filled lazily from room state, where the
    // call id is the room id -- so any unexpired membership of ours in this
    // room answers, including one a previous call left standing when its
    // retract was given up on. announce() then overwrites it with the one this
    // call actually wrote.
    //
    // A floor frozen against the old anchor is always OLDER than the truth,
    // and both floors are lower bounds, so the error is always in the same
    // direction: too permissive, always biased toward reading the peer as
    // gone. On any tick where the peer is in the SFU but their new membership
    // has not synced, their newest visible state is the previous call's
    // emptied one -- which a too-old goneAfter lets through as a departure
    // from THIS call. That is leftDeliberately, and the call the learner has
    // just answered is torn down within a second or two with "The other
    // participant ended the call" while they are still talking. It is verbatim
    // the regression goneAfter was added to prevent.
    test('move to the membership this call announced', () async {
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;

      final previousCall = DateTime.now().subtract(const Duration(minutes: 5));
      final thisCall = DateTime.now();
      // What room state answers before this call has announced.
      calls.roomMembershipId = r'$previousCall';
      // What announcing returns: the membership this call actually wrote.
      calls.membershipId = r'$thisCall';
      calls.writtenAt = {
        r'$previousCall': previousCall,
        r'$thisCall': thisCall,
      };

      // Held so the stale anchor is the only one there is while the presence
      // reads below run. That is the ordinary shape of answering: the room's
      // state is already here, and our own membership has not been written
      // yet.
      final announcing = Completer<void>();
      calls.holdAnnounce = announcing;
      final starting = call.start(
        roomStub(calls.client),
        video: false,
        answering: true,
      );
      await pumpEventQueue();

      // Twice: the first tick fills the anchor from room state, the second is
      // the one that derives the floors from it.
      await call.tickReelectionForTest();
      await call.tickReelectionForTest();
      expect(
        calls.lastGoneAfter,
        previousCall,
        reason:
            'the stale membership is the only anchor there is yet, so this '
            'read has to be measuring against it for the test to mean anything',
      );

      announcing.complete();
      await starting;
      await call.tickReelectionForTest();

      expect(
        calls.lastGoneAfter,
        thisCall,
        reason:
            'the anchor was corrected by announce, so the departure floor '
            'must be too -- an older one lets the PREVIOUS call ending pass '
            'as this one ending',
      );
      expect(
        calls.lastNotBefore,
        CallService.callFloorFrom(thisCall),
        reason: 'the staleness floor is derived from the same anchor',
      );
    });

    test('are still re-asked until the room can date the anchor', () async {
      // The memo may not answer null from a cache. State lags a write, so the
      // first read after the anchor lands can find nothing to date it by, and
      // remembering that "no answer" would freeze the floors off for the whole
      // call -- which is the same too-permissive direction.
      final (call, calls, _, _) = await build();
      calls.remotePresent = true;
      calls.ourJoinAt = null;
      calls.writtenAt = const {};

      await call.start(roomStub(calls.client), video: false, answering: true);
      await call.tickReelectionForTest();
      expect(calls.lastGoneAfter, isNull, reason: 'nothing can date it yet');

      final landed = DateTime.now();
      calls.ourJoinAt = landed;
      await call.tickReelectionForTest();

      expect(
        calls.lastGoneAfter,
        landed,
        reason: 'the write echoed, so the floor is available now',
      );
    });
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
    Future<(ActiveCall, FakeCalls, FakeForeground, FakeMedia)> withForeground({
      bool startReturns = true,
    }) async {
      final calls = FakeCalls(await bareClient(), trace);
      final media = FakeMedia(trace, hasTrack: true);
      final fgs = FakeForeground(trace, startReturns: startReturns);
      final roster = FakeRoster(
        room: media.room,
        myUserId: calls.client.userID ?? '',
        trace: trace,
      );
      media.fakeRoster = roster;
      calls.roster = roster;
      final call = ActiveCall(
        calls: calls,
        media: media,
        capture: FakeCapture(trace),
        foreground: fgs,
      );
      return (call, calls, fgs, media);
    }

    // The leak this pins shut: the start is fired unawaited, so a hangup can
    // land while the platform is still answering. Teardown read the claim as
    // false, skipped the stop, and the ongoing-call service outlived the call.
    test('a start that lands after teardown stops itself', () async {
      final (call, calls, fgs, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      fgs.holdStart = Completer<void>();

      await call.start(roomStub(calls.client), video: false);
      await call.hangUp();
      expect(
        trace.steps,
        isNot(contains(startsWith('fgs.stop'))),
        reason: 'nothing has claimed the service yet',
      );

      fgs.holdStart!.complete();
      await pumpEventQueue();
      expect(
        trace.steps,
        contains(startsWith('fgs.stop')),
        reason: 'the late start must take itself down',
      );
    });

    // `startForegroundService` answers before Android runs the service's own
    // start command, so a success there means "asked for", not "running". A
    // refused promotion stops the service, and the call used to go into the
    // background believing it was protected by something already gone.
    // The instruction has to name the call that issued it. The hop from Dart
    // to the platform is a queue: a camera update or a stop sent by a call
    // that has ended can arrive after the NEXT call has started, and an
    // unstamped one was then applied to that call -- stripping the camera
    // type from a live video call, or stopping a service it had just been
    // told it owned.
    test('every instruction carries the claim its start was given', () async {
      final (call, calls, fgs, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      final issued = fgs.lastGeneration;
      expect(issued, isNot(0), reason: 'the platform accepted the service');

      await call.setForegroundCamera(true);
      await call.hangUp();

      expect(trace.steps, contains('fgs.camera(true, gen: $issued)'));
      expect(trace.steps, contains('fgs.stop(gen: $issued)'));
    });

    test('a refused promotion gives the claim back', () async {
      final (call, calls, fgs, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(trace.steps, contains('fgs.start(video: false)'));

      // The platform reports, after the fact, that it never came up -- and
      // says no again when asked. Nothing is running, so teardown has nothing
      // to stop, and stopping anyway could take down a service another call
      // legitimately owns.
      fgs.startReturns = false;
      call.foregroundRefused();
      await pumpEventQueue();
      await call.hangUp();

      expect(trace.steps, isNot(contains(startsWith('fgs.stop'))));
    });

    test('a refusal whose retry succeeds is stopped like any other', () async {
      final (call, calls, fgs, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);

      // The retry comes up. The claim is real again, so teardown owes the
      // platform a stop -- and it must carry the generation the RETRY was
      // given, not the one the refused attempt held.
      call.foregroundRefused();
      await pumpEventQueue();
      final retried = fgs.lastGeneration;
      await call.hangUp();

      expect(trace.steps, contains('fgs.stop(gen: $retried)'));
    });

    test('a refusal mid-call asks again, once', () async {
      // The platform answers start() before it runs the service, so a refusal
      // can land at any second of the call -- including long after the one
      // checkpoint that used to be the only retry. A call refused at second
      // thirty went into a pocket believing it was protected.
      final (call, calls, fgs, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      final startsAfterJoin = trace.steps
          .where((s) => s.startsWith('fgs.start'))
          .length;

      call.foregroundRefused();
      await pumpEventQueue();
      expect(
        trace.steps.where((s) => s.startsWith('fgs.start')).length,
        startsAfterJoin + 1,
        reason: 'the refusal was not answered with another attempt',
      );

      // And only once: a refusal from the background will not have changed
      // its mind a millisecond later, and a loop is a battery drain.
      call.foregroundRefused();
      await pumpEventQueue();
      expect(
        trace.steps.where((s) => s.startsWith('fgs.start')).length,
        startsAfterJoin + 1,
      );
      await call.hangUp();
    });

    test('starts before anything is awaited, and stops in teardown', () async {
      final (call, calls, _, _) = await withForeground();
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
      expect(trace.steps, contains(startsWith('fgs.stop')));
    });

    test('a failed call still stops the service', () async {
      final (call, calls, _, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.joinError = StateError('no focus');
      await call.start(roomStub(calls.client), video: false);
      expect(call.stage, CallStage.failed);
      expect(
        trace.steps,
        contains(startsWith('fgs.stop')),
        reason: 'every teardown path converges in _unwind',
      );
    });

    /// Every attempt the platform has been asked for, in the order it was
    /// asked -- the entry start and any retry read the same way.
    int startsAsked() =>
        trace.steps.where((s) => s == 'fgs.start(video: false)').length;

    test('a refused start is retried once the microphone is live', () async {
      // The service cannot run before the microphone permission exists; the
      // microphone publishing IS the proof the dialog was answered.
      final (call, calls, fgs, _) = await withForeground(startReturns: false);
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: false);
      expect(
        startsAsked(),
        2,
        reason: 'the entry attempt plus the retry the grant paid for',
      );
      await call.hangUp();
    });

    // The item this closes: the first call's service gets one legal window,
    // and it was being spent on the steps BETWEEN the grant and the end of
    // connect -- the camera, its own permission dialog, another round trip.
    // The learner answering the microphone prompt has often left the app by
    // then, and Android refuses a start from the background.
    test('connect finishing is not what pays for the retry', () async {
      final (call, calls, _, media) = await withForeground(startReturns: false);
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      // A connect that comes up without ever reaching the microphone
      // announcement. Everything else about the call is unchanged, and it
      // still returns perfectly well.
      media.announcesMicrophone = false;

      await call.start(roomStub(calls.client), video: false);

      expect(
        startsAsked(),
        1,
        reason: 'only the grant may spend the retry, never connect returning',
      );
      await call.hangUp();
    });

    test(
      'a grant landing while the first start is still out is not lost',
      () async {
        // The entry start is fired unawaited before the join, so the platform can
        // still be answering it when the microphone comes up. Read through that
        // window the flag says nothing is owed -- of a start that is about to
        // come back refused -- and the call would keep its retry forever.
        final (call, calls, fgs, _) = await withForeground(startReturns: false);
        calls.devicesInCall = [calls.client.deviceID!];
        calls.remotePresent = true;
        fgs.holdStart = Completer<void>();

        await call.start(roomStub(calls.client), video: false);
        expect(startsAsked(), 1, reason: 'the platform has not answered yet');

        fgs.holdStart!.complete();
        await pumpEventQueue();

        expect(
          startsAsked(),
          2,
          reason: 'the refusal arrived after the grant, and still owes a retry',
        );
        await call.hangUp();
      },
    );

    test('a refusal landing on a retry already in flight adds nothing', () async {
      // The refusal callback describes the ENTRY start, and it can arrive while
      // the grant's own retry is still in the platform's hands. Both would then
      // be answering the same debt, and the call would have two starts out at
      // once for one permission that was granted once.
      final (call, calls, fgs, media) = await withForeground(
        startReturns: false,
      );
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      final connecting = Completer<void>();
      media.beforeConnect = connecting.future;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(startsAsked(), 1, reason: 'the entry attempt, already refused');

      // The grant lands and its retry is left with the platform, unanswered.
      fgs.holdStart = Completer<void>();
      connecting.complete();
      await starting;
      expect(startsAsked(), 2, reason: 'the grant paid for the retry');

      call.foregroundRefused();
      await pumpEventQueue();
      fgs.holdStart!.complete();
      await pumpEventQueue();

      expect(
        startsAsked(),
        2,
        reason: 'the debt was already being paid when the refusal arrived',
      );
      await call.hangUp();
    });

    test('a call that is ending is not worth a retry', () async {
      // The grant lands inside connect, and a hangup lands there routinely. A
      // service started for a call already coming down is one nothing is left
      // to stop -- the late-start reconcile would take it back off the platform
      // again, and troubling the platform at all is the thing to skip.
      final (call, calls, _, media) = await withForeground(startReturns: false);
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      final connecting = Completer<void>();
      media.beforeConnect = connecting.future;

      final starting = call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      await call.hangUp();
      connecting.complete();
      await starting;
      await pumpEventQueue();

      expect(
        startsAsked(),
        1,
        reason: 'the grant arrived for a call that no longer wanted it',
      );
      expect(
        trace.steps,
        isNot(contains(startsWith('fgs.stop'))),
        reason: 'and nothing was started for teardown to take back',
      );
    });

    test('a start the account will refuse never touches the service', () async {
      // The service is the LIVE call's; a second start is about to be
      // refused with AlreadyInACall, and firing the service first would
      // overwrite the standing call's notification with this one's name.
      final (call, calls, _, _) = await withForeground();
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
      expect(trace.steps, isNot(contains(startsWith('fgs.stop'))));
    });

    test('a call started with video escalates the service type', () async {
      final (call, calls, _, _) = await withForeground();
      calls.devicesInCall = [calls.client.deviceID!];
      calls.remotePresent = true;
      await call.start(roomStub(calls.client), video: true);
      expect(
        trace.steps,
        contains(startsWith('fgs.camera(true')),
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
      expect(trace.steps, isNot(contains('ring')), reason: 'never rings');
      // It DOES announce. Announcing is how the returning process enters the
      // RTC session, which owns the membership refresh and the delayed leave;
      // without it the dead process's delayed leave still fires and the other
      // side hangs up on a call that is live. What makes it a rejoin rather
      // than a new call is that it does not ring and did not place anything.
      expect(trace.steps, contains('announce'));
      expect(call.placedCall, isFalse);
      // The call keeps the IDENTITY it already had -- the membership written
      // when it was first joined -- while the membership that is live is the
      // fresh one, because that is the one whose refresh and delayed leave
      // the returning process owns. Conflating the two either splits one call
      // into two records or leaves nobody renewing the membership.
      expect(call.callAnchorId, r'$original-membership');
      expect(call.membershipEventId, r'$membership');
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
      expect(
        trace.steps,
        isNot(contains('ring')),
        reason: 'the empty roster must not turn a rejoin into a new call',
      );
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

    /// A device the SDK cannot name, which is a logout landing mid-call.
    ///
    /// The election breaks its tie on device id, and the empty string this used
    /// to substitute for a missing one sorts BEFORE every real id — so such a
    /// device elected ITSELF over every sibling, unconditionally, and both went
    /// on to deliver the same stretch. Duplicate analytics is the one outcome
    /// the election exists to prevent.
    test('a device with no id stands aside rather than winning', () async {
      final (call, calls, _, _) = await build();
      final myDeviceId = calls.client.deviceID!;
      calls.remotePresent = true;
      calls.devicesInCall = [myDeviceId];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);
      trace.steps.clear();

      (calls.client as ForgetfulClient).forgotDevice = true;
      // A sibling this device BEAT while it still had a name, so the outcome
      // here can only have come from the missing id.
      await calls.participantsBecome(['zzzzzzzzzz']);

      expect(call.isRecording, isFalse);
      expect(
        trace.steps,
        contains('capture.stop'),
        reason: 'and what it already holds is flushed, not dropped',
      );
    });

    test('a device with no id still records when it is alone', () async {
      // Standing aside is for somebody. Alone there is nobody to produce a
      // duplicate with, and refusing would cost the call's analytics to
      // prevent nothing.
      final (call, calls, _, _) = await build();
      final myDeviceId = calls.client.deviceID!;
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', myDeviceId];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse, reason: 'the other device sorts lower');

      (calls.client as ForgetfulClient).forgotDevice = true;
      await calls.participantsBecome([]);

      expect(call.isRecording, isTrue);
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

  group('a device that cannot record says so', () {
    /// A call with somebody on it, this device recording, and one sibling
    /// sorting ABOVE this device -- so device id alone would never displace it
    /// and anything that does is capability.
    Future<(ActiveCall, FakeCalls, FakeCapture)>
    recordingBesideAHigherSibling() async {
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue, reason: 'the premise of these tests');
      trace.steps.clear();
      return (call, calls, capture);
    }

    test('a device with nothing published tells its siblings', () async {
      // A trackless device used to leave the election before ranking, so it
      // published nothing and every sibling went on deferring to it on device
      // id -- and NOBODY recorded the call.
      final (call, calls, _, _) = await build(hasTrack: false);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];

      await call.start(roomStub(calls.client), video: false);

      expect(call.isRecording, isFalse, reason: 'nothing to record from');
      expect(calls.roster!.announced, contains(false));
    });

    test('a device whose tap is gone tells its siblings', () async {
      // Every reason a device cannot record reaches BOTH the ranking and the
      // announcement through one expression, so there is no way to stand aside
      // quietly -- which is the state in which every sibling defers to a device
      // that is recording nothing.
      final (_, calls, capture) = await recordingBesideAHigherSibling();

      capture.loseTapForGood();
      await pumpEventQueue();

      expect(calls.roster!.announced, contains(false));
    });

    test('it does not stand aside until that has landed', () async {
      // The pessimistic local answer must never run ahead of what the siblings
      // can see. A device that flipped to "cannot" while the write was stalled
      // would tie every sibling on capability and lose the device-id tiebreak
      // to itself: nobody records at all, for as long as the signal is stuck.
      final (call, calls, capture) = await recordingBesideAHigherSibling();
      calls.roster!.holdAnnounce = Completer<void>();

      capture.loseTapForGood();
      await pumpEventQueue();

      expect(
        trace.steps,
        contains('capture.start'),
        reason: 'it keeps trying while its siblings still read it as able',
      );
      expect(call.isRecording, isFalse, reason: 'and honestly reports failure');
      calls.roster!.holdAnnounce!.complete();
    });

    test('and once it has landed, the capable sibling takes over', () async {
      // The point of the whole ranking. Without it the device that just failed
      // wins the election again on device id, attaches the same tap for the
      // same reason, and the call goes untranscribed while a working sibling
      // sits second in line.
      final (call, calls, capture) = await recordingBesideAHigherSibling();
      // Published for real. Left to the roster's silence-means-able default the
      // check at the end would be reading the fixture back out of itself, and
      // no change to how a sibling's capability is parsed or ranked could move
      // it.
      calls.roster!.attributes = {
        '${calls.client.userID}:zzzzzzzzzz': {
          CallRoster.canCaptureAttribute: 'yes',
        },
      };
      calls.roster!.recompute();

      capture.loseTapForGood();
      await pumpEventQueue();
      // The announcement has landed by here, and this device has already had
      // its one optimistic restart while its siblings still read it as able.
      trace.steps.clear();
      await call.tickReelectionForTest();

      expect(
        trace.steps,
        isNot(contains('capture.start')),
        reason: 'it stopped handing itself a recording it cannot perform',
      );
      expect(call.isRecording, isFalse);
      expect(
        calls.roster!.siblingCanCapture('zzzzzzzzzz'),
        isTrue,
        reason: 'and it stood aside for a sibling that says it can',
      );
    });

    test('and it does not take the recording back until that has', () async {
      // The other direction, and the one that costs the learner. A device whose
      // microphone came back ranks itself able the instant it finds out --
      // while every sibling still reads the "cannot" it published, and one of
      // them is recording precisely because of it. Both are then elected in
      // their own view, so both capture the same seconds and NEITHER discards:
      // the convergence duplicate this whole feature exists to remove, in a
      // window the discard does not cover.
      final (call, calls, capture) = await recordingBesideAHigherSibling();
      capture.loseTapForGood();
      await pumpEventQueue();
      await call.tickReelectionForTest();
      expect(call.isRecording, isFalse, reason: 'the premise: it stood aside');

      // The microphone comes back while the "yes" is still on the wire.
      calls.roster!.holdAnnounce = Completer<void>();
      capture.tapWorks = true;
      trace.steps.clear();
      await call.tickReelectionForTest();

      expect(
        trace.steps,
        isNot(contains('capture.start')),
        reason: 'its siblings still read it as unable, and one is recording',
      );
      expect(call.isRecording, isFalse);
      calls.roster!.holdAnnounce!.complete();
    });

    test('a microphone acquired after connect re-enters the election', () async {
      // An unmute republishes the audio track, so a device that connected
      // before its microphone was up has one only later. Read once at connect,
      // it stayed trackless -- and silent -- for the whole call.
      final (call, calls, media, capture) = await build(hasTrack: false);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse, reason: 'nothing to record from yet');
      trace.steps.clear();

      media.hasTrack = true;
      await call.tickReelectionForTest();

      expect(trace.steps, contains('capture.start'));
      expect(call.isRecording, isTrue);
      expect(capture.discardRequests.last, isFalse);
    });
  });

  group('two devices that answered the same ring at once', () {
    // Whole seconds, because that is all the SFU's stamp ever carries.
    final joinedAt = DateTime.utc(2026, 8, 29, 12, 0, 30);
    final aSecondEarlier = joinedAt.subtract(const Duration(seconds: 1));

    /// A sibling naming an uninterrupted run of captured audio.
    Map<String, String> recording(String run, {bool alsoAble = true}) => {
      if (alsoAble) CallRoster.canCaptureAttribute: 'yes',
      CallRoster.capturingAttribute: CaptureReport.published(run),
    };

    /// A sibling that has SAID it is not recording, which is a different thing
    /// from one that has said nothing.
    Map<String, String> idle() => {
      CallRoster.capturingAttribute: CaptureReport.published(null),
    };

    test('a successor only seen AFTER we started keeps our tail', () async {
      // It joined a whole resolution step earlier and it names a run, so both
      // of the readings taken at the handover say discard. But this device was
      // recording before it could see the sibling at all, and nothing it
      // observed says what the sibling was doing then -- the run token proves
      // continuity forward from the moment it was first seen and no further
      // back. An earlier join stamp does not fill that in: it says the sibling
      // was in the ROOM first, and a device can sit in a call for a long time
      // before its first frame arrives.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (true, aSecondEarlier),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': recording('7'),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      expect(call.isRecording, isFalse, reason: 'displaced all the same');
      expect(capture.discardRequests.last, isFalse);
    });

    test('a successor that only says it CAN record keeps our tail', () async {
      // Its join time and its device id both say discard, and it advertises
      // that it can record -- but capability is TRUE FOR SILENCE, so a device
      // whose tap attached and then produced nothing goes on saying it for the
      // fifteen seconds its own watchdog takes to fire. Reading that as "it
      // recorded" throws away the only copy of what the learner said, on
      // exactly the failure the watchdog exists to detect.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (true, aSecondEarlier),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': {
          CallRoster.canCaptureAttribute: 'yes',
        },
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      expect(call.isRecording, isFalse, reason: 'displaced all the same');
      expect(capture.discardRequests.last, isFalse);
    });

    /// This device recording beside a sibling that joined much earlier and
    /// sorts AFTER it on device id, so this device wins the election and the
    /// sibling only takes over once this one loses its tap. The sibling's
    /// opening statement is the variable each of the next three tests changes.
    Future<(ActiveCall, FakeCalls, FakeCapture)> recordingBeside(
      Map<String, String> saying, {
      void Function(FakeCalls calls)? afterFirstFrame,
    }) async {
      final (call, calls, _, capture) = await build();
      if (afterFirstFrame != null) {
        capture.afterFirstFrame = () => afterFirstFrame(calls);
      }
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:zzzzzzzzzz': (
          true,
          joinedAt.subtract(const Duration(seconds: 20)),
        ),
      };
      calls.roster!.attributes = {'${calls.client.userID}:zzzzzzzzzz': saying};
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue, reason: 'the premise of these tests');
      return (call, calls, capture);
    }

    /// The sibling ends up recording run 7 and this device hands over to it.
    Future<void> handOverTo(
      ActiveCall call,
      FakeCalls calls,
      FakeCapture capture,
    ) async {
      calls.roster!.attributes = {
        '${calls.client.userID}:zzzzzzzzzz': recording('7'),
      };
      calls.roster!.recompute();
      await pumpEventQueue();
      capture.loseTapForGood();
      await pumpEventQueue();
      await call.tickReelectionForTest();
      expect(call.isRecording, isFalse, reason: 'the sibling has it now');
    }

    test(
      'a successor that goes quiet mid-stretch still takes our tail',
      () async {
        // Silence is not a denial. The sibling was already recording run 7 when
        // this stretch opened; a dropped attribute update, or a write that failed
        // and has not been re-asserted, leaves us hearing nothing from it for a
        // while. Reading that as "it stopped" and remembering it keeps a
        // duplicate of a stretch the sibling really holds.
        final (call, calls, capture) = await recordingBeside(recording('7'));

        calls.roster!.attributes = {
          '${calls.client.userID}:zzzzzzzzzz': const {},
        };
        calls.roster!.recompute();
        await pumpEventQueue();

        await handOverTo(call, calls, capture);

        expect(capture.discardRequests.last, isTrue);
      },
    );

    test('the ledger opens at our first frame, not at a later election', () async {
      // The gap between the two is up to a whole presence tick, and a sibling
      // that changed what it was doing inside it would be judged on the later
      // reading as though it were the opening one. Here the sibling was in run
      // 7 when this stretch opened and has moved to run 8 by the time the next
      // election looks -- a stop and a restart, with a hole in the middle that
      // only the opening reading can reveal.
      final (call, calls, capture) = await recordingBeside(
        recording('7'),
        // It stops and restarts INSIDE that window. Only a reading taken at our
        // own first frame catches run 7; every later one sees run 8 alone, and
        // reads a sibling that has already broken as one that never did.
        afterFirstFrame: (calls) {
          calls.roster!.attributes = {
            '${calls.client.userID}:zzzzzzzzzz': recording('8'),
          };
          calls.roster!.recompute();
        },
      );

      capture.loseTapForGood();
      await pumpEventQueue();
      await call.tickReelectionForTest();

      expect(call.isRecording, isFalse, reason: 'the sibling has it now');
      expect(capture.discardRequests.last, isFalse);
    });

    test('a successor first heard from mid-stretch keeps our tail', () async {
      // The same observation sequence as the test above with the OPPOSITE truth
      // underneath it, and this device cannot tell them apart: the sibling was
      // silent when we opened because its `no` was in flight, or was overwritten
      // by its own run before we ever read it, and its first frame came after
      // ours. It holds the second half of this stretch and not the first. Since
      // the two are indistinguishable, the tie goes to keeping the audio -- a
      // duplicate is a wrong number, a discard is a thing the learner said that
      // nothing anywhere still holds.
      final (call, calls, capture) = await recordingBeside(const {});

      await handOverTo(call, calls, capture);

      expect(capture.discardRequests.last, isFalse);
    });

    test('a successor that SAID it was idle stays disqualified', () async {
      // The other side of the same coin, and why devices publish "no" at all.
      // A sibling that TOLD us it was not recording while our stretch ran holds
      // none of what came before it took over -- and unlike silence, that is a
      // sentence it actually said. Without the explicit denial this case is
      // indistinguishable from the one above, and one of the two has to be
      // wrong.
      final (call, calls, capture) = await recordingBeside(idle());

      await handOverTo(call, calls, capture);

      expect(capture.discardRequests.last, isFalse);
    });

    test(
      'a successor recording the same run throughout takes our tail',
      () async {
        // The shape that proves a duplicate, and the only one that can. This
        // device WATCHED the sibling recording run 7 from its own first frame
        // through to the handover, so every second it is about to destroy is a
        // second the sibling was holding. Delivering it would credit the learner
        // twice for saying something once, because the sink keys a result by
        // capture session and two devices are two sessions.
        final (call, calls, capture) = await recordingBeside(recording('7'));

        await handOverTo(call, calls, capture);

        expect(capture.discardRequests.last, isTrue);
      },
    );

    test('a successor whose run changed mid-stretch keeps our tail', () async {
      // A sibling that stopped and started again holds a stretch with a hole in
      // it. Attribute writes are last-write-wins, so the `no` in between can
      // never reach us and both readings say "recording" -- the run token
      // changing is the ONLY evidence the gap happened. Without it this tail is
      // dropped and the seconds in the gap belong to nobody.
      final (call, calls, capture) = await recordingBeside(recording('6'));

      await handOverTo(call, calls, capture);

      expect(capture.discardRequests.last, isFalse);
    });

    test('two devices that joined in the same second keep their tails', () async {
      // The stamp is derived from a whole-second field, so a device that joined
      // at 12:00:30.001 and one that joined at 12:00:30.900 read as EQUAL --
      // and the earlier one, discarding on that equality, destroys nine hundred
      // milliseconds the other was never in the room for. The successor IS
      // recording here, which is the point: the join stamps are what refuse.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (true, joinedAt),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': recording('7'),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      expect(call.isRecording, isFalse);
      expect(capture.discardRequests.last, isFalse);
    });

    test('the request is in before the reconcile that stops the tap', () async {
      // Teardown stops the recorder DIRECTLY, outside the serialised handover
      // chain, so its stop can reach the flush while this election's reconcile
      // is still queued. A request made inside the reconcile would arrive after
      // the audio had already gone -- whatever its value would have been.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (true, aSecondEarlier),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': recording('7'),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      trace.steps.clear();
      final before = capture.discardRequests.length;
      // Deliberately NOT pumped: the roster notifies synchronously, so this is
      // the instant after the election decided and before anything it queued
      // has run.
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];

      expect(
        trace.steps,
        isNot(contains('capture.stop')),
        reason: 'the reconcile has not run yet',
      );
      expect(
        capture.discardRequests.length,
        greaterThan(before),
        reason: 'and the election has already stated the tail is fate',
      );
    });

    test('a successor that arrived later keeps our tail', () async {
      // It was not in the call while we were recording, so nobody else holds
      // those words and discarding them destroys the only copy. It IS recording
      // now, which is the point: the join times are what refuse.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (
          true,
          joinedAt.add(const Duration(seconds: 20)),
        ),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': recording('7'),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await calls.participantsBecome(['AAAAAAAAAA', calls.client.deviceID!]);

      expect(call.isRecording, isFalse, reason: 'displaced all the same');
      expect(capture.discardRequests.last, isFalse);
    });

    test('a stop that is not a handover still delivers its tail', () async {
      // The peer leaving, a grace lapsing, a hangup -- none of them mean
      // another device recorded this stretch. Without the election gate a
      // higher-sorting sibling that merely joined earlier would silently drop
      // audio nobody else has.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:zzzzzzzzzz': (
          true,
          joinedAt.subtract(const Duration(seconds: 20)),
        ),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:zzzzzzzzzz': recording('7'),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue, reason: 'it out-ranks the higher id');

      // They leave. This device is still the elected recorder; it simply has
      // nobody left to record a conversation with.
      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!, 'zzzzzzzzzz']);

      expect(call.isRecording, isFalse);
      expect(capture.discardRequests.last, isFalse);
    });

    test('two devices that both gave up keep their tails', () async {
      // The successor joined first and takes the recording on device id, but a
      // device that says it CANNOT record is certainly not one naming a run --
      // and whichever of two such devices the id hands the call to is recording
      // nothing. Dropping this tail destroys the only copy.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:AAAAAAAAAA': (true, aSecondEarlier),
      };
      calls.roster!.attributes = {
        '${calls.client.userID}:AAAAAAAAAA': {
          CallRoster.canCaptureAttribute: 'no',
        },
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'AAAAAAAAAA'];
      await call.start(roomStub(calls.client), video: false);
      expect(
        call.isRecording,
        isTrue,
        reason: 'able out-ranks a lower id that says it cannot',
      );

      capture.loseTapForGood();
      await pumpEventQueue();
      await call.tickReelectionForTest();

      expect(call.isRecording, isFalse, reason: 'the lower id has it now');
      expect(capture.discardRequests.last, isFalse);
    });

    test('a handover forced by capability keeps our tail', () async {
      // This device loses its tap and a sibling that has been idle all call
      // takes over. Whatever its join time says, it was not recording while the
      // learner was speaking here, and it has never said it was.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:zzzzzzzzzz': (
          true,
          joinedAt.subtract(const Duration(seconds: 20)),
        ),
      };
      calls.roster!.attributes = {'${calls.client.userID}:zzzzzzzzzz': idle()};
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue);

      capture.loseTapForGood();
      await pumpEventQueue();
      await call.tickReelectionForTest();

      expect(call.isRecording, isFalse);
      expect(capture.discardRequests.last, isFalse);
    });
  });

  group('what the roster is told about the token', () {
    // The roster is built from the media, which only dials with the token; the
    // token itself is the call's. Without carrying it across, a write the SFU
    // REFUSED and an SFU that stopped answering arrive at the roster's report
    // as the same thrown error — and only one of them is a deployment we have
    // to change. That indistinguishability is why the refusal read as an
    // ordinary flake for the life of the feature.
    test('carries a grant that cannot publish attributes', () async {
      final (call, calls, media, _) = await build();
      calls.grant = CallToken(
        url: 'ws://sfu',
        jwt: jwtWith({
          'video': {'roomJoin': true, 'canPublish': true},
        }),
      );

      await call.start(roomStub(calls.client), video: false);

      expect(media.rosterGrant, MetadataGrant.absent);
    });

    test('and one that can', () async {
      final (call, calls, media, _) = await build();
      calls.grant = CallToken(
        url: 'ws://sfu',
        jwt: jwtWith({
          'video': {'roomJoin': true, 'canUpdateOwnMetadata': true},
        }),
      );

      await call.start(roomStub(calls.client), video: false);

      expect(media.rosterGrant, MetadataGrant.granted);
    });
  });

  group('telling the other devices what this one is doing', () {
    final joinedAt = DateTime.utc(2026, 8, 29, 12, 0, 30);

    test('an idle device says so rather than staying silent', () async {
      // Silence means nothing to a reader, so a device that is not recording
      // has to SAY it. Without this a sibling cannot tell an idle device from
      // one it has not heard from, and the two want opposite answers.
      final (call, calls, _, _) = await build(hasTrack: false);
      calls.roster!.myJoin = (true, joinedAt);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      expect(call.isRecording, isFalse);
      expect(calls.roster!.announcedCapturing, contains(null));
      expect(calls.roster!.announcedCapturing, isNot(contains(isNotNull)));
    });

    test('a recording device names its run', () async {
      final (call, calls, _, _) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();

      expect(call.isRecording, isTrue);
      expect(calls.roster!.announcedCapturing.last, isNotNull);
    });

    test('the retraction goes out on the DECISION, not on the stop', () async {
      // Every reading a sibling takes is of a snapshot published some
      // unknowable time earlier, so a "no" that waits for the audio to stop is
      // already too late: the sibling can still be reading the run while this
      // device's tail is being flushed, and destroy its own copy on it.
      //
      // THE ELECTION HERE SETTLES TWO FACTS AT ONCE, which is the case that
      // caught it out. This device loses its tap and is displaced in the same
      // pass, so the capability write and the retraction are decided together.
      // Composed one at a time, the retraction goes out behind a whole signal
      // round trip -- and lands after the audio it describes has stopped.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:zzzzzzzzzz': (
          true,
          joinedAt.subtract(const Duration(seconds: 20)),
        ),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(call.isRecording, isTrue);
      trace.steps.clear();
      calls.roster!.traceWrites = true;

      capture.tapWorks = false;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await pumpEventQueue();

      expect(
        trace.steps.indexOf('publish(not recording)'),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(trace.steps.indexOf('capture.stop')),
        ),
        reason: 'the siblings hear it before the audio stops, not after',
      );
    });

    test('the audio waits for a retraction stuck behind another write', () async {
      // THE CASE A HEAD START DOES NOT COVER. The announcer serialises, so when
      // an earlier election's capability write is still in flight the
      // retraction is only STORED -- no write starts -- and the reconcile can
      // stop the audio before the "no" ever reaches the wire. In that window a
      // sibling reads a run this device no longer holds and destroys its own
      // tail for it.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.roster!.joins = {
        '${calls.client.userID}:zzzzzzzzzz': (
          true,
          joinedAt.subtract(const Duration(seconds: 20)),
        ),
      };
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(call.isRecording, isTrue);
      trace.steps.clear();
      calls.roster!.traceWrites = true;

      // An earlier turn's capability write goes out and stays in flight.
      final held = Completer<void>();
      calls.roster!.holdAnnounce = held;
      capture.tapWorks = false;
      await call.tickReelectionForTest();
      calls.roster!.holdAnnounce = null;

      // Now, in a later turn, this device is displaced and must stop.
      calls.devicesInCall = [
        'AAAAAAAAAA',
        calls.client.deviceID!,
        'zzzzzzzzzz',
      ];
      await pumpEventQueue();

      expect(
        trace.steps,
        isNot(contains('capture.stop')),
        reason: 'the siblings have not been told yet',
      );

      held.complete();
      await pumpEventQueue();

      expect(
        trace.steps.indexOf('publish(not recording)'),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(trace.steps.indexOf('capture.stop')),
        ),
        reason: 'and the audio stopped only once they had been',
      );
    });

    test(
      'a stop parked on its retraction obeys the election that reversed it',
      () async {
        // The wait for the retraction is a signal round trip, and elections are
        // synchronous listeners on the roster -- they are not serialised behind
        // the handover chain the way reconciles are. So one can run start to
        // finish while the reconcile is parked, put this device back in charge,
        // and tell the siblings it is still recording. A reconcile that resumed
        // and stopped anyway would stop a recorder the latest election wants
        // running, and the run it just republished would be one nobody holds.
        final (call, calls, _, capture) = await build();
        calls.roster!.myJoin = (true, joinedAt);
        calls.roster!.joins = {
          '${calls.client.userID}:zzzzzzzzzz': (
            true,
            joinedAt.subtract(const Duration(seconds: 20)),
          ),
        };
        calls.remotePresent = true;
        calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
        await call.start(roomStub(calls.client), video: false);
        await pumpEventQueue();
        expect(call.isRecording, isTrue);
        final run = capture.captureRun;
        trace.steps.clear();

        // Displaced. The reconcile parks on a retraction that cannot land yet.
        final held = Completer<void>();
        calls.roster!.holdAnnounce = held;
        calls.devicesInCall = [
          'AAAAAAAAAA',
          calls.client.deviceID!,
          'zzzzzzzzzz',
        ];
        await pumpEventQueue();
        expect(
          trace.steps,
          isNot(contains('capture.stop')),
          reason: 'the premise: it is waiting on the retraction',
        );

        // And put straight back in charge while it waits.
        calls.roster!.holdAnnounce = null;
        calls.devicesInCall = [calls.client.deviceID!, 'zzzzzzzzzz'];
        held.complete();
        await pumpEventQueue();

        expect(
          trace.steps,
          isNot(contains('capture.stop')),
          reason: 'the decision it was carrying out had been reversed',
        );
        expect(call.isRecording, isTrue);
        expect(
          capture.captureRun,
          run,
          reason: 'and the audio was never interrupted, so the run stands',
        );
      },
    );

    test('a device alone does not hold its stop open for nobody', () async {
      // The wait is for the benefit of a sibling that could act on the stale
      // claim. With no sibling in the call there is nobody to mislead, and
      // holding the microphone open for a signal round trip would keep
      // recording audio after this device was told to stop -- which is the very
      // thing the stop was ordered for.
      final (call, calls, _, capture) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(call.isRecording, isTrue);
      trace.steps.clear();

      // Nothing this device announces can land from here on.
      calls.roster!.holdAnnounce = Completer<void>();
      calls.remotePresent = false;
      await calls.participantsBecome([calls.client.deviceID!]);

      expect(trace.steps, contains('capture.stop'));
      expect(call.isRecording, isFalse);
      calls.roster!.holdAnnounce!.complete();
    });

    test('a mute retracts the run at once', () async {
      // A mute is a gap in what this device holds. A sibling still reading the
      // run through it would drop its own tail believing this device had the
      // words spoken during the mute.
      final (call, calls, _, _) = await build();
      calls.roster!.myJoin = (true, joinedAt);
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      await pumpEventQueue();
      expect(calls.roster!.announcedCapturing.last, isNotNull);

      call.setMuted(true);
      await pumpEventQueue();

      expect(calls.roster!.announcedCapturing.last, isNull);
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

  group('a recording whose tap dies mid-call', () {
    /// A call with somebody on it and this device recording. Nothing is
    /// captured while a call is still ringing, so the peer has to be here.
    Future<(ActiveCall, FakeCalls, FakeCapture)> recording() async {
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      calls.devicesInCall = [calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isTrue, reason: 'the premise of these tests');
      trace.steps.clear();
      return (call, calls, capture);
    }

    test('is re-attached at once when the recorder says so', () async {
      // A stop the recorder performed by itself leaves this side's record of
      // "I am recording" describing a recording that no longer exists, and
      // that record is what every later election short-circuits on. Detecting
      // the death and then swallowing it one layer up is the worse failure of
      // the two: the device goes on out-ranking its siblings for the rest of
      // the call while recording nothing.
      final (call, _, capture) = await recording();

      capture.loseTap();
      await pumpEventQueue();

      expect(
        trace.steps.where((s) => s == 'capture.start'),
        hasLength(1),
        reason: 'the death re-enters the election rather than ending recording',
      );
      expect(call.isRecording, isTrue);
    });

    test('is recovered by the presence clock even if nobody says so', () async {
      // The floor under the wiring above. An election that short-circuits on
      // its own cached answer can never notice a recording that stopped
      // without it; one that asks the recorder recovers the call on the next
      // tick however the capture was lost, including in ways nothing here is
      // wired to hear.
      final (call, _, capture) = await recording();

      capture.loseTapUnannounced();
      await call.tickReelectionForTest();

      expect(trace.steps.where((s) => s == 'capture.start'), hasLength(1));
      expect(call.isRecording, isTrue);
    });

    test('a repeated election over a live recording changes nothing', () async {
      // The counterweight. Asking the recorder rather than the cache must not
      // turn every election into a restart -- the check is only there to catch
      // a recording that has actually gone.
      final (call, _, _) = await recording();

      await call.tickReelectionForTest();
      await call.tickReelectionForTest();

      expect(
        trace.steps.where((s) => s.startsWith('capture.')),
        isEmpty,
        reason: 'a live recording is already what was wanted',
      );
    });

    test('the cleared record is what makes the restart stick', () async {
      // The restart above can rescue a record nobody cleared -- it reaches the
      // recorder either way, because the recorder answers that it is not
      // recording -- so it cannot show whether the record was cleared at all.
      // Here the recorder refuses to attach, and this side's own record is the
      // only thing left describing the call. Left saying "recording", it says
      // so for the rest of the call over a tap that is gone.
      final (call, _, capture) = await recording();
      capture.startError = StateError('the tap will not attach');

      capture.loseTap();
      await pumpEventQueue();

      expect(
        call.isRecording,
        isFalse,
        reason: 'a recording that ended is not still described as running',
      );
    });

    test('a device that is not the recorder is left alone', () async {
      // The other half of the truth-reading guard: the recorder is only ever
      // consulted about a recording that is WANTED. Nothing starts a recording
      // behind this method's back, so on a device that is deferring there is no
      // lie to catch -- and consulting it anyway turns every presence tick into
      // a stop against a recorder that is not recording, plus its log line,
      // every two seconds for the whole call.
      final (call, calls, _, capture) = await build();
      calls.remotePresent = true;
      calls.devicesInCall = ['AAAAAAAAAA', calls.client.deviceID!];
      await call.start(roomStub(calls.client), video: false);
      expect(call.isRecording, isFalse, reason: 'the premise of this test');
      capture.stopSettledDeliveries.clear();

      await call.tickReelectionForTest();
      await call.tickReelectionForTest();

      expect(
        capture.stopSettledDeliveries,
        isEmpty,
        reason: 'deferring is not something to keep telling the recorder',
      );
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
