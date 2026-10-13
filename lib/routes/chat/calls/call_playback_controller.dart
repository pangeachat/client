import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';

/// Owns karaoke sync for the "Full call" recording: which [CallTurn] is
/// active right now, and the tap-to-seek transaction that moves playback to
/// one. See `docs/handoff/2026-09-10-recordings-ui-redesign-spec.md` section
/// 4 for the design this implements. (That section's disposal line reads
/// "cancel all subscriptions + THE TIMER" -- this controller creates no
/// timer; that phrase appears to carry over from the loading machine's grace
/// timer, a different agent's file entirely.)
///
/// Deliberately independent of `just_audio` and of `MatrixState`: every
/// dependency on the real shared player arrives as a plain [Stream],
/// [ValueListenable], or callback, so this can be driven by fakes in a unit
/// test and wired to `matrix.audioPlayer` / `matrix.voiceMessageEventId` with
/// a one-line adapter wherever the render layer constructs it. [playing]
/// takes a decoupled `Stream<bool>` rather than `just_audio`'s own
/// `Stream<PlayerState>` for the same reason -- the wiring becomes
/// `playerStateStream.map((s) => s.playing)`, and no test here needs to
/// construct a `PlayerState`.
class CallPlaybackController {
  CallPlaybackController({
    required Stream<Duration> position,
    required Stream<bool> playing,
    required this.ownership,
    required this.mergedEventId,
    required List<CallTurn> turns,
    required this.startMergedPlayer,
    required this.seek,
    required this.play,
  }) : _turns = turns {
    _positionSub = position.listen(_onPosition);
    _playingSub = playing.listen(_onPlaying);
    ownership.addListener(_onOwnershipChanged);
    // No proactive initial resolve, deliberately: [activeIndex] and
    // [isPlaying] both start at their "nothing known yet" default (null,
    // false), which is the CORRECT answer regardless of what [ownership]
    // happens to be at construction, precisely because neither position nor
    // playing state is ever assumed -- only ever set from a real [position]
    // or [playing] event. A controller constructed while already owning the
    // merged event still shows nothing until one of those actually arrives,
    // same as one that gains ownership later; there is no "read as active
    // from the start" case to special-case here.
  }

  /// The shared player's current owner -- `matrix.voiceMessageEventId` in
  /// production. This controller is active only while it equals
  /// [mergedEventId]; see [_owns].
  final ValueListenable<String?> ownership;

  /// The merged "Full call" recording's event id -- the one owner value this
  /// controller treats as "mine".
  final String mergedEventId;

  /// Hands the merged event to the shared player and awaits it being ready to
  /// seek -- e.g. loading the audio source and claiming [ownership]. Called
  /// by [seekToTurn] ONLY when [ownership] does not already hold
  /// [mergedEventId]; already owning it skips straight to [seek].
  final Future<void> Function() startMergedPlayer;

  /// Seeks the (by now merged-owning) shared player to a position.
  final Future<void> Function(Duration position) seek;

  /// Resumes/starts playback on the shared player.
  final Future<void> Function() play;

  List<CallTurn> _turns;

  /// The last reported position, in milliseconds -- null when unknown.
  /// RESET TO NULL ON EVERY OWNERSHIP CHANGE, gained or lost (see
  /// [_onOwnershipChanged]): a position is only meaningful relative to the
  /// track it was reported against, and an ownership change generally means
  /// a different underlying player load whose position has not been
  /// reported yet, so nothing older may be reused as if it still applied.
  /// [_recompute] additionally only ever resolves this against [_turns]
  /// while [_owns] is true, so a value recorded for a track we did not own
  /// can never itself drive [activeIndex] -- but it is the reset here, not a
  /// write-time ownership check in [_onPosition], that stops a STALE value
  /// from being replayed the moment ownership swings back to us; a guard at
  /// the write site would be redundant with it.
  ///
  /// KNOWN LIMITATION, not closable from inside this class: [position] is a
  /// bare `Stream<Duration>` with no per-event owner identity, so a tick
  /// already scheduled by an ASYNCHRONOUS stream (the ordinary case for a
  /// real player) can still be DELIVERED after this reset runs, land while
  /// [_owns] again reads true, and get recorded as if it were fresh. Closing
  /// this fully needs the tick itself to carry which load it came from,
  /// which [Stream<Duration>] cannot. The mitigation is at the wiring layer,
  /// not here: [position] (and [playing]) must be scoped so the underlying
  /// subscription to a track's own stream is torn down SYNCHRONOUSLY, as
  /// part of the same action that moves [ownership] away from it -- the
  /// pattern `_reloadAndPlayAudio` in `select_mode_buttons.dart` already
  /// follows (cancel the old subscription, dispose the old player, THEN
  /// swap [ownership]) -- so a tick for an abandoned track is never queued
  /// to begin with, rather than filtered after the fact.
  int? _lastPositionMs;

