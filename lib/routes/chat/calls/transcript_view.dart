import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_box.dart';
import 'package:fluffychat/routes/chat/audio_player.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_selection.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_playback_controller.dart';
import 'package:fluffychat/routes/chat/calls/call_recordings_load.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_tokens.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';
import 'package:fluffychat/utils/multi_platform_audio_player.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Opens the transcript of one finished call.
///
/// A dialog rather than a route: it is read from a card in the timeline and
/// dismissed back to it, and [FullWidthDialog] already gives a full screen on
/// a phone and a panel on a wide window.
Future<void> showCallTranscript(
  BuildContext context, {
  required Room room,
  required String callKey,
}) => showDialog(
  context: context,
  useRootNavigator: false,
  builder: (_) => FullWidthDialog(
    maxWidth: 640,
    maxHeight: 800,
    dialogContent: CallTranscriptView(room: room, callKey: callKey),
  ),
);

/// Who could have written a half of THIS CALL, and whether that is an answer.
///
/// A 1:1 call has exactly two sides, and both are known locally: this account,
/// and the room's direct-chat peer. Nothing here comes from room content.
///
/// The card's `caller` field used to be consulted, to name a caller who had
/// since left the room. It was never needed: [peerId] is read from the m.direct
/// account data, which records who the conversation is with and does not change
/// when they leave. So the field bought nothing, and it is written by whoever
/// wrote the card.
///
/// Checking it harder was the wrong answer, and the first attempt shows why --
/// it asked whether the name had EVER been a member of this room, which is not
/// the same question as whether they were on this call. An attacker with a
/// second account could join it, leave it, and still satisfy that check, then
/// forge both a card naming it and a half from it: fabricated speech attributed
/// to somebody who was never on the call. The fix is not a better check on an
/// untrusted field. It is not to need the field.
///
/// This list matters in both directions, which is why it is derived and not
/// asserted: assembly reports a named participant who wrote nothing as ABSENT
/// rather than omitting them, and DROPS a half from anyone not named -- which
/// is what stops a stranger writing themselves a section.
///
/// The list and whether it is an ANSWER come back together, because they are
/// one fact read two ways and splitting them is how the second came to
/// contradict the first. The caller built the list from the peer AND this
/// account, then asked only whether the PEER was known -- so a null `userID`
/// produced a one-id list that reported itself authoritative, and an
/// authoritative list missing our own id is one assembly may DROP our own half
/// against: no section, on a read it calls complete. That is the failure
/// `assembleTranscript` exists to prevent, reached through the guard meant to
/// prevent it. Not provokable while a signed-in client renders a Room, which is
/// exactly how a guard that asserts more than it checks survives review.
@visibleForTesting
({List<String> ids, bool known}) callParticipants({
  required String? me,
  required String? peerId,
}) {
  final ids = <String>{?me, ?peerId};

  return (
    // Sorted, so the sections do not reorder between two reads of the same
    // call.
    ids: ids.toList()..sort(),
    // Every id this list is BUILT from, not only the one that is usually
    // missing. A list is an answer when nothing that goes into it was absent.
    known: me != null && peerId != null,
  );
}

class CallTranscriptView extends StatefulWidget {
  final Room room;
  final String callKey;

  /// Injected only by tests, which have no homeserver to read from.
  final RelationsFetcher? fetcher;

  /// Injected only by tests, so a widget test can drive the "Full call" slot's
  /// [CallRecordingsLoadState] deterministically (its own grace clock and
  /// timer) rather than waiting out a real ~30s window. Production always
  /// builds its own with a real monotonic clock.
  final CallRecordingsLoadController? recordingsLoadController;

  const CallTranscriptView({
    required this.room,
    required this.callKey,
    this.fetcher,
    this.recordingsLoadController,
    super.key,
  });

  @override
  State<CallTranscriptView> createState() => _CallTranscriptViewState();
}

class _CallTranscriptViewState extends State<CallTranscriptView> {
  late Future<CallTranscript> _transcript;

  /// The call's saved audio, fetched alongside the transcript rather than
  /// after it -- see [_load] -- so a slow recordings read never adds its own
  /// wait on top of the transcript's.
  ///
  /// Never fails: [_loadRecordings] catches and logs, because a recording is
  /// a bonus on top of the transcript and a hiccup fetching it must not take
  /// the (working) transcript down with it. See that method.
  late Future<List<CallAudioRecording>> _recordings;

  /// The call's merged, full-call recording(s), read alongside the halves --
  /// see [_load] -- so the "Full call" primary row and the per-device halves
  /// are fetched CONCURRENTLY rather than one after the other.
  ///
  /// Isolated from both the transcript AND the halves the same way [_recordings]
  /// is: [_loadMerged] catches and logs, so a slow or failed merged read never
  /// holds up -- or takes down -- either. The player picks ONE of these to show
  /// via [selectMergedRow]; a stray extra merge in room history is not this
  /// screen's problem to resolve.
  late Future<List<CallAudioMergedRecording>> _merged;

  /// The "Full call" slot's loading state machine (spec section 3). Fed the
  /// recordings/merged reads' progress by [_feedLoadController]; drives the
  /// pinned bar's content via [state]. A test may inject one with a
  /// controllable clock (see [CallTranscriptView.recordingsLoadController]);
  /// production builds its own with a real monotonic clock. REPLACED on
  /// [_retry] (unless injected) so a re-load starts a fresh epoch rather than
  /// inheriting a latched terminal `ready`; disposed by [dispose] either way.
  late CallRecordingsLoadController _loadController =
      widget.recordingsLoadController ?? CallRecordingsLoadController();

  /// The per-device recordings section, collapsed by default behind the
  /// Full-call bar's chevron (spec section 2/D3: "Full call is the hero").
  bool _devicesExpanded = false;

  /// Karaoke sync (spec section 4), wired ONLY while a merged "Full call" row
  /// is actually on screen -- otherwise every field here stays null and
  /// [TurnTimeline] is handed null callbacks, so the transcript renders
  /// EXACTLY as it does today (the hard invariant). [_playbackMergedEventId]
  /// is the merged event the live [_playback] was built for, so a rebuild
  /// only rebuilds the controller when that identity changes, not on every
  /// frame.
  MatrixState? _matrix;
  CallPlaybackController? _playback;
  String? _playbackMergedEventId;

  /// Bridges the merged player's own `positionStream`/`playerStateStream` to
  /// the two stable streams [CallPlaybackController] subscribes to once at
  /// construction. Attached by [_attachObservation] to the SPECIFIC player
  /// [_startMergedPlayer] creates -- never guessed from `matrix.audioPlayer`,
  /// a field reassigned with no notification (see [_onVoiceOwnershipChanged]).
  StreamController<Duration>? _positionBridge;
  StreamController<bool>? _playingBridge;
  AudioPlayer? _observedPlayer;
  StreamSubscription<Duration>? _observedPositionSub;
  StreamSubscription<PlayerState>? _observedStateSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Worked out ONCE and both facts carried together: who we think took part,
    // and whether that is an answer or a guess. Read separately, the second
    // one is what gets forgotten -- and a guess presented as an answer is how
    // a real half comes to be discarded in silence. It was read separately
    // here, and the guess it presented as an answer was a list with no id of
    // our own in it.
    final me = widget.room.client.userID;
    final participants = callParticipants(
      me: me,
      peerId: callPeerOf(widget.room),
    );
    // ONE fetcher, reused for both relation types -- the seam is generic in
    // `relType` (see `RelationsFetcher`), and a second one here would be a
    // second thing a test double has to stand in for.
    final fetch = widget.fetcher ?? relationsFetcherFor(widget.room.client);
    _transcript = fetchCallTranscript(
      fetch: fetch,
      roomId: widget.room.id,
      callKey: widget.callKey,
      selfId: me,
      expectedSenders: participants.ids,
      participantsKnown: participants.known,
      encrypted: widget.room.encrypted,
    );
    // Started here, alongside the transcript fetch, so the relation types are
    // read CONCURRENTLY rather than one after the other. The transcript fetch
    // stays FIRST so it is the read whose failure surfaces as the retryable
    // error state -- the two audio reads only ever add a row and never fail
    // the screen.
    _recordings = _loadRecordings(fetch);
    _merged = _loadMerged(fetch);

