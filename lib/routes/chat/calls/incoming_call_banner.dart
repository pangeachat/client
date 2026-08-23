import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart' as matrix show Event, Logs, Room, User;

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_breadcrumb.dart';
import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_quick_replies.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/ring_player.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Announces a call arriving for this account, wherever the learner happens to
/// be in the app.
///
/// Wraps the app rather than living on the chat screen: a call is worth
/// interrupting whatever someone is doing, and a learner reading a different
/// conversation would otherwise never know they were being called.
class IncomingCallBanner extends StatefulWidget {
  /// Nullable because the router supplies it, and it is null before the first
  /// route resolves.
  final Widget? child;

  /// Tests hand in a player with a fake sound; the app builds the real one.
  final RingPlayer? ringPlayerOverride;

  const IncomingCallBanner({
    required this.child,
    this.ringPlayerOverride,
    super.key,
  });

  @override
  State<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<IncomingCallBanner> {
  /// The one hand that touches the ring sound. Injected in tests.
  late final RingPlayer _ringPlayer = widget.ringPlayerOverride ?? RingPlayer();

  StreamSubscription<IncomingCallNotification>? _rings;
  StreamSubscription<matrix.Event>? _ownDeclines;
  StreamSubscription<void>? _callerGone;
  CallService? _service;
  Timer? _stillRinging;
  IncomingCallNotification? _ringing;

  /// A call this device was on before a reload, offered back to the learner.
  ///
  /// Held on [MatrixState] rather than here: this State can be re-created
  /// around the app (locale, lock, theme rebuilds), and widget-local offer
  /// state died invisible in a detached instance while another rendered.
  ValueNotifier<RejoinOffer?>? _rejoinStore;

  RejoinOffer? get _rejoin => _rejoinStore?.value;
  set _rejoin(RejoinOffer? value) => _rejoinStore?.value = value;

  /// Watched so a call starting ANYWHERE clears the rejoin offer: the join
  /// claim is one-per-account, so whatever started owns it now.
  ValueNotifier<Object?>? _activeCall;

  String? _listeningTo;

  /// The ONLY assignment to [_ringing], so the ring sound can never disagree
  /// with the prompt on screen: the loop starts when a ring shows, restarts
  /// when a redial replaces it, and stops on EVERY way a prompt goes --
  /// dismissal, decline, answer, lifetime, caller-gone, account switch, and
  /// a rejoin offer taking the same room. A test greps this file for direct
  /// assignments; this setter must stay the only one.
  void _showRing(IncomingCallNotification? ring) {
    final previous = _ringing;
    _ringing = ring;
    if (ring != null) {
      _ringPlayer.play(ring.event.eventId);
    } else if (previous != null) {
      _ringPlayer.stop(previous.event.eventId);
    }
  }

  /// Notification event ids the learner has turned down.
  ///
  /// Keyed by the notification event, which is unique per call — so a decline
  /// holds for exactly the call it declined, and the next call from the same
  /// person (a different notification) rings normally.
  final Set<String> _declined = {};

  @override
  void initState() {
    super.initState();
    // Deferred: Matrix.of needs a mounted context, and the call service is
    // per-account and resolved from it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The active account can change under this widget. Without re-subscribing,
    // the banner would keep listening to the account active when it mounted and
    // never ring for the one the learner switched to.
    _listen();
  }

  void _listen() {
    if (!mounted) return;
    final matrixState = Matrix.of(context);
    final account = matrixState.client.clientName;
    if (account == _listeningTo) return;

    _rings?.cancel();
    _ownDeclines?.cancel();
    _callerGone?.cancel();
    _listeningTo = account;
    _service = matrixState.callService;
    // A prompt belonging to the account we just left is not this one's.
    if (_ringing != null) setState(() => _showRing(null));
    // Both prompts belonged to the account we just left: a Return offer
    // surviving the switch would rejoin the OLD account's call over the new
    // account's connection.
    _clearOffer();
    _ringPlayer.stopAll();

    _rings = matrixState.callService.incomingRings.listen(
      (ring) => _offer(ring, account),
    );

    // Answering on one phone has to stop the others ringing. The decline this
    // account sends carries the ring it refers to, so a device showing that ring
    // can put its own prompt away — otherwise it goes on offering to answer a
    // call the caller is already tearing down.
    _ownDeclines = matrixState.callService.ownDeclines().listen((event) {
      if (!mounted) return;
      final target = matrixState.callService.declineTarget(event);
      if (target == null) return;
      // Remembered as well as dismissed, so a ring still working its way
      // through the timeline cannot put the prompt back up.
      _declined.add(target);
      if (_ringing?.event.eventId == target) _dismiss();
    });

    // A ring that landed before a reload is not on the live stream any more.
    // Without this, refreshing the page while the phone was ringing lost the
    // call outright, with no way left to answer it.
    unawaited(_replayMissed(matrixState, account));

    // And a call this DEVICE was on when the reload happened is offered back.
    _activeCall?.removeListener(_onActiveCallChanged);
    _activeCall = matrixState.activeCall;
    _activeCall?.addListener(_onActiveCallChanged);
    _rejoinStore = matrixState.rejoinOffer;
    unawaited(_offerRejoin(matrixState, account));
  }

  /// A call starting anywhere in the app takes the one join claim this account
  /// has, so a standing rejoin offer is for a call that can no longer be
  /// rejoined first — it goes.
  void _onActiveCallChanged() {
    if (_activeCall?.value == null || _rejoin == null) return;
    _clearOffer();
  }

  /// Offers a return to the call a reload interrupted.
  ///
  /// The membership is only the OFFER: whether the call still exists is
  /// decided by the join itself, which waits briefly for the peer and leaves
  /// quietly if the room is empty. Never auto-joined — a microphone opens on a
  /// tap or not at all.
  Future<void> _offerRejoin(MatrixState matrixState, String account) async {
    final service = matrixState.callService;
    matrix.Logs().i('Rejoin offer scan starting');
    // An active session suppresses the offer outright: the learner is already
    // in whatever call matters most.
    if (service.isBusy) {
      matrix.Logs().i('Rejoin offer scan: account already busy');
      return;
    }
    final List<RejoinOffer> offers;
    try {
      offers = await service.rejoinOffers();
    } catch (e, s) {
      matrix.Logs().w('Could not look for a call to return to', e, s);
      return;
    }
    matrix.Logs().i(
      'Rejoin offer scan: ${offers.length} offer(s); '
      'mounted=$mounted stillThisAccount=${_listeningTo == account}',
    );
    if (!mounted || _listeningTo != account) return;
    // Re-checked: the scan awaited network, and a call may have started since.
    if (service.isBusy || offers.isEmpty) return;
    final offer = offers.first;
    final showing = _ringing;
    if (showing != null && showing.event.room.id == offer.room.id) {
      // The same-room rule again, from the other side: a ring that names the
      // caller's CURRENT membership is a live call and keeps the screen; the
      // offer for that room is dead and is not shown. Only a STALE ring --
      // the replay of this account's own call's past -- gives way.
      if (_ringIsLive(showing, offer)) return;
      // The full dismissal, not only the prompt: the ring being replaced has
      // its lifetime timer and caller-presence watch armed, and leaving them
      // running leaked the subscription until the next ring came along.
      _stillRinging?.cancel();
      _stillRinging = null;
      _callerGone?.cancel();
      _callerGone = null;
      _showOffer(offer, replacingRing: true);
      return;
    }
    matrix.Logs().i('Rejoin offer shown for ${offer.room.id}');
    _showOffer(offer);
  }

  /// The ONE way a return offer goes up.
  ///
  /// Every offer is a promise that there is something to return to, and the
  /// watcher is what keeps the promise honest. One path -- the one that
  /// replaces a stale ring for the same room -- assigned the offer directly
  /// and armed nothing, so that banner could outlive the call it pointed at
  /// for ever. Assigning `_rejoin` anywhere but here is the bug; there is no
  /// second way to raise one.
  void _showOffer(RejoinOffer offer, {bool replacingRing = false}) {
    setState(() {
      _rejoin = offer;
      if (replacingRing) _showRing(null);
    });
    _watchOffer(offer);
  }

  /// The ONE way it comes down, watcher and all.
  void _clearOffer() {
    _offerWatch?.cancel();
    _offerWatch = null;
    if (_rejoin == null) return;
    _rejoin = null;
    if (mounted) setState(() {});
  }

  /// Watches a standing offer and withdraws it once the call is over.
  ///
  /// The offer is a promise that there is something to return to. Nothing was
  /// re-checking it, so the banner sat there long after both sides had hung
  /// up -- an invitation into an empty room. Level triggered: the room's own
  /// state answers it, and the crumb goes with the offer so a later reload
  /// cannot raise the same dead call again.
  Timer? _offerWatch;

  void _watchOffer(RejoinOffer offer) {
    _offerWatch?.cancel();
    // Checked once NOW, not only on the first tick five seconds from here. An
    // offer raised from a breadcrumb at startup is a guess about a call that
    // may already be over, and for those five seconds Return was a live
    // button into an empty room.
    _withdrawIfOver(offer);
    if (_rejoin == null) return;
    _offerWatch = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _rejoin == null) {
        _offerWatch?.cancel();
        _offerWatch = null;
        return;
      }
      _withdrawIfOver(offer);
    });
  }

  /// Takes the offer down if nobody is holding the call any more.
  ///
  /// Level triggered: the room's own state answers it, and the crumb goes
  /// with the offer so a later reload cannot raise the same dead call again.
  void _withdrawIfOver(RejoinOffer offer) {
    final service = _service;
    if (service == null) return;
    // Only on the answer that says the call is OVER. "No call state to read
    // yet" is the state of the world for the first moments after a reload --
    // which is precisely when this offer is raised -- and withdrawing on it
    // took down the offer, and the breadcrumb behind it, for a call that was
    // alive and waiting.
    // The floor comes from OUR membership's server timestamp, never from the
    // breadcrumb: the crumb is this device's own clock, and the memberships
    // being filtered are the server's. A device two minutes fast would set a
    // floor two minutes into the future of everything in the room, skip the
    // peer's still-live membership as "before this call", and clear a Return
    // offer while the other person was sitting in the call waiting. With no
    // server-domain anchor there is no floor at all -- the cost is that a
    // stale membership from an earlier call can keep a dead offer up a little
    // longer, which the next tick retires, and the join itself leaves quietly
    // if the room turns out to be empty. Erring towards keeping an offer is
    // the cheap mistake; erring towards destroying a live one is not.
    if (service.callHoldByAnother(
          offer.room,
          offer.membershipEventId,
          notBefore: CallService.callFloorFrom(
            service.membershipWrittenAt(offer.room, offer.membershipEventId),
          ),
        ) !=
        CallHold.over) {
      return;
    }
    matrix.Logs().i('The call to return to is over; withdrawing the offer');
    unawaited(CallBreadcrumb.clear());
    _clearOffer();
  }

  /// Declining the way back: the call ENDS.
  ///
  /// Dismissing used to only hide the banner, leaving our membership standing
  /// -- so the other person sat watching their reconnecting window run out
  /// for someone who had already decided not to return. Saying no is an
  /// answer, and it travels.
  void _endFromOffer(RejoinOffer offer) {
    final service = _service;
    unawaited(CallBreadcrumb.clear());
    _clearOffer();
    if (service == null) return;
    unawaited(
      service.abandonCall(offer.room, offer.membershipEventId).catchError((
        Object e,
        StackTrace s,
      ) {
        matrix.Logs().w('Could not end the call from the return offer', e, s);
        return false;
      }),
    );
  }

  void _acceptRejoin(RejoinOffer offer) {
    // The breadcrumb is NOT cleared here. It is the only durable record that
    // this device was in a call, and rejoining can fail -- a token request, a
    // focus lookup or the SFU connect can all miss. Clearing it first threw
    // away the retry path before knowing whether it was needed, and the
    // failed-call screen only offers Close, so the learner was left with a
    // peer still waiting in a call they could no longer reach. The rejoined
    // call owns it from here: it re-drops the crumb once it is up, and erases
    // it on a clean teardown.
    _clearOffer();
    if (!mounted) return;
    try {
      Matrix.of(context).startCall(
        offer.room,
        // The call comes back as what it WAS. Returning always as audio left
        // a video call with the camera off and the other person's picture
        // gone for good.
        video: offer.video,
        rejoinMembershipEventId: offer.membershipEventId,
        rejoinSince: offer.since,
      );
    } on AlreadyInACall {
      // A call started somewhere else while this offer was on screen. The one
      // in progress wins and has already been brought forward; there is
      // nobody to tell, because a return is not a ring.
      matrix.Logs().i('Cannot return: this account is already on a call');
      return;
    }
    final router = FluffyChatApp.router;
    final uri = router.routeInformationProvider.value.uri;
    router.go(WorkspaceNav.openRoomById(uri, offer.room.id));
  }

  /// Puts back a ring that arrived while this device was not listening.
  ///
  /// Runs behind the live subscription deliberately: a ring that is still
  /// arriving normally should come through that, and [_offer] keeps whichever
  /// arrives first rather than letting the replay overwrite it.
  Future<void> _replayMissed(MatrixState matrixState, String account) async {
    final List<IncomingCallNotification> missed;
    try {
      missed = await matrixState.callService.ringsMissed();
    } catch (e, s) {
      matrix.Logs().w('Could not look for calls missed while away', e, s);
      return;
    }
    if (!mounted || _listeningTo != account) return;
    for (final ring in missed) {
      _offer(ring, account);
    }
  }

  /// The one gate every ring goes through, live or replayed.
  ///
  /// Both sources have to apply the same rules — a replayed ring that skipped
  /// the redial rule, or the account check, would put up a prompt the live path
  /// would have refused.
  /// Whether [ring] offers a call that still exists AND is not the very call
  /// [against] would return to.
  ///
  /// Two tests, both needed. The membership test alone is not enough: while
  /// the peer holds their place for our return, their membership -- and so
  /// the ORIGINAL ring of the call we were in -- still reads current, and it
  /// would beat the offer to rejoin itself. The breadcrumb knows when this
  /// device was in the call; a ring sent before that moment is that call's
  /// own past (it rang, we answered, we died), and only one sent after is a
  /// genuine new call.
  bool _ringIsLive(IncomingCallNotification ring, RejoinOffer? against) {
    // Compared in ONE clock domain, through `orderedAt`; the breadcrumb's
    // `since` is this device's own clock. Comparing them directly made the answer depend on how far
    // this device's clock had drifted -- ten seconds slow was enough to read
    // the call's OWN original ring as newer than the call, so the offer to
    // return to it was thrown away. Our membership event's `origin_server_ts`
    // says the same thing as the crumb in the ring's domain, and the crumb is
    // the fallback for an offer whose event has aged out of state.
    // Server time or nothing. The crumb's own timestamp is this device's
    // clock, and ordering it against a server-stamped ring compares two
    // different clocks -- a device two minutes fast then read a genuinely new
    // ring as older than the call it was interrupting, so the new call never
    // rang and a dead offer stayed up. When our membership has aged out of
    // state there is no server-domain anchor to order against, and there is
    // also nothing left to protect: an offer whose own membership is gone
    // cannot outrank a live ring, so the ring wins.
    final since = against == null
        ? null
        : _service?.membershipWrittenAt(
            against.room,
            against.membershipEventId,
          );
    if (against != null && since == null) return true;
    // ORDERED by the server's stamp, not the sender's. `sentAt` prefers the
    // caller's own clock while it is within the skew allowance, which is
    // right for deciding when a ring EXPIRES -- the lifetime is the sender's
    // promise -- and wrong for putting a ring in sequence against a
    // membership the server stamped. A caller ten seconds slow could
    // otherwise have a genuinely new ring read as older than the call it was
    // interrupting, leaving a dead Return offer up and the new call silent.
    if (since != null && !ring.orderedAt.isAfter(since)) {
      return false;
    }
    final named = ring.membershipEventId;
    if (named == null) return false;
    return _service?.membershipEventIsCurrent(
          ring.event.room,
          ring.event.senderId,
          named,
        ) ??
        false;
  }

  void _offer(IncomingCallNotification ring, String account) {
    // Checked against the account this subscription was made for, BEFORE any
    // state is touched. Cancelling does not unqueue what has already been
    // handed over, so a ring for the account the learner just left could
    // still land here — and besides answering with the wrong account, it
    // must not clear this account's offer or setState after dispose.
    if (!mounted || _listeningTo != account) return;
    // Same room as a standing rejoin offer: one rule, by evidence. A ring
    // naming the caller's CURRENT membership is a live call happening NOW --
    // it wins, and the offer goes (the caller has moved on, so the call the
    // offer would return to is over). A ring naming an older membership is
    // this account's own call's past, and the offer wins.
    if (_rejoin?.room.id == ring.event.room.id) {
      if (!_ringIsLive(ring, _rejoin)) return;
      // The trace goes with the offer: a genuine newer call for this room
      // means the old one is finished, and a crumb left standing would
      // resurrect its dead Return offer on a reload inside the age bound.
      unawaited(CallBreadcrumb.clear());
      _clearOffer();
    }
    // Never one already turned down.
    if (_declined.contains(ring.event.eventId)) return;
    final showing = _ringing;
    if (showing != null) {
      if (showing.event.eventId == ring.event.eventId) return;
      // One conversation at a time: a call from somebody else does not take
      // the prompt away from the one the learner is looking at. A REDIAL
      // does. The caller hung up and tried again, and a card still pointing
      // at the first ring answers a call that is already over — and declines
      // it to a caller who is no longer listening for that one.
      //
      // The second caller's ring is dropped rather than queued. Holding it
      // would mean a prompt appearing for a call that may have been given up
      // on while the learner dealt with the first, which reads as a phantom
      // call; the cost is that a second caller during a call goes unanswered,
      // as they would on a phone.
      if (showing.event.room.id != ring.event.room.id) return;
      // A redial replaces the ring it redials -- but only FORWARDS. The
      // startup replay hands rings over newest-first, so without this the
      // older one arrived second and overwrote the live redial, and the
      // learner then answered a call that was already over: the wrong
      // notification id, pointed at a membership nobody is holding.
      if (ring.orderedAt.isBefore(showing.orderedAt)) return;
    }
    setState(() => _showRing(ring));
    _watchForGiveUp(ring);
  }

  /// Dismisses the prompt when the ring lifetime lapses.
  ///
  /// The notification carries how long it rings; after that the call is taken as
  /// unanswered and the prompt goes. Read from the notification, so nothing here
  /// touches the call machinery for a call this device has not joined.
  void _watchForGiveUp(IncomingCallNotification ring) {
    _stillRinging?.cancel();
    final remaining = ring.expiresAt.difference(DateTime.now());
    _stillRinging = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (mounted && _ringing?.event.eventId == ring.event.eventId) _dismiss();
    });
    _watchCaller(ring);
    _watchSiblings(ring);
  }

  /// Stops this device ringing the moment ANOTHER of our devices answers.
  ///
  /// Answering sends no decline -- it is not a refusal -- so nothing used to
  /// tell the other phone, and it went on offering a call that had already
  /// been picked up until its ring timed out. Our own membership appearing
  /// for that call from a different device is the evidence, and it needs no
  /// new message.
  StreamSubscription<void>? _siblingAnswered;

  void _watchSiblings(IncomingCallNotification ring) {
    _siblingAnswered?.cancel();
    final service = _service;
    if (service == null) return;
    final room = ring.event.room;
    // Ordered against membership timestamps, which are the server's, so this
    // has to be the server's too.
    final sentAt = ring.orderedAt;
    // Checked NOW as well as on every change. The reasoning for not checking
    // immediately held only for a LIVE ring, where nothing written after it
    // can exist yet -- but a ring recovered from the timeline at startup can
    // be minutes old, and the other device may have answered it long before
    // this one came back. Without the immediate look, no new event ever
    // fires and the replayed prompt goes on offering to answer a call that
    // was answered elsewhere. The check is harmless on a live ring: it looks
    // for a membership written AFTER the ring, and there is none.
    if (service.answeredOnAnotherDevice(room, sentAt)) {
      matrix.Logs().i('Already answered on another device; not ringing here');
      _dismiss();
      return;
    }
    _siblingAnswered = service.ownPresenceChanges(room).listen((_) {
      if (!mounted || _ringing?.event.eventId != ring.event.eventId) return;
      if (!service.answeredOnAnotherDevice(room, sentAt)) return;
      matrix.Logs().i('Answered on another device; this one stops ringing');
      _dismiss();
    });
  }

  /// Stops the prompt the moment the caller gives up.
  ///
  /// Cancelling an unanswered call sends nothing that says so — the caller just
  /// retracts its membership — so this watches for that membership going away.
  /// Without it the prompt kept ringing for the rest of the lifetime, and
  /// answering it joined a call the caller had already walked out of.
  ///
  /// Strictly TRANSITION-based: the membership must have been SEEN present
  /// before its absence counts. State may not have synced yet when a ring
  /// arrives, and treating "not there yet" as "gone" would silence real calls —
  /// the failure that matters most here. Never seeing it present simply leaves
  /// the lifetime timer in charge, which is the behaviour this had before.
  void _watchCaller(IncomingCallNotification ring) {
    _callerGone?.cancel();
    final service = _service;
    if (service == null) return;
    final room = ring.event.room;
    final callerId = ring.event.senderId;
    final callerDevice = ring.senderDeviceId;
    var wasPresent = service.callerStillInCall(
      room,
      callerId,
      deviceId: callerDevice,
    );
    _callerGone = service.callerPresenceChanges(room, callerId).listen((_) {
      if (!mounted || _ringing?.event.eventId != ring.event.eventId) return;
      final present = service.callerStillInCall(
        room,
        callerId,
        deviceId: callerDevice,
      );
      if (present) {
        wasPresent = true;
        return;
      }
      if (wasPresent) _dismiss();
    });
  }

  @override
  void dispose() {
    _rings?.cancel();
    _ownDeclines?.cancel();
    _callerGone?.cancel();
    _stillRinging?.cancel();
    _activeCall?.removeListener(_onActiveCallChanged);
    _offerWatch?.cancel();
    _siblingAnswered?.cancel();
    _ringPlayer.stopAll();
    super.dispose();
  }

  void _dismiss() {
    _stillRinging?.cancel();
    _stillRinging = null;
    _callerGone?.cancel();
    _callerGone = null;
    _siblingAnswered?.cancel();
    _siblingAnswered = null;
    if (mounted) setState(() => _showRing(null));
  }

  /// Turns the call down and tells the caller, so their phone stops ringing.
  void _decline(IncomingCallNotification ring) {
    _declined.add(ring.event.eventId);
    unawaited(
      Matrix.of(context).callService
          .decline(ring.event.room, notificationEventId: ring.event.eventId)
          // The prompt is already gone and nothing is waiting on this, so an
          // ordinary network failure would surface as an unhandled async error
          // rather than as the caller simply ringing out.
          .catchError((Object e, StackTrace s) {
            matrix.Logs().w('Could not tell the caller we declined', e, s);
          }),
    );
    _dismiss();
  }

  /// Turns the call down and says why, in the conversation itself.
  ///
  /// If the learner answered on another phone a moment earlier, the caller's
  /// side re-reads who is present and does not end the call — but this message
  /// still goes to the room, so a "can't talk right now" can land in a
  /// conversation that is happening. Knowing the call had been answered would
  /// mean trusting a membership for liveness, and a device that crashed leaves
  /// one that reads live for about twelve minutes; wired to a prompt, that
  /// silences real calls. An odd line in the chat is the cheaper mistake.
  ///
  /// The decline still goes out first: the caller's phone should stop ringing
  /// whether or not the message sends, and the message is the courtesy on top
  /// rather than the mechanism.
  void _declineWith(IncomingCallNotification ring, String message) {
    final room = ring.event.room;
    _decline(ring);
    unawaited(
      room.sendTextEvent(message).catchError((Object e, StackTrace s) {
        // The call is already declined and the prompt already gone. A message
        // that will not send must not resurrect either.
        matrix.Logs().w('Could not send the quick reply', e, s);
        return null;
      }),
    );
  }

  Future<void> _answer(IncomingCallNotification ring) async {
    _dismiss();
    if (!mounted) return;
    // Deliberately NOT gated on the caller still being visible in Matrix room
    // state. That read lags a join by seconds, so it was routinely empty at the
    // moment someone tapped answer — and answering did nothing at all. The SFU
    // is the rendezvous point: join it, and let presence decide from there
    // whether anyone is actually on the other end.
    try {
      Matrix.of(context).startCall(
        ring.event.room,
        video: ring.isVideo,
        // Anchors this side's speaking analytics: the answering device does
        // not write the call to the timeline, the caller does.
        notificationEventId: ring.event.eventId,
        // The caller's own membership, named by their ring: the call's SHARED
        // identity, which every card for this call is stamped with.
        callerMembershipEventId: ring.membershipEventId,
      );
    } on AlreadyInACall {
      // A call is live somewhere else -- another account, or another room on
      // this one. The answer cannot happen, and the prompt is already down --
      // so TELL the caller rather than leaving them ringing into nothing
      // until they time out and write a missed call.
      matrix.Logs().w('Answering while already on a call elsewhere');
      final service = _service;
      if (service != null) {
        unawaited(() async {
          try {
            await service.decline(
              ring.event.room,
              notificationEventId: ring.event.eventId,
              reason: CallService.declineBusy,
            );
          } catch (e, s) {
            matrix.Logs().w('Could not turn down a call we cannot take', e, s);
          }
        }());
      }
      return;
    }
    // The call lives in its own chat's pane, so answering also goes there.
    // Through the app's router directly: this banner is mounted above it.
    final router = FluffyChatApp.router;
    final uri = router.routeInformationProvider.value.uri;
    router.go(WorkspaceNav.openRoomById(uri, ring.event.room.id));
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _ringing;
    return ValueListenableBuilder<RejoinOffer?>(
      valueListenable: _rejoinStore ?? ValueNotifier<RejoinOffer?>(null),
      builder: (context, rejoin, _) => _buildStack(context, ringing, rejoin),
    );
  }

  Widget _buildStack(
    BuildContext context,
    IncomingCallNotification? ringing,
    RejoinOffer? rejoin,
  ) {
    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        // A live ring outranks the offer to return: someone is calling NOW.
        // The offer keeps its state and comes back if the ring resolves.
        if (ringing == null && rejoin != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _ReturnCard(
                  key: ValueKey(rejoin.membershipEventId),
                  offer: rejoin,
                  onReturn: () => _acceptRejoin(rejoin),
                  onEnd: () => _endFromOffer(rejoin),
                ),
              ),
            ),
          ),
        if (ringing != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Align(
              alignment: Alignment.topCenter,
              // A call card is not a page banner. Constrained and centred so it
              // reads as a card on a tablet or a desktop window instead of a
              // strip pinned across the whole width.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _CallCard(
                  key: ValueKey(ringing.event.eventId),
                  ring: ringing,
                  onAnswer: () => _answer(ringing),
                  onDecline: () => _decline(ringing),
                  onQuickReply: (message) => _declineWith(ringing, message),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card itself: who is calling, and what can be done about it.
class _CallCard extends StatefulWidget {
  final IncomingCallNotification ring;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final void Function(String message) onQuickReply;

  const _CallCard({
    required this.ring,
    required this.onAnswer,
    required this.onDecline,
    required this.onQuickReply,
    super.key,
  });

  @override
  State<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<_CallCard>
    with SingleTickerProviderStateMixin {
  /// Whether the preset replies have taken over the card's action row.
  ///
  /// Shown in place rather than as a sheet on top: the card is already an
  /// overlay, and stacking a second one over it puts the learner two dismissals
  /// away from a ringing phone.
  bool _choosingReply = false;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  matrix.Room get _room => widget.ring.event.room;

  /// The caller, not the room. In a direct message the two usually agree, but a
  /// room named after something else would otherwise show the wrong name on the
  /// one screen where who is calling is the entire question.
  matrix.User get _caller =>
      _room.unsafeGetUserFromMemoryOrFallback(widget.ring.event.senderId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final caller = _caller;

    final curve = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween(
        begin: const Offset(0, -0.25),
        end: Offset.zero,
      ).animate(curve),
      child: FadeTransition(
        opacity: curve,
        // A plain decorated box, NOT a Material with elevation and a clip. On
        // the CanvasKit web renderer a clipped, elevated Material repaints its
        // whole clip region as an opaque grey rectangle the instant any child
        // inside it changes — which a hover does — and that grey box swallowed
        // the answer and decline buttons. The rounded corners and the shadow
        // come from the decoration instead, which has no clip layer to go grey,
        // and the buttons carry their own Material for their ink.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identity(theme, l10n, caller),
                const SizedBox(height: 14),
                // Swapped directly, NOT through AnimatedSize. Its clip repaints
                // as an opaque grey box on Flutter web on any hover or repaint —
                // the "grey thing" that covered the card the moment the pointer
                // touched it. The card resizing in one frame when the quick
                // replies open is unremarkable next to a phone that is ringing.
                if (_choosingReply)
                  CallQuickReplyList(
                    onPick: widget.onQuickReply,
                    onBack: () => setState(() => _choosingReply = false),
                  )
                else
                  _actions(theme, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme, L10n l10n, matrix.User caller) => Row(
    children: [
      Avatar(
        mxContent: caller.avatarUrl,
        name: caller.calcDisplayname(),
        size: 52,
        showPresence: false,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caller.calcDisplayname(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            // The full Matrix id, so two people with the same display name are
            // still distinguishable at the moment of answering.
            Text(
              caller.id,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.ring.isVideo ? Icons.videocam : Icons.call,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.ring.isVideo
                      ? l10n.callIncomingVideo
                      : l10n.callIncomingVoice,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _actions(ThemeData theme, L10n l10n) => Row(
    children: [
      Expanded(
        child: TextButton.icon(
          onPressed: () => setState(() => _choosingReply = true),
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(l10n.callQuickReply, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _CircleAction(
        icon: Icons.call_end,
        tooltip: l10n.callDecline,
        background: theme.colorScheme.error,
        foreground: theme.colorScheme.onError,
        onPressed: widget.onDecline,
      ),
      const SizedBox(width: 10),
      _CircleAction(
        icon: widget.ring.isVideo ? Icons.videocam : Icons.call,
        tooltip: l10n.callAnswer,
        // Answer is the affirmative action and green is what every calling
        // product uses for it; the scheme's primary is not reliably distinct
        // from the decline colour across this app's themes.
        background: const Color(0xFF2E7D32),
        foreground: Colors.white,
        onPressed: widget.onAnswer,
      ),
    ],
  );
}

/// A round call action, sized to be an easy target on a phone.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    // No Tooltip. On the CanvasKit web renderer a Tooltip's overlay is the other
    // widget that paints a grey rectangle over the card on hover, and a round
    // answer or decline button does not need a hover hint — the icon says it,
    // and the label a screen reader needs is carried here.
    button: true,
    label: tooltip,
    child: Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: foreground, size: 22),
        ),
      ),
    ),
  );
}

/// The offer to return to a call a reload interrupted.
///
/// Deliberately quieter than the ring card: nothing is ringing. It states the
/// fact and offers the way back; the tap is what finds out whether the call is
/// still there, and a call that is not is left as quietly as it was offered.
class _ReturnCard extends StatelessWidget {
  final RejoinOffer offer;
  final VoidCallback onReturn;
  final VoidCallback onEnd;

  const _ReturnCard({
    required this.offer,
    required this.onReturn,
    required this.onEnd,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    matrix.Logs().i('ReturnCard building for ${offer.room.id}');
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final peerId = offer.room.directChatMatrixID;
    final peer = peerId == null
        ? null
        : offer.room.unsafeGetUserFromMemoryOrFallback(peerId);
    final name =
        peer?.calcDisplayname() ?? offer.room.getLocalizedDisplayname();

    // The same decorated box as the ring card, for the same web-renderer
    // reason: a clipped, elevated Material repaints grey on hover there.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            Avatar(
              mxContent: peer?.avatarUrl,
              name: name,
              size: 44,
              showPresence: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.callReturnOffer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Both controls are built the way the round call actions above
            // are, and for the two reasons this file already states. NEVER a
            // Tooltip: this banner is mounted above the router's Navigator,
            // so nothing here has an Overlay ancestor, and the throw takes
            // the whole banner down -- including the ring card beside it. And
            // never a Material that carries elevation or a clip: on the
            // CanvasKit web renderer such a Material repaints its region as
            // an opaque grey rectangle the moment a child changes, which a
            // HOVER does, and the grey box swallows the card. FilledButton
            // and IconButton each bring one, which is exactly what appeared
            // over this banner on hover.
            // Red, and it MEANS it: the other person is waiting out their
            // reconnecting window, and this tells them the answer.
            _FlatAction(
              icon: Icons.call_end,
              label: l10n.callHangUp,
              onPressed: onEnd,
              background: const Color(0xFFD32F2F),
              foreground: Colors.white,
            ),
            const SizedBox(width: 8),
            _FlatAction(
              icon: Icons.call,
              label: l10n.callReturn,
              onPressed: onReturn,
              background: theme.colorScheme.primary,
              foreground: theme.colorScheme.onPrimary,
              showLabel: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// A banner control with no elevation and no clip.
///
/// The rule this file keeps relearning: on the CanvasKit web renderer a
/// Material that carries elevation or a clip repaints its whole region as an
/// opaque grey rectangle whenever a child changes -- and a hover is a child
/// changing. Material's own buttons (FilledButton, IconButton) each bring
/// one, so the banner builds its controls from a flat Material and an InkWell
/// instead, exactly as the round answer and decline actions do. The label a
/// screen reader needs rides on Semantics, never a Tooltip: there is no
/// Overlay above the router for one to live in.
class _FlatAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;
  final bool showLabel;

  const _FlatAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        // No elevation, no clipBehavior: both are the grey box.
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 16 : 10,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