  /// The last raw player-state event, regardless of ownership -- unlike
  /// [_lastPositionMs], a playing/paused flag is meaningful on its own (it
  /// says something about the player object, not about a position on a
  /// particular track's timeline), so it survives an ownership change and is
  /// simply re-combined with the new ownership via [_recomputePlaying].
  /// Without this cache, a `true` event that arrived while we did not yet
  /// own the player would be dropped, and gaining ownership afterward would
  /// leave [isPlaying] stuck at false until some unrelated future
  /// player-state event happened to refresh it.
  bool _lastRawPlaying = false;

  bool _seekInFlight = false;
  bool _disposed = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  /// [_awaitWhileOwned]'s temporary ownership watchers, tracked ONLY so
  /// [dispose] can remove them immediately. Its own `finally` block already
  /// removes each one once the awaited action completes, so without a
  /// disposed transaction still in flight this stays empty -- but a
  /// transaction disposed mid-await would otherwise leave its watcher
  /// registered on [ownership] (an object this controller does not own and
  /// so never closes) for however long that action takes to settle, or
  /// forever if it never does, retaining this controller in memory the
  /// whole time.
  final Set<VoidCallback> _activeOwnershipWatches = {};

  final ValueNotifier<int?> _activeIndexNotifier = ValueNotifier(null);