    // The reads are in flight: put the Full-call slot's machine into
    // [CallRecordingsLoadState.loading] until they both land. The true->false
    // edge that stamps the grace window is fed by [_feedLoadController] when
    // the reads complete.
    _loadController.update(readsInFlight: true, halfCount: 0, hasMerge: false);
    _feedLoadController();
  }

  /// Feeds the load machine the outcome of the current [_recordings]/[_merged]
  /// reads once BOTH have landed (spec section 3: the grace window is stamped
  /// "the instant BOTH reads first complete"). Neither future ever rejects
  /// ([_loadRecordings]/[_loadMerged] turn a failure into an empty list), so
  /// this needs no error branch. Drops a superseded result by FUTURE IDENTITY:
  /// a [_retry] swaps in fresh futures, and only the latest pair may feed the
  /// machine.
  ///
  /// NOTE: this feeds the machine independently of whether the transcript read
  /// itself succeeded (the two are deliberately decoupled -- a recordings
  /// hiccup must not fail the transcript, and vice versa). [_retry] REPLACES
  /// the machine, so a merge that latched `ready` under a failed-transcript
  /// load never carries a stale `ready` into the retried screen.
  void _feedLoadController() {
    final recordings = _recordings;
    final merged = _merged;
    Future.wait<Object>([recordings, merged]).then((results) {
      if (!mounted ||
          !identical(recordings, _recordings) ||
          !identical(merged, _merged)) {
        return;
      }
      final recs = results[0] as List<CallAudioRecording>;
      final mergedList = results[1] as List<CallAudioMergedRecording>;
      final mergedRow = selectMergedRow(mergedList, recs.length);
      // More than two halves is a mid-call device switch: `selectMergedRow`
      // suppresses the merge for v1, so NO merge is ever coming. Feed the
      // machine zero MERGEABLE halves in that case, so it resolves `none` (the
      // note, immediately) rather than sitting in `pendingMerge` shimmering
      // out the full grace for a merge that will never arrive. A `<= 2`-half
      // call with no merge yet still feeds its real count, so it correctly
      // waits (pendingMerge) for a merge that genuinely might land.
      final mergeableHalfCount = recs.length > 2 ? 0 : recs.length;
      _loadController.update(
        readsInFlight: false,
        halfCount: mergeableHalfCount,
        hasMerge: mergedRow != null,
      );
    });
  }

  /// [fetchCallAudio], with a failure turned into an empty list rather than
  /// left to propagate.
  ///
  /// A recording is supplementary: the transcript is the primary content of
  /// this screen and already has its own retry path, and coupling its
  /// fate to a second relation fetch would let a recordings-only hiccup take
  /// a working transcript down too. So the failure is caught here rather
  /// than at the `FutureBuilder` -- but it is never swallowed BENIGNLY: it is
  /// logged, because "no recordings" and "could not read them" are different
  /// facts and only the log can still tell them apart afterwards.
  Future<List<CallAudioRecording>> _loadRecordings(
    RelationsFetcher fetch,
  ) async {
    try {
      return await fetchCallAudio(
        fetch: fetch,
        roomId: widget.room.id,
        callKey: widget.callKey,
      );
    } catch (e, s) {
      Logs().e('Could not load call recordings for ${widget.callKey}', e, s);
      return const <CallAudioRecording>[];
    }
  }

  /// [fetchCallAudioMerged], with a failure turned into an empty list rather
  /// than left to propagate -- the exact mirror of [_loadRecordings], and for
  /// the exact same reason: the merged "Full call" recording is supplementary
  /// to both the transcript and the per-device halves, so a hiccup reading it
  /// must not take either of them down. Never swallowed benignly: "no merge"
  /// and "could not read the merge" are different facts, and only the log can
  /// still tell them apart afterwards.
  Future<List<CallAudioMergedRecording>> _loadMerged(
    RelationsFetcher fetch,
  ) async {
    try {
      return await fetchCallAudioMerged(
        fetch: fetch,
        roomId: widget.room.id,
        callKey: widget.callKey,
      );
    } catch (e, s) {
      Logs().e(
        'Could not load merged call recording for ${widget.callKey}',
        e,
        s,
      );
      return const <CallAudioMergedRecording>[];
    }
  }

  void _retry() {
    setState(() {
      // A fresh load epoch. The load machine latches `ready` terminally, so a
      // merge found under a PREVIOUS load (even one whose transcript failed,
      // leaving the bar unshown) would otherwise carry a stale `ready` into
      // the retried screen -- and if this re-read no longer selects a merge,
      // that stale `ready` has no player to show. Replacing the machine (never
      // a test-injected one) starts the retry cleanly at `loading`.
      if (widget.recordingsLoadController == null) {
        _loadController.dispose();
        _loadController = CallRecordingsLoadController();
      }
      _load();
    });
  }

  @override
  void dispose() {
    _disposePlayback();
    _loadController.dispose();
    super.dispose();
  }

  // ---- Karaoke wiring (spec section 4) ----------------------------------

  /// (Re)wires or tears down the [CallPlaybackController] for the merged row
  /// currently on screen. Called from [build] so the controller and
  /// [TurnTimeline] receive the same [displayTurns] in the SAME build (spec
  /// section 4's same-tick requirement, which the controller's index
  /// resolution relies on).
  ///
  /// Enabled ONLY while a merged "Full call" row is shown AND there are turns
  /// to highlight; otherwise every controller field stays null and
  /// [TurnTimeline] is handed null callbacks, so the screen renders EXACTLY as
  /// it does today (the hard invariant). The controller is rebuilt only when
  /// the merged event's IDENTITY changes, never on an ordinary rebuild -- a
  /// fresh (equal-content) [displayTurns] list each build just feeds
  /// [CallPlaybackController.updateTurns].
  void _syncPlayback(
    CallAudioMergedRecording? mergedRow,
    List<CallTurn> displayTurns,
  ) {
    final enabled = mergedRow != null && displayTurns.isNotEmpty;
    if (!enabled) {
      if (_playback != null) _disposePlayback();
      return;
    }

    if (_playback != null && _playbackMergedEventId == mergedRow.eventId) {
      _playback!.updateTurns(displayTurns);
      return;
    }

    // A new merged row (first appearance, or an identity change): tear down
    // any prior controller and build one over this row's own streams.
    _disposePlayback();
    final matrix = Matrix.of(context);
    _matrix = matrix;
    _playbackMergedEventId = mergedRow.eventId;
    _positionBridge = StreamController<Duration>.broadcast();
    _playingBridge = StreamController<bool>.broadcast();
    _playback = CallPlaybackController(
      position: _positionBridge!.stream,
      playing: _playingBridge!.stream,
      ownership: matrix.voiceMessageEventId,
      mergedEventId: mergedRow.eventId,
      turns: displayTurns,
      startMergedPlayer: () => _startMergedPlayer(mergedRow),
      seek: _seekSharedPlayer,
      play: _playSharedPlayer,
    );
    matrix.voiceMessageEventId.addListener(_onVoiceOwnershipChanged);
  }

  /// The controller reacts to ownership itself (clearing its active index).
  /// Here we only tear the position/playing observation DOWN once the merged
  /// recording is no longer the active shared player. Observation is only ever
  /// ATTACHED to a player we are ACTIVELY acting on while we own the merged
  /// event -- the one [_startMergedPlayer] creates, or (when a bar-started
  /// playback already owns the merged id) the one a turn tap seeks/plays via
  /// [_seekSharedPlayer]/[_playSharedPlayer]. It is never guessed from
  /// `matrix.audioPlayer` on a bare ownership edge, where that field can
  /// momentarily hold a stale (already-disposed) or foreign instance.
  ///
  /// KNOWN, DOCUMENTED GAPS (both narrow, both bar-initiated, neither affects
  /// the null-merge screen or a karaoke seek from a turn on a fresh load):
  /// - A playback the reader starts SOLELY by tapping the Full-call bar's OWN
  ///   play button, and never taps a turn, is not observed (the bar creates
  ///   its player inside `AudioPlayerWidget`, which this widget has no signal
  ///   for). The moment they tap any turn's time, the seek/play attaches to
  ///   that same player and the follow-along engages; the bar's own
  ///   pause/resume then drive that instance too, so they stay in sync.
  /// - A turn tapped in the brief window while a BAR-started playback is still
  ///   downloading (the bar owns the merged id, but its player is not ready)
  ///   may not seek -- the controller sees ownership held and does not reload,
  ///   and just_audio ignores a seek on an unready player. Tapping again once
  ///   it is playing seeks normally.
  /// - If the bar's OWN play button is tapped and its download FAILS,
  ///   `AudioPlayerWidget` leaves `voiceMessageEventId` claimed on the merged
  ///   event with no live player (a pre-existing behavior of that shared
  ///   widget's failure path). A turn tap then sees the merged event "owned"
  ///   and seeks a dead player. This is a rare shared-widget failure-path bug,
  ///   best fixed in `AudioPlayerWidget` (release ownership on failure) as its
  ///   own scoped change rather than worked around here.
  void _onVoiceOwnershipChanged() {
    if (_matrix?.voiceMessageEventId.value != _playbackMergedEventId) {
      _detachObservation();
    }
  }

  /// Idempotent: re-attaching to the player already observed is a no-op, so
  /// [_startMergedPlayer] and every seek/play may call it freely.
  void _attachObservation(AudioPlayer player) {
    if (identical(player, _observedPlayer)) return;
    _detachObservation();
    _observedPlayer = player;
    _observedPositionSub = player.positionStream.listen(
      (position) => _positionBridge?.add(position),
    );
    _observedStateSub = player.playerStateStream.listen(
      (state) => _playingBridge?.add(state.playing),
    );
  }

  void _detachObservation() {
    _observedPositionSub?.cancel();
    _observedPositionSub = null;
    _observedStateSub?.cancel();
    _observedStateSub = null;
    _observedPlayer = null;
  }

  /// Claims the shared player for the merged recording and loads its source
  /// WITHOUT playing -- the controller seeks, then plays (see
  /// [CallPlaybackController.seekToTurn]). Mirrors the app's own reload dance
  /// (`select_mode_buttons.dart` `_reloadAndPlayAudio`, `audio_player.dart`
  /// `_onButtonTap`): dispose whatever is playing, create a fresh player,
  /// claim [MatrixState.voiceMessageEventId] SYNCHRONOUSLY (before the
  /// download await, so [CallPlaybackController]'s ownership recheck sees it),
  /// observe that fresh player, then load.
  ///
  /// A FAILED load RELEASES ownership (disposes the player, clears
  /// `voiceMessageEventId`) rather than returning as if it succeeded: the
  /// controller's post-await recheck then ABORTS the seek/play that would
  /// otherwise run on a source-less player, and a later tap re-enters here to
  /// reload instead of seeking a track that was never set.
  Future<void> _startMergedPlayer(CallAudioMergedRecording row) async {
    final matrix = _matrix;
    if (matrix == null) return;
    matrix.audioPlayer
      ?..stop()
      ..dispose();
    final player = matrix.audioPlayer = AudioPlayer();
    matrix.voiceMessageEventId.value = row.eventId;
    _attachObservation(player);
    try {
      final file = await _mergedRecordingEvent(
        row,
        widget.room,
      ).downloadAndDecryptAttachment();
      if (!mounted || matrix.voiceMessageEventId.value != row.eventId) return;
      await MultiPlatformAudioPlayer(
        audioPlayer: player,
        bytes: file.bytes,
        name: file.name,
        mimeType: file.mimeType,
      ).setAudioSource();
    } catch (e, s) {
      Logs().w('Could not load merged recording for karaoke seek', e, s);
      // Give the shared player back on failure -- but ONLY if the player we
      // created is STILL the current one. `identical`, not just the event id:
      // during a slow failed download the reader may have started a FRESH
      // merged playback (a new [AudioPlayer] under the same merged event id),
      // and disposing THAT would kill a playback that is fine. When it is
      // still ours, clearing ownership is what makes the controller's recheck
      // abort the pending seek and lets the next tap reload.
      if (identical(matrix.audioPlayer, player) &&
          matrix.voiceMessageEventId.value == row.eventId) {
        _detachObservation();
        matrix.audioPlayer?.dispose();
        matrix.audioPlayer = null;
        matrix.voiceMessageEventId.value = null;
      }
    }
  }

  /// Invoked when a turn's time is tapped. Runs the controller's seek
  /// transaction and handles any error HERE, at the tap boundary: the
  /// controller awaits [_seekSharedPlayer], so a seek that throws aborts the
  /// transaction before playback (rather than being swallowed and letting play
  /// proceed on a bad position) -- but its future is fire-and-forget from
  /// [TurnTimeline]'s tap handler, so it must be caught here or it surfaces as
  /// an unhandled async error.
  void _seekToTurnGuarded(int index) {
    final playback = _playback;
    if (playback == null) return;
    unawaited(
      playback
          .seekToTurn(index)
          .catchError(
            (Object e, StackTrace s) => Logs().w('Karaoke seek failed', e, s),
          ),
    );
  }

  Future<void> _seekSharedPlayer(Duration position) async {
    final player = _matrix?.audioPlayer;
    if (player == null) return;
    // Observe the player we are about to seek. The controller only calls this
    // while we own the merged event, so this IS the current merged player
    // (fresh, whether karaoke or the bar created it) -- attaching here is what
    // makes a turn tap follow along even when the bar started the playback.
    // Idempotent, so a karaoke-started seek (already attached) re-attaches for
    // free.
    _attachObservation(player);
    // Deliberately NOT caught here: a seek failure must ABORT the transaction
    // (the controller awaits this before play), and [_seekToTurnGuarded] is
    // where it is logged.
    await player.seek(position);
  }

  Future<void> _playSharedPlayer() async {
    // Start playback and RETURN -- do NOT await the play() future, which
    // just_audio resolves only when playback COMPLETES/pauses/stops, not when
    // it starts. Awaiting it would hold [CallPlaybackController]'s seek lock
    // for the whole playback, so every later turn tap would be ignored. Errors
    // are logged off the fired future instead.
    final player = _matrix?.audioPlayer;
    if (player == null) return;
    unawaited(
      player.play().catchError(
        (Object e, StackTrace s) =>
            Logs().w('Could not play merged recording', e, s),
      ),
    );
  }

  void _disposePlayback() {
    _detachObservation();
    _matrix?.voiceMessageEventId.removeListener(_onVoiceOwnershipChanged);
    _playback?.dispose();
    _playback = null;
    _playbackMergedEventId = null;
    _positionBridge?.close();
    _positionBridge = null;
    _playingBridge?.close();
    _playingBridge = null;
    _matrix = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.callTranscriptTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.close,
          onPressed: Navigator.of(context).pop,
        ),
      ),
      body: FutureBuilder<CallTranscript>(
        future: _transcript,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          // A failed read is its own answer. Showing "no transcript" here
          // would tell the learner nothing was said, when the truth is that
          // we could not find out.
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.cloud_off_outlined,
              text: l10n.callTranscriptLoadFailed,
              action: TextButton(
                onPressed: _retry,
                child: Text(l10n.callTranscriptRetry),
              ),
            );
          }

          final transcript = snapshot.data!;

          // The screen has two shapes and takes the one the data supports.
          //
          // A conversation can only be drawn when EVERY displayed segment of
          // EVERY half carries a position and those positions run forwards.
          // Anything less and we would be ordering some turns against others
          // we cannot place, which reads as a record of who said what when
          // and is a guess. The per-speaker view claims nothing about
          // ordering, so it is what a partly-timed call gets.
          final turns = transcript.timelineEligible
              ? _turnsOf(transcript, l10n)
              : const <CallTurn>[];

          // Worked out here rather than inline, so the list itself stays
          // readable and so this is a value a test can reason about.
          final notes = transcript.halves
              .map((half) => _noteFor(half, l10n))
              .nonNulls
              .toList();

          // Said once, at the top, and only about what is actually DRAWN.
          // The per-speaker view prints no times at all, so no caveat here has
          // anything to explain there -- and a caveat that fires when nothing
          // on screen shows the thing it describes is noise that teaches the
          // reader to skip the next one.
          //
          // The clock one is asked of the TRANSCRIPT rather than of the turns,
          // because it is why they carry no time: the two devices were never
          // put on one clock, so nothing here is measured against the origin
          // every printed time is a difference from.
          final clocksUnreconciled =
              turns.isNotEmpty && !transcript.turnsShareOneClock;
          final approximate = turns.any(
            (turn) => turn.time == TurnTime.atOrBefore,
          );

          // Suppressed when the clocks are the reason, and only then. Every
          // turn is unstated in that case, so this caveat would fire on all of
          // them while blaming a writer that never said how exact its times are
          // -- a confident, specific, wrong diagnosis, and the mistake the rest
          // of this feature is built to avoid. The two are never both shown:
          // the reader asked one question, and gets the operative answer.
          final unstated =
              !clocksUnreconciled &&
              turns.any((turn) => turn.time == TurnTime.unstated);

          // The conversation timeline and the recordings both read the call's
          // audio, and share ONE resolution of it here: the merged "Full call"
          // row is the pinned bar at the top, AND its start is the origin the
          // turns' times are measured from (see [_turnsOf]), so a printed time
          // is a position in that recording. Nested futures, each
          // `data ?? const []`, so the FIRST frame renders with no recording
          // and the first-turn origin -- the transcript is on screen at once,
          // and a slow or failed recordings/merged read never holds it up or
          // takes it down; the bar and the recording-anchored times just
          // appear when the read lands. See `_loadRecordings` / `_loadMerged`.
          return FutureBuilder<List<CallAudioRecording>>(
            future: _recordings,
            builder: (context, recordingsSnapshot) {
              final recordings =
                  recordingsSnapshot.data ?? const <CallAudioRecording>[];
              return FutureBuilder<List<CallAudioMergedRecording>>(
                future: _merged,
                builder: (context, mergedSnapshot) {
                  final mergedList =
                      mergedSnapshot.data ?? const <CallAudioMergedRecording>[];
                  // The ONE merged row to show, or null when there is no merge
                  // or the call switched devices mid-way (more than two halves,
                  // out of v1 scope). Suppression is keyed on the number of
                  // halves the room actually shows, which is why the count
                  // comes from `recordings` rather than the merge's coverage.
                  //
                  // Deferred until BOTH reads are done: `selectMergedRow`'s
                  // half count is only trustworthy once `recordings` has
                  // landed. If the merged read finishes FIRST, the count is
                  // transiently 0, which would show the player -- then the
                  // recordings read landing with >2 halves would SUPPRESS it,
                  // unmounting a possibly-playing merged player mid-frame. Not
                  // showing it until the count is settled keeps the bar on its
                  // shimmer (the load machine is `loading` until both land) and
                  // never exposes then yanks the player.
                  final readsSettled =
                      recordingsSnapshot.connectionState ==
                          ConnectionState.done &&
                      mergedSnapshot.connectionState == ConnectionState.done;
                  final mergedRow = readsSettled
                      ? selectMergedRow(mergedList, recordings.length)
                      : null;

                  // Rebuilt here, not reused from above, because only here is
                  // the merged row known: with one on screen the turn times
                  // anchor to its start; without one they keep the first-turn
                  // origin. Re-anchoring shifts every time by one constant, so
                  // it changes no order and no time KIND -- the eligibility and
                  // the caveats worked out above still hold.
                  //
                  // Stably sorted by [CallTurn.at] HERE, once, so the SAME
                  // ordered list feeds both the playback controller and
                  // [TurnTimeline]. `_turnsOf` returns turns GROUPED by half,
                  // but [TurnTimeline] renders them re-sorted by time
                  // (`_byTime`) and its `activeIndex`/`onSeekTurn` are indices
                  // into THAT rendered order (its class doc's index-space
                  // contract). Handing the controller the unsorted grouped list
                  // would resolve an index against a different order -- an
                  // interleaved conversation would then highlight and seek the
                  // WRONG turn. Sorting once with the same stable rule keeps
                  // the two in lockstep; [TurnTimeline]'s own re-sort of an
                  // already-sorted list is a no-op.
                  final displayTurns = turns.isEmpty
                      ? const <CallTurn>[]
                      : _byCallTime(
                          _turnsOf(
                            transcript,
                            l10n,
                            recordingOriginMs:
                                mergedRow?.content.mergedStartSfuMs,
                            mergedRow: mergedRow,
                            recordings: recordings,
                          ),
                        );

                  // Karaoke: (re)wire, or tear down, the playback controller
                  // for the merged row on screen -- in the SAME build that
                  // hands [TurnTimeline] these same turns, since the
                  // controller's index resolution assumes the two move together
                  // (spec section 4). A no-op teardown when no merged row is
                  // shown, which is what keeps the null-recording screen
                  // rendering EXACTLY as it does today.
                  _syncPlayback(mergedRow, displayTurns);

                  return CustomScrollView(
                    // ONE scrollable for the whole body (spec section 2):
                    // [TurnTimeline]'s auto-scroll watches only its NEAREST
                    // ancestor Scrollable, so the pinned Full-call bar, the
                    // per-device rows and the turns must all live inside this
                    // single one.
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _FullCallBarDelegate(
                          theme: theme,
                          l10n: l10n,
                          state: _loadController.state,
                          mergedPlayer: mergedRow == null
                              ? null
                              : _mergedRecordingPlayer(mergedRow, theme),
                          hasDeviceRows: recordings.isNotEmpty,
                          expanded: _devicesExpanded,
                          onToggle: () => setState(
                            () => _devicesExpanded = !_devicesExpanded,
                          ),
                          onRetry: _retry,
                          textScale: MediaQuery.textScalerOf(context).scale(1),
                        ),
                      ),
                      // The per-device rows, a SEPARATE sliver, collapsed by
                      // default behind the bar's chevron (spec section 2/D3).
                      SliverToBoxAdapter(
                        child: recordings.isEmpty
                            ? const SizedBox.shrink()
                            : AnimatedSize(
                                duration: FluffyThemes.animationDuration,
                                curve: FluffyThemes.animationCurve,
                                alignment: Alignment.topCenter,
                                // Collapse HIDES the rows ([Offstage]) rather
                                // than removing them: the per-device
                                // [AudioPlayerWidget]s stay MOUNTED across
                                // expand/collapse, so a collapse never triggers
                                // their disposal. Removing them would (a) leak
                                // the shared-player listeners a non-owning
                                // AudioPlayerWidget's dispose does not clean up,
                                // and (b) for an actively-playing device row,
                                // clear `voiceMessageEventId` mid-unmount and
                                // make the still-mounted Full-call bar setState
                                // during the locked build phase. Offstage keeps
                                // them alive and un-laid-out (so it still
                                // animates 0<->full and `find` skips them while
                                // collapsed).
                                child: Offstage(
                                  offstage: !_devicesExpanded,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: _recordingsSection(
                                        recordings,
                                        theme,
                                        l10n,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      // The caveats, the conversation and its notes -- NON-LAZY
                      // (a plain [SliverToBoxAdapter], matching today's eager
                      // [ListView] build), so every turn keeps a live
                      // [BuildContext] for karaoke's `Scrollable.ensureVisible`
                      // (spec section 2).
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: _bodySection(
                            transcript: transcript,
                            displayTurns: displayTurns,
                            notes: notes,
                            clocksUnreconciled: clocksUnreconciled,
                            approximate: approximate,
                            unstated: unstated,
                            theme: theme,
                            l10n: l10n,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// The caveats, the conversation (one timeline, or the per-speaker sections
  /// when it cannot be placed) and the notes below it -- everything that used
  /// to sit in the dialog's [ListView] apart from the recording rows, which
  /// have moved to the pinned bar and the expandable per-device sliver above.
  Widget _bodySection({
    required CallTranscript transcript,
    required List<CallTurn> displayTurns,
    required List<String> notes,
    required bool clocksUnreconciled,
    required bool approximate,
    required bool unstated,
    required ThemeData theme,
    required L10n l10n,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One caveat per REASON the read could not conclude, and every reason
        // that applies. They used to share a single line -- the one about a
        // call being too long -- so a room we could not decrypt and a peer we
        // could not name were both explained away as length. That is the
        // failure this whole feature is built against, reached from the only
        // direction still open: not a claim about what somebody said, but a
        // confident, specific, wrong account of why we cannot say.
        //
        // Not one winner. Unlike the clock caveats below, none of these makes
        // another WRONG -- they are independent facts about one read, and
        // suppressing a true one to keep the list short is the same collapse in
        // miniature. Ordered by how much of the screen each explains:
        // encryption accounts for the whole of it, an unnamed participant for a
        // person missing from it, our own ceiling for words missing from a
        // section that is there.
        if (transcript.readLimits.contains(TranscriptReadLimit.roomEncrypted))
          _Caveat(text: l10n.callTranscriptRoomEncrypted),
        if (transcript.readLimits.contains(
          TranscriptReadLimit.participantsUnknown,
        ))
          _Caveat(text: l10n.callTranscriptParticipantsUnknown),
        if (transcript.readLimits.contains(TranscriptReadLimit.readerCeiling))
          _Caveat(text: l10n.callTranscriptStoppedEarly),
        if (clocksUnreconciled)
          _Caveat(text: l10n.callTranscriptUnreconciledClocks),
        if (approximate) _Caveat(text: l10n.callTranscriptApproximateTimes),
        if (unstated) _Caveat(text: l10n.callTranscriptUnstatedTimes),

        if (displayTurns.isNotEmpty)
          // The karaoke wiring is null-safe: [_playback] is non-null only while
          // a merged "Full call" row is shown (see [_syncPlayback]), and while
          // it is null [TurnTimeline] renders EXACTLY as it does today.
          TurnTimeline(
            turns: displayTurns,
            activeIndex: _playback?.activeIndex,
            isPlaying: _playback?.isPlaying,
            onSeekTurn: _playback == null ? null : _seekToTurnGuarded,
          )
        else
          for (final half in transcript.halves)
            _HalfSection(
              half: half,
              name: _nameFor(half.senderId, l10n),
              theme: theme,
              l10n: l10n,
            ),

        // BELOW the conversation, never inside it. Absent, silent and
        // unreadable are facts about a HALF and have no moment they happened
        // at; a place in the timeline would invent one, at an instant nobody
        // spoke. The per-speaker view says these itself, so they are added out
        // here only when the timeline is what is drawn.
        if (displayTurns.isNotEmpty)
          for (final note in notes) _Muted(text: note),
      ],
    );
  }

  /// The call's saved audio, one row per device that wrote a
  /// `pangea.call_audio` half -- or nothing at all when [recordings] is
  /// empty, which includes both "read, and there are none" and "still
  /// reading": the caller does not tell the two apart, and the answer is the
  /// same screen either way. See [_recordings].
  List<Widget> _recordingsSection(
    List<CallAudioRecording> recordings,
    ThemeData theme,
    L10n l10n,
  ) {
    if (recordings.isEmpty) return const [];

    return [
      Text(
        l10n.callTranscriptRecordings,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      for (final recording in recordings) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            // The SAME name the transcript itself uses for this half's
            // sender -- "You" for our own recording, the transcript's own
            // fallback-to-Matrix-displayname for the other side -- so one
            // person is never called two different things on one screen.
            _nameFor(recording.senderId, l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AudioPlayerWidget(
          // `AudioPlayerWidget` downloads and plays through
          // `Event.downloadAndDecryptAttachment`, which refuses any event
          // whose TYPE is not `m.room.message`/`m.sticker` before it looks
          // at content -- `pangea.call_audio` is neither, so the real event
          // cannot be handed to it directly. `_recordingEvent` relabels the
          // same url, mimetype and size this recording already carries as
          // an ordinary `m.audio` message; see its own doc for why that is
          // safe.
          _recordingEvent(recording, widget.room),
          color: theme.colorScheme.primary,
          linkColor: theme.colorScheme.primary,
          fontSize: 14,
          eventId: recording.eventId,
          roomId: widget.room.id,
          senderId: recording.senderId,
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// The merged, full-call recording as one [AudioPlayerWidget], for the
  /// pinned Full-call bar's [CallRecordingsLoadState.ready] state -- fed the
  /// SAME relabel-to-`m.audio` event the halves use (see
  /// [_mergedRecordingEvent]) and keyed by the merged event's OWN id. The
  /// "Full call" label and chevron are the bar's own (see
  /// [_FullCallBarDelegate]), so this is the player alone.
  Widget _mergedRecordingPlayer(
    CallAudioMergedRecording row,
    ThemeData theme,
  ) => AudioPlayerWidget(
    _mergedRecordingEvent(row, widget.room),
    color: theme.colorScheme.primary,
    linkColor: theme.colorScheme.primary,
    fontSize: 14,
    eventId: row.eventId,
    roomId: widget.room.id,
    senderId: row.senderId,
  );

  /// Stably sorts [turns] by [CallTurn.at], ties broken by original index --
  /// the SAME rule [TurnTimeline] applies to `widget.turns` internally (its
  /// private `_byTime`), replicated here because it is private to
  /// `turn_timeline.dart`. The playback controller resolves an active/seek
  /// index against whatever list it is given, and [TurnTimeline] renders (and
  /// so numbers) turns in this sorted order -- feeding the two the same sorted
  /// list is what keeps a given index naming the same turn in both. See the
  /// sort site in [build]. Idempotent against [TurnTimeline]'s own re-sort (a
  /// stable sort of an already-sorted list preserves it).
  static List<CallTurn> _byCallTime(List<CallTurn> turns) {
    final indices = List<int>.generate(turns.length, (i) => i)
      ..sort((a, b) {
        final byTime = turns[a].at.compareTo(turns[b].at);
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    return [for (final i in indices) turns[i]];
  }

  /// Both halves flattened into one column, in the order they were spoken.
  ///
  /// Only ever called once [CallTranscript.timelineEligible] has answered yes,
  /// which is what makes the `!` on each position safe: eligibility IS the
  /// promise that every displayed segment carries one. The widget sorts what
  /// it is given, so this does not.
  ///
  /// The two sides of this seam speak different units, and converting between
  /// them is this method's real job. A segment's `atMs` is an ABSOLUTE Unix
  /// millisecond -- that is what makes two devices comparable at all -- while
  /// a turn's `at` is time ELAPSED, and gets printed as `m:ss`. Handing the
  /// absolute value straight over renders a call that began in 2026 as some
  /// twenty-eight million minutes in.
  ///
  /// The other conversion is between two DEVICES. A position is stamped from
  /// the writing device's own wall clock, and merging both halves by comparing
  /// those absolute values compares two clocks: a constant skew shifts one
  /// speaker's whole half, so the transcript states the wrong person spoke
  /// first. Each half's [CallTranscript.clockShiftFor] moves it onto the one
  /// clock both devices observed -- the SFU's -- before anything is ordered.
  ///
  /// The shift is applied HERE and nothing on the wire is rewritten. What a
  /// device asserted stays what it asserted; putting two halves side by side
  /// is a reader's problem, which is also why no migration is needed for the
  /// calls already in people's rooms.
  /// [recordingOriginMs] is the merged "Full call" recording's start on the
  /// SFU clock ([CallAudioMergedContent.mergedStartSfuMs]), passed when such a
  /// recording is on screen so the turn times are measured from it and a
  /// printed time is a position in that recording. Null -- no merge, or a merge
  /// that carries no start -- keeps the origin at the first turn placed.
  ///
  /// [mergedRow] and [recordings] answer a DIFFERENT question from
  /// [recordingOriginMs]: not where the printed clock starts, but which turns
  /// may carry a recording-timeline window at all (see [CallTurn.audioStartMs]).
  /// That window is display-only and never feeds back into [CallTurn.at] or
  /// the standalone order, so it is computed from its own inputs rather than
  /// reusing [recordingOriginMs] -- [recordingOriginMs] is REFUSED (falls back
  /// to the first-turn origin) whenever the recording claims to start after
  /// somebody already spoke, a rule that protects the printed clock and must
  /// not also silently borrow a substitute origin for the window; the window
  /// has its own clamp for exactly that case instead. [recordings] is the same
  /// per-device `pangea.call_audio` list the "Recordings" rows below are built
  /// from -- needed because a [TranscriptHalf] carries no event id of its own
  /// once `_assembleDevices` (`transcript_assembly.dart`) has folded one
  /// sender's devices into it, so the only way to ask "is this half's audio
  /// part of the merge" is by the sender's RECORDING event id(s), read off
  /// this list, against [CallAudioMergedContent.sourceEventIds] -- ALL of
  /// them, when a sender has more than one; see the coverage check below for
  /// why.
  List<CallTurn> _turnsOf(
    CallTranscript transcript,
    L10n l10n, {
    int? recordingOriginMs,
    CallAudioMergedRecording? mergedRow,
    List<CallAudioRecording> recordings = const [],
  }) {
    final me = widget.room.client.userID;

    // Worked out once per HALF, not once per segment: one constant per half is
    // the whole correction, and that is also what keeps the render gate sound.
    // `timelineEligible` was answered on the raw positions, and subtracting a
    // single constant from all of a half's positions cannot reorder them, so a
    // half that was non-decreasing before the shift is non-decreasing after.
    final placed = [
      for (final half in transcript.halves)
        (half: half, shift: transcript.clockShiftFor(half)),
    ];

    // Asked once for the whole transcript, because that is its scope: a turn's
    // time is a difference against an origin taken across BOTH halves, so
    // whether it can be vouched for is a fact about the call, not about the
    // segment or the half it came from.
    final onOneClock = transcript.turnsShareOneClock;

    // The moment each segment is PLACED at, which for one that knows only its
    // chunk is the END of that chunk's audio rather than the estimate inside
    // it. That is the whole fix: placed at its estimate, a turn spoken forty
    // seconds into a chunk renders at the chunk's start and jumps ahead of the
    // other speaker's correctly timed question; placed at the latest moment it
    // could have been, it cannot render earlier than it was said.
    final keys = [
      for (final entry in placed)
        for (final segment in entry.half.segments)
          segment.orderKeyMs! - entry.shift,
    ];
    if (keys.isEmpty) return const [];

    // The keys we are prepared to STAND BEHIND: the ones from a half whose
    // writer says which of its positions are exact. Both kinds from such a half
    // qualify -- an exact key is a word's own start and an approximate one is
    // the end of a chunk of audio we captured, and both are real instants on
    // that device's clock.
    final vouched = [
      for (final entry in placed)
        if (entry.half.positionsMarked)
          for (final segment in entry.half.segments)
            segment.orderKeyMs! - entry.shift,
    ];

    // The earliest turn ANYWHERE in the transcript, not the earliest in each
    // half: the whole point is that one clock runs behind both columns, and
    // per-half origins would restart it for the second speaker.
    //
    // Taken over the VOUCHED keys, because every time on screen is a difference
    // from this one number and a difference is only as sound as both its ends.
    // An unmarked writer's position is a bare assertion -- it may be a word's
    // moment or a whole chunk's, and it never said which -- so letting one open
    // the transcript would have made every OTHER turn's plain `m:ss` an exact
    // offset from a number we had just told the reader we could not vouch for.
    // The stamp would look exact and be off by however wrong that half was.
    //
    // Falling back to every key when nothing is vouched costs nothing: a
    // transcript with no marked half prints no times at all, so the origin then
    // only orders turns, and ordering by an unvouched position is what such a
    // call has anyway.
    //
    // A turn from an unmarked half can therefore sit BEFORE the origin and take
    // a negative elapsed value. That is deliberate and it never reaches the
    // screen: such a turn prints no time, and a negative sorts it first, which
    // is where its own device put it.
    //
    // This origin is the first turn PLACED, not the moment the call connected,
    // and the two are different whenever a call opens with silence. Nothing on
    // the wire says when capture began -- each segment carries only its own
    // absolute time -- so the connect moment cannot be recovered here, and this
    // clock can therefore read a little short of the duration on the call card.
    // See `CallTurn.at`, which states the same contract.
    final firstPlaced = (vouched.isNotEmpty ? vouched : keys).reduce(
      (a, b) => a < b ? a : b,
    );

    // The origin every printed time is a difference from. Normally the first
    // turn placed, above -- but when a merged "Full call" recording is drawn,
    // its own start is used so a turn's time is where that turn sits in the
    // recording, and reading a time then scrubbing the player to it lands on
    // the same words. Both are on the SFU clock -- a segment's `orderKeyMs`
    // less its half's `shift` is on the SFU's clock, and so is
    // [CallAudioMergedContent.mergedStartSfuMs] -- so the difference is a real
    // elapsed. Only an origin AT OR BEFORE the first turn is taken: the
    // recording begins before anyone speaks, so a sound start is <= it; a
    // greater one (a foreign or malformed value) would push a real turn to a
    // negative time, so it is refused in favour of the first-turn origin.
    final start =
        (recordingOriginMs != null && recordingOriginMs <= firstPlaced)
        ? recordingOriginMs
        : firstPlaced;

    // A SEPARATE origin from [start] above, deliberately, even though both
    // read `mergedRow.content.mergedStartSfuMs` in production. [start] is
    // REFUSED (falls back to [firstPlaced]) whenever the recording claims to
    // begin after the first turn was placed -- a rule that protects the
    // PRINTED elapsed time and the standalone ORDER, both governed and
    // neither this window may perturb. The window below has no such
    // fallback to protect, and does not need [start]'s: a too-late origin
    // here simply clamps every window to its floor (see the loop below)
    // rather than silently borrowing an origin that was refused for an
    // unrelated reason.
    final windowOriginMs = mergedRow?.content.mergedStartSfuMs;
    final windowDurationMs = mergedRow?.content.durationMs;

    // Which senders' audio this merge actually covers. A `TranscriptHalf`
    // carries no event id of its own -- `_assembleDevices` folds however many
    // of one sender's `pangea.call_transcript` events into one half and keeps
    // none of their ids -- so the only id this reader can compare against
    // [CallAudioMergedContent.sourceEventIds] is that sender's
    // `pangea.call_audio` RECORDING event(s), read off [recordings]. A sender
    // with no recording at all is not covered, obviously; a sender with one
    // or more recordings is covered only when EVERY one of them is named by
    // this merge.
    //
    // SENDER-level, not event-level -- and deliberately conservative rather
    // than precise, CLOSED here rather than deferred. A sender can produce
    // more than one `pangea.call_audio` recording for one call -- two
    // devices, a capture drop-and-rejoin, or the ordinary convergence race
    // `CaptureElection`'s own doc describes (two of one account's devices can
    // each start capturing before their rosters converge, one then stopping)
    // -- and when this merge names only SOME of them, there is no way from
    // here to tell which of that sender's SEGMENTS came from the named
    // recording and which from the excluded one: `_assembleDevices` has
    // already folded a sender's several recordings into one half before this
    // method ever sees it, and kept no per-segment recording id to check
    // instead. Requiring EVERY recording of a sender to be named, rather than
    // ANY, is what keeps that unknown from ever reaching the screen: such a
    // sender gets NO window on ANY of their turns rather than a window that
    // might point at audio never mixed in -- no karaoke rather than wrong
    // karaoke. The ordinary two-party case (each sender exactly one
    // recording, both named) is unaffected: "every recording of one is
    // named" and "the one recording is named" are the same statement.
    //
    // A FUTURE per-segment, per-recording-precise coverage could still narrow
    // this to the exact stretch each recording actually contributed -- it
    // needs identity this layer does not carry, and belongs with the
    // >2-halves device-switch merge work, pangeachat/client#8878, which needs
    // the same identity. This is not that: it is the conservative rule that
    // makes today's coverage check HONEST rather than merely narrower than it
    // claims to be.
    final recordingsBySender = <String, List<CallAudioRecording>>{};
    for (final recording in recordings) {
      recordingsBySender
          .putIfAbsent(recording.senderId, () => [])
          .add(recording);
    }
    final mergeCoveredSenderIds = mergedRow == null
        ? const <String>{}
        : <String>{
            for (final entry in recordingsBySender.entries)
              if (entry.value.every(
                (recording) => mergedRow.content.sourceEventIds.contains(
                  recording.eventId,
                ),
              ))
                entry.key,
          };

    // Whether [half]'s turns may carry a recording-timeline window at all.
    // Every term is a reason the window would otherwise show a position
    // nothing backs: no recording on screen, or one that never declared its
    // own start; the transcript's two clocks never reconciled (asked exactly
    // as the printed-time caveat above asks it); THIS half's own clock never
    // compared to the SFU's, asked separately from `onOneClock` rather than
    // folded into it -- [CallTranscript.clockShiftFor] answers zero for both
    // "not reconciled" and "this half has no anchor", and treating either
    // zero as a real shift would place a window on a clock this half never
    // read; or this sender's audio simply is not part of the mix.
    bool windowEligible(TranscriptHalf half) =>
        windowOriginMs != null &&
        windowDurationMs != null &&
        onOneClock &&
        half.clockAnchor != null &&
        mergeCoveredSenderIds.contains(half.senderId);

    final turns = <CallTurn>[];
    // Shared across every half, deliberately: [_turnContentKey] already
    // embeds [senderId], so two different senders' segments never share a
    // content key and this one map naturally scopes each sender's own
    // ordinals without having to be reset per half.
    final identityOrdinals = <String, int>{};
    for (final entry in placed) {
      final eligible = windowEligible(entry.half);
      for (final segment in entry.half.segments) {
        // [audioStartMs] is this segment's own placement -- [atMs], never
        // [orderKeyMs] -- on the recording's clock: a precise segment's
        // window is a single instant ([spanMs] null makes [orderKeyMs] equal
        // [atMs] already), and an approximate one's window OPENS at the
        // earliest evidence of speech in its chunk, exactly where [atMs]
        // already places it for the same reason `_timeKindOf` reads it.
        // [audioEndMs] is [orderKeyMs] on that same clock: the end of the
        // window an approximate turn's estimate could fall anywhere in, and
        // equal to [audioStartMs] for a precise one. Neither ever substitutes
        // one for the other -- that substitution is exactly the defect
        // [orderKeyMs] exists to fix for [at] above, reintroduced here for a
        // different timeline if the two were ever swapped.
        int? audioStartMs;
        int? audioEndMs;
        if (eligible) {
          final rawStart = segment.atMs! - entry.shift - windowOriginMs!;
          audioStartMs = rawStart.clamp(0, windowDurationMs!);
          final rawEnd = segment.orderKeyMs! - entry.shift - windowOriginMs;
          audioEndMs = rawEnd.clamp(audioStartMs, windowDurationMs);
        }

        turns.add(
          CallTurn(
            senderId: entry.half.senderId,
            // The speaker's OWN name, not what the header will print. The
            // widget substitutes "You" for your own turns itself, and the
            // avatar needs the real one: handing it the label drew every
            // self-turn's avatar as the initial of the word "You".
            name: _displayNameOf(entry.half.senderId),
            avatarUrl: _avatarOf(entry.half.senderId),
            isMe: entry.half.senderId == me,
            at: Duration(
              milliseconds: segment.orderKeyMs! - entry.shift - start,
            ),
            time: _timeKindOf(segment, entry.half, onOneClock),
            text: segment.text,
            langCode: entry.half.langCode,
            audioStartMs: audioStartMs,
            audioEndMs: audioEndMs,
            identityKey: _turnIdentityKey(
              entry.half.senderId,
              segment,
              identityOrdinals,
            ),
          ),
        );
      }
    }
    return turns;
  }

  /// A [CallTurn.identityKey] for [segment] within [senderId]'s (already
  /// device-merged) half.
  ///
  /// Built from [segment]'s own content rather than its position in
  /// [TranscriptHalf.segments] -- which is what lets it survive a rebuild
  /// that inserts, removes or reorders a SIBLING segment in the same half.
  /// `atMs` is this segment's own absolute placement, untouched by anything
  /// else the half comes to contain, so the same spoken moment keeps the
  /// same key regardless of where it ends up in the list. A plain index
  /// cannot promise that: `_assembleDevices` (`transcript_assembly.dart`)
  /// PLACES a multi-device half's segments by position rather than
  /// concatenating them, so a second device's half joining the same sender
  /// -- a late recording finishing its own read after the dialog is already
  /// open -- can insert a new segment ahead of ones already on screen and
  /// shift their index, which would otherwise change their key and break a
  /// [GlobalKey] keyed on it (karaoke auto-scroll/highlight, #8797's own
  /// follow-on work).
  ///
  /// [senderId] is already unique across [CallTranscript.halves] --
  /// `assembleTranscript` groups every candidate into a half by a `Set` of
  /// sender ids, so no two halves in one transcript ever share one -- and
  /// `atMs` is unique WITHIN one half in the ordinary case. Two segments can
  /// still share an instant: one malformed chunk's shared fallback offset is
  /// stamped on every segment cut from it (see `_speechBeganAt` in
  /// `transcript_segments.dart`). [spanMs] -- null for a precise segment, the
  /// chunk's own delta for an approximate one -- and the segment's own
  /// [TranscriptSegment.text] break that tie before falling back to an
  /// accident.
  ///
  /// CONTENT alone is still not quite injective: two segments can share
  /// senderId, atMs, spanMs AND text all at once -- an approximate "yes", a
  /// pause, then another "yes" the writer estimated to the identical chunk,
  /// with nothing on the wire to tell the two apart. [ordinals] is what
  /// closes that gap. It counts occurrences PER content key -- the same
  /// string this method would otherwise return outright -- across every
  /// segment already keyed in this call to [_turnsOf], and the count is
  /// appended as one final field: the first segment with any given content
  /// key is `#0`, a genuine duplicate is `#1`, a third is `#2`, and so on.
  /// This is deliberately NOT a plain index into the half's segment list --
  /// see the doc above for why a bare position breaks a [GlobalKey] -- it is
  /// a position WITHIN one content-key GROUP, so it only moves when a
  /// SIBLING with the identical content is inserted ahead of it, never when
  /// an unrelated segment is: a later segment with fresh content leaves
  /// every existing key exactly as it was, and a later segment that happens
  /// to repeat an earlier one's content becomes the next ordinal in that
  /// group rather than colliding with it.
  ///
  /// The text is embedded VERBATIM, never hashed. A hash is lossy by
  /// construction -- two DIFFERENT texts can share one `hashCode`, which
  /// would silently reintroduce the same collision this key exists to rule
  /// out, only rarer and undetectable. `#` cannot appear in [senderId] (a
  /// Matrix user id) or in a formatted integer, so it never creates an
  /// ambiguous boundary among the first three fields. The ordinal is placed
  /// LAST, after the text, for the same reason the text used to be last:
  /// nothing reads this key back apart again, it is compared only for
  /// equality, and a `#` inside the text can only ever be part of the text
  /// because the ordinal that follows it is itself pure digits with no `#`
  /// of its own -- so reading from the end, the LAST `#` in the whole string
  /// is always this method's own final separator, whatever the text
  /// contains.
  ///
  /// [spanMs] is interpolated directly rather than defaulted to a sentinel
  /// integer: Dart prints a null `int?` as the literal string `null`, which
  /// no `int.toString()` output can ever equal, so a precise segment
  /// (`spanMs` absent) can never collide with an approximate one however
  /// that approximate segment's own span happens to be signed -- this holds
  /// without having to lean on [TranscriptSegment.spanMs] never being
  /// negative in practice.
  String _turnIdentityKey(
    String senderId,
    TranscriptSegment segment,
    Map<String, int> ordinals,
  ) {
    final contentKey = _turnContentKey(senderId, segment);
    final ordinal = ordinals.update(
      contentKey,
      (occurrences) => occurrences + 1,
      ifAbsent: () => 0,
    );
    return '$contentKey#$ordinal';
  }

  /// The content-derived portion of [_turnIdentityKey], broken out so the
  /// per-content-key ordinal counter there can group segments by this exact
  /// string without duplicating its derivation.
  String _turnContentKey(String senderId, TranscriptSegment segment) =>
      '$senderId#${segment.atMs!}#${segment.spanMs}#${segment.text}';

  /// What may be said about one segment's moment.
  ///
  /// The MARKER decides first, and it decides everything. A half that marks its
  /// positions has asserted which of them are a word's and which are a chunk's;
  /// a half that does not has asserted nothing, and NOTHING it carries can be
  /// labelled -- not its bare positions, and not its spans either. A "by T"
  /// from such a half would be a bound this app vouched for, resting on a
  /// position its own writer never characterised.
  ///
  /// The span is still honoured for ORDERING on an unmarked half, in
  /// [_turnsOf]. That is a different question with a different answer: a span
  /// can only move a turn LATER, so acting on one cannot invent precision, and
  /// a turn placed later than its device asked for is the safe direction. What
  /// may be SAID about the result is what the marker governs.
  ///
  /// The CLOCK decides before the marker, and it decides for the whole call.
  /// The marker is a claim by one writer about its own positions; it says
  /// nothing about whether that writer's clock was ever compared to the other
  /// speaker's. Our own writer sets `positions_marked` on every half while its
  /// anchor stays nullable -- `ClockAnchor.of` legitimately returns null when
  /// LiveKit's `joinedAt` is the unstamped protocol default of zero -- so the
  /// combination that defeats the marker is one we PRODUCE, not an exotic
  /// foreign client. Without this, two halves that were never reconciled printed
  /// plain `m:ss` while sitting on clocks that may disagree by minutes.
  ///
  /// Not corrected, and deliberately not: shifting one half by an offset
  /// measured for only one of them might invert an order that was already
  /// right, and we cannot say which. That trade is defensible. Presenting the
  /// uncorrected result as a time this app vouches for is not, and the choice
  /// between them is the same one already made for an unvouched origin: show
  /// no number rather than one that looks exact and is off by however far the
  /// two clocks stand apart.
  TurnTime _timeKindOf(
    TranscriptSegment segment,
    TranscriptHalf half,
    bool onOneClock,
  ) {
    if (!onOneClock) return TurnTime.unstated;
    if (!half.positionsMarked) return TurnTime.unstated;
    return segment.positionIsApproximate ? TurnTime.atOrBefore : TurnTime.exact;
  }

  /// What still needs saying about a half once its words are in the timeline,
  /// or null when the half is a clean record and needs nothing.
  String? _noteFor(TranscriptHalf half, L10n l10n) {
    final name = _nameFor(half.senderId, l10n);
    if (half.state == HalfState.absent) return l10n.callTranscriptNone(name);
    if (half.segments.isEmpty) return emptyHalfNote(half, name, l10n);
    if (half.state == HalfState.incomplete) {
      return l10n.callTranscriptPartial(name);
    }
    return null;
  }

  String _nameFor(String userId, L10n l10n) {
    if (userId == widget.room.client.userID) return l10n.you;
    return _displayNameOf(userId);
  }

  /// What this person is actually called, self included.
  ///
  /// Separate from [_nameFor] because the notes below the transcript address
  /// the reader ("You said nothing") while an avatar has to be the person's
  /// own, and one function cannot answer both.
  String _displayNameOf(String userId) =>
      widget.room.unsafeGetUserFromMemoryOrFallback(userId).calcDisplayname();

  Uri? _avatarOf(String userId) =>
      widget.room.unsafeGetUserFromMemoryOrFallback(userId).avatarUrl;
}

/// Presents one saved recording as an ordinary Matrix voice message, so
/// [AudioPlayerWidget] -- built to download and play an `m.room.message` of
/// type `m.audio` -- can do that for a `pangea.call_audio` half without
/// changing anything about the widget itself.
///
/// `pangea.call_audio`'s content is not that shape, and the mismatch is not
/// cosmetic. [CallAudioContent.toJson] writes [url], [mimetype] and [size]
/// at the TOP level of a `pangea.call_audio` EVENT, while the SDK's own
/// `Event.downloadAndDecryptAttachment` -- what the player calls on tap --
/// refuses any event whose TYPE is not `m.room.message` or `m.sticker`
/// before it ever looks at content:
/// ```
/// if (![EventTypes.Message, EventTypes.Sticker].contains(type)) {
///   throw ("This event has the type '$type' and so it can't contain an
///   attachment.");
/// }
/// ```
/// Handing the real event to the player would therefore throw on every tap,
/// caught by the player's own `catch` and surfaced as a download-failed
/// snackbar -- a control that renders and never plays.
///
/// So this relabels rather than reinvents. The mxc [url] this returns is the
/// SAME url the recorder already uploaded to and the writer already
/// published -- nothing is re-uploaded, re-sent, or copied -- and the
/// `info.size`/`info.mimetype` the player reads to size and decode the
/// download are the same facts [CallAudioContent] already carries, just
/// nested where a normal voice message keeps them. The room is unencrypted
/// (see [CallAudioContent]'s own docs), so there is no `file` block to
/// forge and nothing here decrypts anything either.
Event _recordingEvent(CallAudioRecording recording, Room room) => Event(
  eventId: recording.eventId,
  senderId: recording.senderId,
  originServerTs: recording.originServerTs,
  room: room,
  type: EventTypes.Message,
  content: {
    'msgtype': MessageTypes.Audio,
    'body': 'call_audio.wav',
    'url': recording.content.url,
    'info': {
      'mimetype': recording.content.mimetype,
      'size': recording.content.size,
      'duration': recording.content.durationMs,
    },
  },
);

/// The merged, full-call recording presented as an ordinary Matrix voice
/// message, so [AudioPlayerWidget] can play a `pangea.call_audio_merged` event
/// on the same terms [_recordingEvent] lets it play a `pangea.call_audio` half.
///
/// The reasoning is [_recordingEvent]'s exactly -- see it in full. The player's
/// `Event.downloadAndDecryptAttachment` refuses any event whose TYPE is not
/// `m.room.message`/`m.sticker`, and `pangea.call_audio_merged` is neither, so
/// handing the real event to the player throws on every tap. This relabels the
/// SAME url, mimetype and size [CallAudioMergedContent] already carries as an
/// ordinary `m.audio` message -- nothing is re-uploaded, and the room is
/// unencrypted (see [CallAudioMergedContent]'s own docs), so there is no `file`
/// block to forge and nothing here decrypts anything either.
Event _mergedRecordingEvent(CallAudioMergedRecording recording, Room room) =>
    Event(
      eventId: recording.eventId,
      senderId: recording.senderId,
      originServerTs: recording.originServerTs,
      room: room,
      type: EventTypes.Message,
      content: {
        'msgtype': MessageTypes.Audio,
        'body': 'call_audio.wav',
        'url': recording.content.url,
        'info': {
          'mimetype': recording.content.mimetype,
          'size': recording.content.size,
          'duration': recording.content.durationMs,
        },
      },
    );

/// What to say about a half that carries no words.
///
/// ONE function for both shapes of this screen. The per-speaker sections and
/// the notes under the timeline ask exactly this question and each carried its
/// own copy of the ladder, which is a second place for a cause to be added to
/// only one of them.
///
/// **A `switch` over [HalfIssue] with no default, deliberately.** As a chain of
/// `if`s with a fallthrough this was a second inventory of the causes, kept by
/// hand beside the enum -- so a cause could be added to [HalfIssue], ranked in
/// [TranscriptHalf.issue], and never reach a sentence: `audioDroppedAtCapture`
/// and `audioHeldByAnotherDevice` both landed that way and both told the
/// learner their words could not be READ, about audio no reader ever saw. A
/// non-exhaustive switch does not compile, so the next cause added to the enum
/// cannot be silently absent from this screen: somebody has to decide what it
/// says.
///
/// Every branch below the first asks [TranscriptHalf.issue] rather than
/// re-deriving anything, so the sentence a person reads and the line a bug
/// report is diagnosed from can never name different reasons for the same half.
///
/// Public only so a test can hold it against every [HalfIssue] at once; nothing
/// outside this file calls it.
@visibleForTesting
String emptyHalfNote(TranscriptHalf half, String name, L10n l10n) {
  // Asked of the half rather than of [TranscriptHalf.issue], and ahead of it.
  // "They said nothing" is a definite claim about a person, the only thing
  // separating it from "we could not find out" is which STATE an empty half is
  // in, and that distinction is too easy to invert at each site that needs it.
  // A silent half is a clean record, so its issue is `none` -- or a fact about
  // the read, like an unknown participant list, which does not stop it having
  // been silence.
  if (half.saidNothing) return l10n.callTranscriptSaidNothing(name);

  return switch (half.issue) {
    // An empty half whose audio our own detector held back was never read by
    // anything, so neither silence nor a failure to read names its cause.
    HalfIssue.audioSuppressedLocally => l10n.callTranscriptNoSpeechDetected(
      name,
    ),

    // The writer had words and dropped every one of them to fit the event under
    // the server's size limit. Nothing about that is a reading failure: the
    // words existed, we read what arrived exactly as it was sent, and "nothing
    // could be read from what they said" points whoever chases it at the wrong
    // device. Taken from `issue` rather than from `accounting.truncated`,
    // because OUR own trim sets that flag too -- and that is `tooLongToRead`, a
    // different device and a different answer.
    HalfIssue.tooLongToSend => l10n.callTranscriptTooLongToSend(name),

    // Four failures of the WRITING device, each named as its own. All four
    // otherwise fall through to "nothing could be read", which points whoever
    // chases it at the reader -- and for the last two that is not merely vague
    // but wrong, because nothing ever reached a reader to fail at.
    HalfIssue.microphoneRefused => l10n.callTranscriptMicrophoneRefused(name),
    HalfIssue.audioLost => l10n.callTranscriptAudioLost(name),
    HalfIssue.audioDroppedAtCapture => l10n.callTranscriptAudioDropped(name),
    HalfIssue.audioHeldByAnotherDevice => l10n.callTranscriptHeldByOtherDevice(
      name,
    ),

    // Reachable here only in one narrow shape -- an empty half whose chunks
    // WERE transcribed and came back with no words, and which also deferred a
    // stretch no sibling's half holds. `audioHeldByAnotherDevice` above answers
    // every other empty half that deferred anything. Its ordinary home is a
    // half that still carries words, where the note under the timeline says
    // part of it may be missing; this is the sentence for the case where there
    // is nothing left to say that about.
    //
    // KNOWN COPY DRIFT, recorded rather than papered over. This sentence says
    // "nothing from that device arrived", which was the whole of the condition
    // while a sibling WRITING excused a discard. The condition is now
    // containment -- no half of theirs states it held that stretch -- and a
    // sibling that wrote a half of some other stretch reaches this branch with
    // its half very much here. The conclusion the sentence draws is still true
    // and it is the part a learner acts on; the middle clause is narrower than
    // what it now describes. Re-wording it is a translation across every locale
    // and is the owner's call, so it is flagged rather than made here.
    HalfIssue.audioLeftToADeviceThatDidNotHoldIt =>
      l10n.callTranscriptDeviceNeverWrote(name),

    // Everything else, and only here a true statement: something of theirs was
    // there and WE are the ones who could not make a record of it. Listed one
    // by one rather than under a wildcard, because a wildcard is exactly the
    // fallthrough this switch replaced -- it would swallow the next cause added
    // to the enum in silence.
    //
    // `neverWritten` is unreachable from both callers, which check for an
    // absent half first; it is answered rather than excepted because a reader
    // of this function should not have to prove that to know what it returns.
    HalfIssue.none ||
    HalfIssue.neverWritten ||
    HalfIssue.tooLongToRead ||
    HalfIssue.participantsUnknown ||
    HalfIssue.contentUnreadable ||
    HalfIssue.drainAbandoned ||
    HalfIssue.writerSaidNothing ||
    HalfIssue.accountingImpossible ||
    HalfIssue.timesApproximate ||
    HalfIssue.timesUnstated ||
    HalfIssue.assembledFromSeveralDevices ||
    HalfIssue.couldNotRead => l10n.callTranscriptNothingRead(name),
  };
}

/// One speaker's side of the call.
///
/// Per speaker, not interleaved. What this view is for is a call whose turns
/// cannot all be placed: the two halves are recorded independently on two
/// devices, and without a position on every displayed segment, ordering one
/// against the other would be a guess presented as a record of who said what
/// when. A call that CAN be placed is drawn as one conversation instead, with
/// each half moved onto the SFU's clock first.
class _HalfSection extends StatelessWidget {
  final TranscriptHalf half;
  final String name;
  final ThemeData theme;
  final L10n l10n;

  const _HalfSection({
    required this.half,
    required this.name,
    required this.theme,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ..._body(),
        ],
      ),
    );
  }

  List<Widget> _body() {
    // ABSENT is a statement about a half that was never written, and it is
    // only reachable from a read that reached the end. It is NOT "they were
    // silent": a silent speaker still writes an empty half, and that case is
    // the one below.
    if (half.state == HalfState.absent) {
      return [_Muted(text: l10n.callTranscriptNone(name))];
    }

    // Shared with the notes drawn under the timeline, because it is the same
    // question. Two copies of this ladder is how the writer-side packing loss
    // came to read as a reading failure in the first place -- there is one
    // ladder now, and adding a cause to it reaches both shapes of the screen.
    if (half.segments.isEmpty) {
      return [_Muted(text: emptyHalfNote(half, name, l10n))];
    }

    return [
      for (final segment in half.segments)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TranscriptTokens(
            text: segment.text,
            langCode: half.langCode,
            style: theme.textTheme.bodyMedium,
          ),
        ),

      // Said after the words, not instead of them: what we have is worth
      // reading, and the caveat is about what may be missing from it.
      if (half.state == HalfState.incomplete) ...[
        const SizedBox(height: 4),
        _Caveat(text: l10n.callTranscriptPartial(name)),
      ],
    ];
  }
}

class _Muted extends StatelessWidget {
  final String text;

  const _Muted({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  final String text;

  const _Caveat({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

/// The pinned "Full call" slot (spec section 2, item 1): always present, its
/// content driven by the [CallRecordingsLoadController]'s [state] -- the
/// merged player when ready, a shimmer while loading or preparing, a compact
/// note (with retry when the grace has elapsed) when there is none.
///
/// A custom delegate rather than a `SliverAppBar`: a 56px app bar cannot hold
/// a 40-bar audio player. Opaque [ColorScheme.surface], so the turns scroll
/// UNDER it. The extent is scale-aware ([_base] scaled by the text scale,
/// clamped) so the player and label do not clip at large text sizes; the
/// "Full call" label ellipsises rather than wrapping.
class _FullCallBarDelegate extends SliverPersistentHeaderDelegate {
  _FullCallBarDelegate({
    required this.theme,
    required this.l10n,
    required this.state,
    required this.mergedPlayer,
    required this.hasDeviceRows,
    required this.expanded,
    required this.onToggle,
    required this.onRetry,
    required this.textScale,
  });

  final ThemeData theme;
  final L10n l10n;
  final ValueListenable<CallRecordingsLoadState> state;

  /// The merged recording's player, pre-built by the state, or null when no
  /// merged row is on screen (so [CallRecordingsLoadState.ready] can never be
  /// reached without one).
  final Widget? mergedPlayer;

  /// Whether there are per-device rows to reveal -- the chevron is shown only
  /// then (a call with zero halves has nothing to toggle).
  final bool hasDeviceRows;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRetry;
  final double textScale;

  /// The bar's height at a text scale of 1: the "Full call" label, a small
  /// gap, and the tallest content (the ~60px player), plus vertical padding.
  static const double _base = 112;

  double get _extent => (_base * textScale).clamp(_base, 260.0);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // [SizedBox.expand] so the child FILLS the declared [_extent]: a pinned
    // persistent header's geometry is invalid ("layoutExtent exceeds
    // paintExtent") if the child paints shorter than min/maxExtent, which a
    // bare content Column (sized to its ~60px player) does. The content itself
    // stays top-aligned inside; the slack is the bar's own breathing room.
    return SizedBox.expand(
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: ValueListenableBuilder<CallRecordingsLoadState>(
            valueListenable: state,
            builder: (context, loadState, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.callTranscriptFullCall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(child: _content(loadState)),
                    if (hasDeviceRows)
                      IconButton(
                        onPressed: onToggle,
                        tooltip: l10n.callTranscriptRecordings,
                        icon: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(CallRecordingsLoadState loadState) {
    // The PLAYER is shown whenever there IS a merged row to play, driven by
    // the live [mergedPlayer] rather than the machine's `ready` -- the machine
    // latches `ready` terminally, but the selectable merged row can still go
    // away (a >2-half device switch is suppressed, a re-read flakes), and
    // rendering off the actual row keeps the two from diverging into an empty
    // "ready" slot. The machine's state only decides what to show when there
    // is NO player: a shimmer while still resolving, a note otherwise.
    final player = mergedPlayer;
    if (player != null) return player;
    switch (loadState) {
      case CallRecordingsLoadState.loading:
        return _shimmer(null);
      case CallRecordingsLoadState.pendingMerge:
        return _shimmer(l10n.callTranscriptPreparingRecording);
      case CallRecordingsLoadState.none:
        return _note(retry: false);
      case CallRecordingsLoadState.unavailable:
      // `ready` with no player: the merge that latched it is no longer the
      // selectable row (suppressed, or a flaky re-read), so show the note with
      // a retry rather than a slot that can never fill.
      case CallRecordingsLoadState.ready:
        return _note(retry: true);
    }
  }

  Widget _shimmer(String? caption) {
    final child = ShimmerBox(
      baseColor: theme.colorScheme.surfaceContainerHigh,
      highlightColor: theme.colorScheme.surfaceContainerHighest,
      width: double.infinity,
      height: 40,
      borderRadius: BorderRadius.circular(12),
    );
    if (caption == null) return child;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 6),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _note({required bool retry}) {
    return Row(
      children: [
        Icon(
          Icons.mic_off_outlined,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.callTranscriptNoRecording,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (retry)
          TextButton(onPressed: onRetry, child: Text(l10n.callTranscriptRetry)),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _FullCallBarDelegate old) =>
      // A fresh delegate is built every frame with new closures/data, so this
      // is conservatively always true; the header is cheap and its own
      // ValueListenableBuilder is what actually re-renders on a state change.
      true;
}