  /// The active turn's index into the list last given to the constructor or
  /// [updateTurns] -- null when nothing is active (no eligible turn yet, or
  /// [ownership] is not [mergedEventId]).
  ValueListenable<int?> get activeIndex => _activeIndexNotifier;

  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);

  /// Whether the MERGED recording specifically is playing right now -- false
  /// whenever [ownership] is not [mergedEventId], even if the underlying
  /// player is busy playing something else. A convenience for the render
  /// layer's "auto-scroll only while playing" rule (spec section 4): the
  /// ownership check that rule needs is the one this controller already
  /// keeps, so it does not have to be re-derived at the call site.
  ValueListenable<bool> get isPlaying => _isPlayingNotifier;

  bool get _owns => ownership.value == mergedEventId;

  /// Called whenever the transcript rebuilds with a new (still [at]-ordered)
  /// turn list -- e.g. late recording data recomputing every turn's window
  /// (spec section 1). Re-resolves the active index against the turns as
  /// they now stand, since indices, and which turns even have an
  /// [CallTurn.audioStartMs], can both change.
  void updateTurns(List<CallTurn> turns) {
    _turns = turns;
    _recompute();
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    _lastPositionMs = position.inMilliseconds;
    _recompute();
  }

  void _onPlaying(bool value) {
    if (_disposed) return;
    _lastRawPlaying = value;
    _recomputePlaying();
  }

  void _onOwnershipChanged() {
    if (_disposed) return;
    _lastPositionMs = null;
    _recomputePlaying();
    _recompute();
  }

  void _recomputePlaying() {
    _setPlaying(_owns && _lastRawPlaying);
  }

  void _recompute() {
    final positionMs = _lastPositionMs;
    _setActiveIndex(
      _owns && positionMs != null ? _resolveActiveIndex(positionMs) : null,
    );
  }

  /// The turn with the greatest `audioStartMs <= positionMs` among turns
  /// that have one at all; a tie is broken by DISPLAY ORDER, the later turn
  /// in [_turns] winning (spec section 1's tie-break) -- so scanning forward
  /// and replacing the running best on `>=` rather than `>` is what makes
  /// this deterministic. Never reads `audioEndMs`: a precise turn's window is
  /// implicitly `[audioStart, next eligible turn's audioStart)` by this same
  /// rule, so precise and approximate turns need no separate handling.
  int? _resolveActiveIndex(int positionMs) {
    int? bestIndex;
    int? bestStart;
    for (var i = 0; i < _turns.length; i++) {
      final start = _turns[i].audioStartMs;
      if (start == null || start > positionMs) continue;
      if (bestStart == null || start >= bestStart) {
        bestIndex = i;
        bestStart = start;
      }
    }
    return bestIndex;
  }

  // The authoritative disposal gate: every path that can change [activeIndex]
  // or [isPlaying] -- a stream event, an ownership change, or a direct
  // [updateTurns] call -- funnels through one of these two setters, so
  // guarding here (rather than, or in addition to, every caller) is what
  // actually keeps a callback from firing after [dispose]. The de-dupe check
  // below mirrors `highlightCurrentText` in `message_selection_overlay.dart`
  // for the same reason that code has one: it is what a reader should expect
  // of this class's contract, spelled out rather than left to be inferred
  // from `ValueNotifier`'s own (also real) equality check underneath it.

  void _setActiveIndex(int? newIndex) {
    if (_disposed) return;
    if (newIndex == _activeIndexNotifier.value) return;
    _activeIndexNotifier.value = newIndex;
  }

  void _setPlaying(bool value) {
    if (_disposed) return;
    if (value == _isPlayingNotifier.value) return;
    _isPlayingNotifier.value = value;
  }

  /// Seeks the merged recording to turn [index]'s `audioStartMs` and plays
  /// it, as one transaction that re-reads [ownership] SYNCHRONOUSLY after
  /// EVERY await in the sequence -- including the seek itself -- so a
  /// per-device player the user started mid-transaction is never overridden
  /// (spec section 4, g2/g3):
  ///
  /// 1. If [ownership] is not already [mergedEventId], await
  ///    [startMergedPlayer]; abort (touching nothing else) if ownership was
  ///    ever seen away from [mergedEventId] while that was in flight.
  /// 2. Re-read [_owns] ONE LAST TIME, synchronously, with no await between
  ///    that read and starting the seek -- abort if it no longer holds.
  /// 3. Await [seek] to the turn's start; abort BEFORE playing under the
  ///    same "ever seen away" rule as step 1.
  /// 4. Re-read [_owns] ONE LAST TIME, synchronously, with no await between
  ///    that read and calling [play] -- then await [play].
  ///
  /// Each recheck in steps 1 and 3 is "was ownership ever seen away from
  /// [mergedEventId] during the await", not merely "does it read as
  /// [mergedEventId] now" -- see [_awaitWhileOwned] for why a plain
  /// before/after comparison is not enough there, and for why it alone is
  /// still not enough to greenlight the NEXT action (steps 2 and 4): this
  /// function's own resumption, after [_awaitWhileOwned] returns its
  /// verdict, is itself a fresh suspension point -- nothing guarantees
  /// [ownership] cannot change in whatever gap exists between that verdict
  /// being decided and this function acting on it (in production both
  /// [seek] and [play] are real platform calls, genuine yield points the
  /// user's own next tap can land inside). Steps 2 and 4's guards are what
  /// actually get read at the last possible synchronous instant before the
  /// next action runs; without either one, a `true` decided one step ago
  /// could already be stale by the time it is used -- step 2's absence is
  /// exactly what let [seek] run once on a source the user had already
  /// moved to, even though step 4 still correctly kept [play] from
  /// following it.
  ///
  /// A no-op for a turn with no `audioStartMs` (nothing to seek to), and for
  /// a tap that arrives while a previous one is still in flight -- overlap is
  /// ignored rather than queued or interrupting the one already running.
  Future<void> seekToTurn(int index) async {
    if (_disposed || _seekInFlight) return;
    if (index < 0 || index >= _turns.length) return;
    final startMs = _turns[index].audioStartMs;
    if (startMs == null) return;

    _seekInFlight = true;
    try {
      if (!_owns) {
        if (!await _awaitWhileOwned(() => startMergedPlayer())) return;
        // Same reasoning as the pre-play guard below, one step earlier:
        // _awaitWhileOwned's `true` just now was decided as of the moment
        // startMergedPlayer() resolved, so it alone cannot prove ownership
        // is STILL ours right now -- seekToTurn's own resumption after
        // awaiting it is itself a fresh suspension point. Re-reading here,
        // with nothing awaited between this line and the seek's
        // _awaitWhileOwned call, is what actually closes the load->seek
        // boundary; without it, seek() -- a real side effect on the shared
        // player -- would run on whatever source ownership moved to in
        // that gap, even though _awaitWhileOwned would still correctly
        // abort before play() afterward.
        if (_disposed || !_owns) return;
      }
      if (!await _awaitWhileOwned(
        () => seek(Duration(milliseconds: startMs)),
      )) {
        return;
      }
      // Last synchronous instant before playing: _awaitWhileOwned's `true`
      // above was decided as of the moment seek() resolved, so it alone
      // cannot prove ownership is STILL ours right now -- only re-reading
      // it here, with nothing awaited between this line and `play()`, can.
      if (_disposed || !_owns) return;
      await play();
    } finally {
      _seekInFlight = false;
    }
  }

  /// Awaits the future [action] produces and reports whether [ownership]
  /// stayed at [mergedEventId] (or was never seen otherwise) the whole time
  /// -- false if [_disposed], or if [ownership] was EVER observed to differ
  /// from [mergedEventId] while [action] was running, even if it reads back
  /// as [mergedEventId] again by the time it completes.
  ///
  /// That last case is not hypothetical: [startMergedPlayer]'s OWN job is to
  /// claim [mergedEventId] as a side effect of completing, so a plain
  /// before/after read of [ownership] always passes right after it returns
  /// -- by construction, not because nothing happened in between. If the
  /// user picked a per-device half mid-load and [startMergedPlayer]
  /// reclaims [mergedEventId] regardless when it finally finishes, that
  /// reclaim is indistinguishable from a clean load unless something
  /// watches for the INTERRUPTION itself, not just the value at either end
  /// -- an ABA race a two-point check cannot see. Watching every change
  /// [ownership] makes while [action] runs is what closes it.
  ///
  /// [action] is a THUNK -- called HERE, not by the caller -- specifically
  /// so the `watch` listener below is registered BEFORE [action] starts
  /// running, not after. Every call site used to pass an ALREADY-STARTED
  /// future (e.g. `_awaitWhileOwned(startMergedPlayer())`), which evaluates
  /// `startMergedPlayer()` as a plain argument expression before this
  /// function's own body runs at all -- including [startMergedPlayer]'s own
  /// synchronous prefix, the part of an `async` function that runs
  /// immediately, before its first `await`, one full step ahead of the
  /// listener meant to watch it. An ownership change [startMergedPlayer] or
  /// [seek] makes synchronously, before either ever suspends, would fire
  /// and be missed with nothing listening yet. Calling the thunk only after
  /// `addListener` closes that window.
  ///
  /// A caller MUST STILL re-read [_owns] at its own last synchronous instant
  /// before acting on a `true` result here (see [seekToTurn]'s guard right
  /// before [play]): a `true` returned here is only a statement about the
  /// instant it was decided, not a lease on the future -- the caller's own
  /// resumption after awaiting this function is itself a fresh suspension
  /// point [ownership] can change across before anything further runs.
  Future<bool> _awaitWhileOwned(Future<void> Function() action) async {
    var interrupted = false;
    void watch() {
      if (ownership.value != mergedEventId) interrupted = true;
    }

    _activeOwnershipWatches.add(watch);
    ownership.addListener(watch);
    try {
      await action();
    } finally {
      ownership.removeListener(watch);
      _activeOwnershipWatches.remove(watch);
    }
    return !_disposed && !interrupted && _owns;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_positionSub?.cancel());
    unawaited(_playingSub?.cancel());
    ownership.removeListener(_onOwnershipChanged);
    // A transaction disposed mid-await still owns a temporary watcher on
    // [ownership] (see [_activeOwnershipWatches]) that its own `finally`
    // will not remove until [startMergedPlayer]/[seek] settles -- removed
    // here instead of waiting for that.
    for (final watch in _activeOwnershipWatches) {
      ownership.removeListener(watch);
    }
    _activeOwnershipWatches.clear();
    _activeIndexNotifier.dispose();
    _isPlayingNotifier.dispose();
  }
}
