import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/transcript_tokens.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// How well a turn's moment is known, and therefore what may be printed above
/// it.
///
/// THREE states, not a boolean, because there are three different things the
/// reader can be told and only one of them is a time we stand behind. An
/// earlier design had two renderings for these three, which left the third
/// printing a plain `m:ss` it had no standing to print.
enum TurnTime {
  /// [CallTurn.at] is the start of this turn's first word, as the provider
  /// timed it in the audio that was sent. Printed as `m:ss`.
  ///
  /// Word-timing resolution, not phoneme resolution: the trim's pad stands
  /// between the first voiced frame and the start of the audio a provider
  /// read, so an unvoiced onset can fall a few tens of milliseconds ahead of
  /// this. Far below anything that reorders two turns.
  exact,

  /// The words were said at or before [CallTurn.at], somewhere inside the
  /// chunk of audio they were cut from. Printed as "by m:ss".
  ///
  /// Placed at the LATEST moment it could have been, which is what stops it
  /// rendering ahead of the other speaker's correctly timed turn.
  atOrBefore,

  /// The writing device asserted a moment and never said whether that moment
  /// was a word's or a whole chunk's. NO time is printed.
  ///
  /// Showing the number anyway would put this app's confidence behind that
  /// device's silence. The turn still keeps its PLACE in the order that
  /// unvouched number implies -- there is nothing else to order it by, and
  /// hiding it would cost a real turn to protect against an uncertain one --
  /// so its position in the conversation is as unvouched as its time. The
  /// transcript says exactly that; withholding only the label would leave the
  /// ordering claim standing unannounced.
  unstated,
}

/// One utterance in an ordered call transcript.
///
/// Deliberately plain, and deliberately not `TranscriptSegment` or a Matrix
/// event: everything that decides who was on the call, whether their words
/// can be trusted, and whether they can be placed in time at all belongs to
/// the reader that assembles this list. This widget draws whatever it is
/// given, in the order it is given, and asks nothing about how either
/// question was answered -- which is what lets the two be built, and tested,
/// apart.
@immutable
class CallTurn {
  /// The Matrix user ID. Used only to key [Avatar] and to tell one speaker's
  /// turns apart from the next; never rendered.
  final String senderId;

  /// The speaker's avatar, when they have one. Null renders the initial of
  /// [name], which is the same fallback the rest of the app uses.
  final Uri? avatarUrl;

  /// The speaker's display name. Ignored when [isMe] is true -- the widget
  /// substitutes the localised "You" itself, so no caller has to remember to.
  final String name;

  final bool isMe;

  /// Elapsed from the transcript's ORIGIN — the earliest moment any turn in it
  /// is PLACED at — not from the moment the call connected. Already the number
  /// this widget prints, not a wall-clock instant left for it to convert.
  ///
  /// The earliest PLACED moment, and nothing stronger. It is the first thing
  /// anybody said only when every drawn turn is [TurnTime.exact]; one
  /// [TurnTime.atOrBefore] turn is enough to break that, and not only when it
  /// is the earliest. A speaker bounded to `[0s, 45s]` who actually spoke at 5s
  /// is placed at 45s, so the other speaker's exact word at 40s becomes the
  /// origin and 0:00 lands on something said second.
  ///
  /// Either way this clock can disagree with the duration the call card shows.
  /// The transcript wire carries one absolute time per segment and nothing
  /// about when capture began, so the moment the call connected is not
  /// recoverable here; ringing, greetings before anyone spoke, and any opening
  /// silence are all outside what this can see.
  ///
  /// If these times ever need to line up with the call's own duration, the
  /// call's start has to be written into the transcript event at capture time
  /// -- a wire change, not a display one.
  final Duration at;

  /// What may be said about [at]. See [TurnTime].
  final TurnTime time;

  final String text;

  /// The language this turn was transcribed in, from the half's `lang_code`, or
  /// null when the writer recorded none. Passed to [TranscriptTokens] so the
  /// words can be tokenized for their word cards (#8797).
  final String? langCode;

  /// This turn's window in the merged "Full call" recording -- a SEPARATE
  /// timeline from [at], added display-only so playback can seek to and
  /// highlight the turn currently playing. See `_turnsOf` in
  /// `transcript_view.dart` for the exact arithmetic and for every condition
  /// that leaves both of these null (no merged recording on screen, clocks
  /// never reconciled, this turn's own half never anchored its clock, or this
  /// sender's audio is not part of the mix).
  ///
  /// Both null together, always -- a turn either has a position in the
  /// recording to seek and highlight against, or it does not.
  /// [audioStartMs] is where a tap should seek playback to; [audioEndMs] is
  /// the end of the window a chunk-bounded turn's estimate could fall
  /// anywhere in. Neither ever changes [at] or its printed label, and
  /// neither ever reorders the standalone list: this is read-only display
  /// state layered on top of a turn whose own time and place are already
  /// decided.
  ///
  /// Milliseconds from the merged recording's own start, already clamped to
  /// `[0, durationMs]` (and `audioEndMs` further to `[audioStartMs,
  /// durationMs]`) -- never a raw, possibly out-of-range offset.
  final int? audioStartMs;
  final int? audioEndMs;

  /// Identifies this turn uniquely within the transcript it was built from,
  /// stable across a rebuild that leaves the underlying segment unchanged --
  /// what a [GlobalKey] for auto-scroll / karaoke highlighting is keyed on.
  ///
  /// NEITHER [senderId] alone NOR a position in either list will do. A
  /// speaker who contributed from more than one device (see
  /// `TranscriptHalf.deviceCount`) writes several turns under the one
  /// [senderId], so that alone collides. And a position is not a fact about
  /// the turn, it is a fact about everything else that happens to sit beside
  /// it: a position in the SORTED list moves whenever another turn's [at]
  /// changes, and a position in the half's OWN segment list moves whenever a
  /// sibling segment is inserted or removed ahead of it -- a second device's
  /// half joining the same sender after the dialog is already open, say.
  /// Keying on either would change a turn's identity for a reason that has
  /// nothing to do with the turn itself, which is exactly what breaks a
  /// [GlobalKey]: Flutter reads a changed key as a DIFFERENT widget, not an
  /// update to this one, so an in-flight highlight or scroll keyed on it
  /// silently resets.
  ///
  /// So this is built from the turn's own content instead -- see
  /// `_turnIdentityKey` in `transcript_view.dart` for the exact derivation.
  /// [senderId] is already unique across the transcript's halves, since
  /// `assembleTranscript` groups every candidate into `CallTranscript.halves`
  /// by a `Set` of sender ids (`transcript_assembly.dart`), so one sender's
  /// several devices are combined into ONE half before this widget ever sees
  /// them, never kept as separate halves. Paired with the segment's own
  /// `atMs` -- a fact about that segment alone, which does not move when
  /// anything ELSE in the half does -- and, since two segments can share an
  /// `atMs` (one malformed chunk's shared fallback offset), a tiebreak of the
  /// segment's own span and its own text, both embedded verbatim -- see
  /// `_turnIdentityKey` for why neither is reduced to a lossy digest. A
  /// content tie survives even that -- two segments can share atMs, span AND
  /// text all at once -- so a final ordinal breaks it; see
  /// `_turnIdentityKey` for how that ordinal stays stable across a rebuild
  /// too.
  final String identityKey;

  const CallTurn({
    required this.senderId,
    required this.name,
    required this.isMe,
    this.avatarUrl,
    required this.at,
    this.time = TurnTime.exact,
    required this.text,
    this.langCode,
    this.audioStartMs,
    this.audioEndMs,
    required this.identityKey,
  });
}

/// The turn-by-turn view of a call transcript, ordered by [CallTurn.at].
///
/// Drawn as the chat it came from: your turns on one side, theirs on the
/// other, in the same two fills `message.dart` uses so the two screens agree.
/// A call between the same two people whose conversation this is reads as that
/// conversation; one column of avatar, name, time and text read as a meeting
/// minute. A speaker CHANGE opens a run, drawing their face, their name and a
/// time; a turn from the same speaker draws none of those and squares off the
/// corner adjacent to its neighbour.
///
/// Deliberately not a [ListView] or [SliverList] itself -- the caller already
/// owns a scrollable (the transcript dialog's, today), and a scrollable
/// nested inside another only fights it for gesture ownership. A transcript
/// is read start to finish, not queried at an offset, so there is nothing to
/// buy by making this one lazy.
///
/// ## Karaoke (optional, additive)
///
/// [activeIndex], [isPlaying] and [onSeekTurn] wire this widget to a
/// `CallPlaybackController` driving the "Full call" recording -- see
/// `docs/handoff/2026-09-10-recordings-ui-redesign-spec.md` section 4. All
/// three are optional and [activeIndex] is the master gate: while it is null
/// (no recording on screen, or nothing resolved yet) this widget renders and
/// behaves EXACTLY as it does with none of this wired up at all -- no accent
/// bar, no tint, no auto-scroll, no seek affordance -- regardless of what
/// [isPlaying] or [onSeekTurn] happen to be. Once [activeIndex] is non-null,
/// [isPlaying] additionally gates auto-scroll (it still highlights without
/// it) and [onSeekTurn] additionally gates the seek affordance turn-by-turn
/// (a turn also needs its own [CallTurn.audioStartMs]).
///
/// [activeIndex] and any index passed to [onSeekTurn] are indices into THIS
/// widget's own call-time-ordered rendering -- the same order [turns] sorts
/// into internally (see [_byTime]). A caller must construct its
/// `CallPlaybackController` over that SAME ordered list (which, since
/// [_byTime] is a stable sort, is simplest by always handing both this widget
/// and the controller an already call-time-sorted list) or the two will
/// disagree about which turn a given index names.
class TurnTimeline extends StatefulWidget {
  /// Need not arrive sorted by [CallTurn.at] -- [build] sorts it. A caller
  /// that forgets to order its own list is not a caller this widget trusts
  /// to have gotten it right; an unenforced precondition is a hazard, not a
  /// contract, and the one direction it can fail in here is a teacher reading
  /// a call in the wrong order with full confidence that it is correct.
  final List<CallTurn> turns;

  /// The turn currently playing in the "Full call" recording, as an index
  /// into this widget's ordered rendering -- see the class doc's Karaoke
  /// section for the index-space contract and the null gate.
  final ValueListenable<int?>? activeIndex;

  /// Whether the recording behind [activeIndex] is playing right now. Gates
  /// auto-scroll only (see the class doc) -- a null value, or one that never
  /// turns true, still highlights the active turn, it is just never
  /// auto-scrolled to.
  final ValueListenable<bool>? isPlaying;

  /// Called with a turn's index (see the class doc's index-space contract)
  /// when the reader taps that turn's time to seek playback there. A turn
  /// with no [CallTurn.audioStartMs] never offers the tap regardless of this
  /// being set.
  final void Function(int index)? onSeekTurn;

  const TurnTimeline({
    required this.turns,
    this.activeIndex,
    this.isPlaying,
    this.onSeekTurn,
    super.key,
  });

  static const double _avatarSize = 32;
  static const double _avatarGap = 12;

  @override
  State<TurnTimeline> createState() => _TurnTimelineState();

  /// Sorted by [CallTurn.at], stable by construction rather than by trusting
  /// `List.sort` to behave that way -- it is not guaranteed to.
  ///
  /// Two turns can legitimately share one instant: the backend's own
  /// arithmetic stamps every chunk cut from one oversized audio batch with a
  /// position derived from frame count, and a batch split into several
  /// chunks in a single pass can produce equal timestamps for chunks that
  /// were still spoken in a real order. Every segment of one chunk whose
  /// timings were refused shares one instant too, by construction.
  ///
  /// Sorting the ORIGINAL INDEX alongside the timestamp turns every comparison
  /// into a strict total order, so two same-instant turns keep the order they
  /// were given regardless of which algorithm runs underneath and regardless of
  /// how many times this rebuilds. WITHIN one speaker that order is the order
  /// they were spoken. ACROSS two speakers it is whichever half the caller
  /// flattened first, which is arbitrary -- stable, so the screen does not
  /// shuffle between rebuilds, but not a claim about who spoke first.
  static List<CallTurn> _byTime(List<CallTurn> turns) {
    final indices = List<int>.generate(turns.length, (i) => i)
      ..sort((a, b) {
        final byTime = turns[a].at.compareTo(turns[b].at);
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    return [for (final i in indices) turns[i]];
  }

  /// 20px across a speaker change, 6px between two turns from the one
  /// speaker -- the vertical half of the rule that makes a change read as
  /// one. [i] is never 0; the caller supplies that gap directly, since there
  /// is no turn above the first to measure a change against. Reads
  /// [ordered], never [turns] -- the gap is between two turns as SHOWN, and
  /// only the sorted list says what that is.
  static double _gapAbove(List<CallTurn> ordered, int i) =>
      _opensATurn(ordered, i) ? 20 : 6;

  /// How long one speaker may keep going before their next stretch is read as
  /// a new turn rather than a continuation of the last.
  ///
  /// A speaker CHANGE always opens a turn. A pause does too, and it has to:
  /// only the opening turn of a run draws a header, and the header is the only
  /// thing that prints a time. Grouping on the speaker alone therefore printed
  /// ONE time above a run and let the rest inherit it silently -- a real call
  /// showed three stretches at 0:04, 0:17 and 0:19 rendered as a single turn
  /// stamped 0:04, so the screen said the last two happened fifteen seconds
  /// before they did.
  ///
  /// Matched to `kUtterancePause`, the same gap the cutter used to end the
  /// previous stretch. Anything the backend judged long enough to break a
  /// segment on is long enough to deserve its own time on screen.
  static const _newTurnAfter = Duration(milliseconds: 900);

  static bool _opensATurn(List<CallTurn> ordered, int i) {
    if (i == 0) return true;
    final previous = ordered[i - 1];
    final current = ordered[i];
    if (previous.senderId != current.senderId) return true;
    // A change of KIND opens a turn too, and it has to. Only the opening turn
    // of a run draws a header, and the header is the only thing that says what
    // is known about the time -- so an exact turn landing on the same moment as
    // an at-or-before one would slide under its "by", or an unstated turn under
    // a plain stamp, and inherit a claim that does not describe it.
    if (previous.time != current.time) return true;
    return current.at - previous.at >= _newTurnAfter;
  }
}

class _TurnTimelineState extends State<TurnTimeline> {
  /// One [GlobalKey] per turn, keyed by [CallTurn.identityKey] and retained
  /// across rebuilds -- an index-derived key would break the moment a
  /// transcript rebuild inserts or reorders a turn (late recording data
  /// recomputing every turn's window, spec section 1), silently resetting an
  /// in-flight scroll. Only ever populated while karaoke is enabled (see
  /// [build]); pruned to the turns currently on screen at the top of every
  /// build, so a turn that disappears does not leak its key forever.
  final Map<String, GlobalKey> _keysByIdentity = {};

  /// This widget's own [TurnTimeline._byTime]-ordered rendering as of the
  /// most recent [build] -- read by the listener callbacks below, which run
  /// OUTSIDE the build phase and so cannot recompute it from `widget.turns`
  /// on demand without risking it disagreeing with what is actually mounted
  /// right now.
  List<CallTurn> _ordered = const [];

  int? _lastActiveIndex;

  /// The last `isPlaying` value [_onIsPlayingChanged] actually saw -- via a
  /// real notification while attached, or via [_syncIsPlayingListener]'s
  /// own rebaseline the moment it (re)attaches. A false->true edge against
  /// this is the RESUME condition (spec section 4).
  ///
  /// KNOWN, UNCLOSED GAP -- inherent to honoring the master gate, not a
  /// defect in the rebaseline itself: while [_karaokeEnabled] is false,
  /// NOTHING observes `isPlaying` at all (the entire point of the gate --
  /// see [_syncIsPlayingListener]), so this field is simply frozen at
  /// whatever it last was. Two DIFFERENT ways this can arrive at a stale
  /// value once the gate reopens, both unrecoverable for the same reason:
  ///
  /// - The SAME, continuously-existing `isPlaying` object changes value and
  ///   then changes BACK before the gate reopens (`true -> false -> true`,
  ///   say).
  /// - [TurnTimeline.isPlaying] itself passes through null (removed, or
  ///   swapped for a different object) WHILE the gate is ALSO closed, so by
  ///   the time something is attached again -- the same object once more,
  ///   or a brand new one -- there is no reason to expect its CURRENT value
  ///   to relate at all to whatever [TurnTimeline.activeIndex] was doing
  ///   when the gate last closed. (Swapping `isPlaying` while the gate
  ///   stays OPEN throughout is NOT this gap: [_syncIsPlayingListener] still
  ///   rebaselines against the new object's current value in that case,
  ///   deliberately treating it as a real edge -- see the dedicated test for
  ///   that swap.)
  ///
  /// Either way, this field can only ever compare the LAST value seen
  /// before closing against the CURRENT value after reopening, never
  /// anything that happened in between, because nothing was watching in
  /// between -- so a false->true edge that would have fired a resume had
  /// the gate stayed open is silently missed whenever the net effect across
  /// the closed window looks like no change at all. Closing this would mean
  /// observing `isPlaying` in some form while the gate is closed --
  /// precisely what the gate exists to prevent. The alternative of
  /// resuming unconditionally on every reattachment where the newly
  /// observed value happens to be `true` was considered and rejected: that
  /// would misfire on the FAR more common case of an incidental,
  /// transient gate blip landing while `isPlaying` is simply already `true`
  /// (the ordinary state while a recording plays), spuriously clearing a
  /// suspension the reader only just set -- trading a narrow, hard-to-hit
  /// gap for a broader, easy-to-hit one. So, like [_autoScrollInFlight]'s
  /// own activity-ownership gap and [_observedPosition]'s single-ancestor-
  /// `Scrollable` limitation elsewhere in this class, this is documented
  /// rather than fixed.
  bool _lastIsPlaying = false;

  /// Whichever `isPlaying` listenable [_onIsPlayingChanged] is actually
  /// attached to right now, or null when nothing is -- written only by
  /// [_syncIsPlayingListener]. Tracked separately from [TurnTimeline.
  /// isPlaying] because the two can disagree: [TurnTimeline.activeIndex] is
  /// the master gate for the whole karaoke feature (the class doc), so this
  /// stays null whenever [_karaokeEnabled] is false regardless of what
  /// [TurnTimeline.isPlaying] itself is.
  ValueListenable<bool>? _attachedIsPlaying;

  /// Bumped on every [_onActiveIndexChanged] call that finds a REAL value
  /// change (never on a no-op notification, including a listenable swap
  /// that lands on the same value as one already pending) -- see the
  /// generation check inside that method's deferred callback.
  int _activeIndexNotificationGeneration = 0;

  /// Set once the reader manually scrolls (see [_onAncestorScrollChanged]);
  /// cleared on the next seek tap or the next playing-false->true edge (spec
  /// section 4). While set, [_autoScrollTo] is a no-op.
  bool _autoScrollSuspended = false;

  /// Whether SOME scroll this widget itself set in motion -- not
  /// necessarily the most RECENT [_autoScrollTo] call specifically -- is
  /// still able to move `pixels` on its own. Kept in lockstep with the one
  /// authoritative source of that fact,
  /// `ScrollPosition.isScrollingNotifier` (see [_onAncestorScrollingChanged]
  /// and the direct read at the end of [_autoScrollTo]), rather than with
  /// per-call bookkeeping of its own: an earlier version tracked this with
  /// a monotonic "generation" stamped on each [_autoScrollTo] call, cleared
  /// only by the LATEST call's own completion -- which breaks the instant a
  /// call is a NO-OP (`Scrollable.ensureVisible` finds the target already
  /// visible against wherever an EARLIER, still-running call currently
  /// sits, and touches no activity at all). That no-op call's own
  /// (immediately-resolved) future still completed and still "was the
  /// latest", so it would clear the flag regardless of the earlier call's
  /// activity continuing to drive `pixels` -- misreading THAT activity's
  /// own next tick as a manual scroll. Reading the real, single source of
  /// truth directly sidesteps the whole class of "whose completion gets to
  /// win" races a second, parallel piece of bookkeeping invites.
  ///
  /// KNOWN, UNCLOSED GAP -- `isScrollingNotifier` answers "is SOMETHING
  /// scrolling", never "is it MINE": Flutter's scroll-activity model
  /// exposes no public way to ask a `ScrollPosition` which specific caller
  /// owns its current activity, only that ACTIVITY's own type and
  /// `isScrolling` flag. A keyboard `PageDown`/arrow-key scroll
  /// (`ScrollAction.invoke` -> `ScrollPosition.moveTo` -> `animateTo` for
  /// any non-zero duration, which is what it passes) constructs its OWN
  /// `DrivenScrollActivity` -- INDISTINGUISHABLE, by `isScrolling` alone,
  /// from this widget's. If one interrupts an in-flight [_autoScrollTo]
  /// call, `beginActivity` disposes this widget's activity for the
  /// keyboard's, but the notifier never leaves `true`, so neither
  /// listener ever notices: the keyboard scroll's own pixel changes are
  /// misread as this widget's continuing scroll (never suspending), and
  /// once the keyboard scroll ends, [_autoScrollInFlight] clears as if
  /// this widget's OWN scroll had finished -- without ever having flagged
  /// [_autoScrollSuspended]. A LATER karaoke auto-scroll can then still
  /// override wherever the reader's keyboard scroll left them. Genuinely
  /// closing this needs a way to identify activity OWNERSHIP that the
  /// public `ScrollPosition` API does not expose (short of wrapping or
  /// subclassing it, well beyond what a single consuming widget should
  /// take on) -- not attempted here. Scrollbar-track taps carry the exact
  /// same gap for the same reason (also a `moveTo`-driven jump). Both are
  /// desktop/web-only interactions; the touch platforms this feature
  /// primarily ships on have neither.
  bool _autoScrollInFlight = false;

  /// True for the duration of an [_autoScrollTo] call's OWN synchronous
  /// `Scrollable.ensureVisible` setup -- see the guard comment on that call
  /// site, and both [_onAncestorScrollChanged] and
  /// [_onAncestorScrollingChanged], which each check it for a different
  /// reason: the former because [_autoScrollInFlight] itself is not
  /// updated until AFTER this window closes, the latter because a
  /// transition `ensureVisible` causes as part of its own startup is never
  /// a genuinely external one.
  bool _startingAutoScroll = false;

  /// The enclosing scrollable's position, watched directly rather than via a
  /// `NotificationListener<UserScrollNotification>` -- see
  /// [_onAncestorScrollChanged] for why. Null whenever karaoke is disabled or
  /// no ancestor `Scrollable` exists.
  ///
  /// KNOWN LIMITATION: only the NEAREST ancestor `Scrollable` is watched.
  /// [_autoScrollTo]'s `Scrollable.ensureVisible` call walks and scrolls
  /// EVERY nested ancestor scrollable, so a reader manually scrolling a MORE
  /// DISTANT one (this widget's caller nested inside a second, outer
  /// scrollable) would not be seen here and could still be overridden by a
  /// later auto-scroll. Not fixed: the documented composition
  /// (`docs/handoff/2026-09-10-recordings-ui-redesign-spec.md` section 2,
  /// and the pre-existing `ListView` this replaces) nests this widget inside
  /// exactly ONE scrollable, so the gap does not reach the shipped
  /// composition; watching every nested level defensively for a shape this
  /// widget is never actually placed in was judged not worth the added
  /// complexity. Revisit if a future composition nests this inside two
  /// scrollables.
  ScrollPosition? _observedPosition;

  bool get _karaokeEnabled => widget.activeIndex != null;

  @override
  void initState() {
    super.initState();
    widget.activeIndex?.addListener(_onActiveIndexChanged);
    // Seeds [_lastIsPlaying] too, via [_onIsPlayingChanged], but ONLY when
    // this actually attaches to something -- i.e. only when [_karaokeEnabled]
    // is true from construction. While it is false, [_lastIsPlaying] is left
    // at its bare field default: reading `widget.isPlaying?.value` here
    // regardless of the gate would be the exact same violation Fix 1 closed
    // for the LISTENER, just for a plain getter instead -- see
    // [_syncIsPlayingListener].
    _syncIsPlayingListener();
    _lastActiveIndex = widget.activeIndex?.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncScrollObserver();
  }

  @override
  void didUpdateWidget(covariant TurnTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activeIndex, widget.activeIndex)) {
      oldWidget.activeIndex?.removeListener(_onActiveIndexChanged);
      widget.activeIndex?.addListener(_onActiveIndexChanged);
      // Re-evaluate against the NEW object's current value via the same
      // path a real notification takes, rather than silently adopting it as
      // the new baseline: a caller that swaps the listenable instance
      // itself (a fresh `CallPlaybackController`, say) for one already
      // sitting on a different value is exactly as real an active-turn
      // change as that same value arriving as a notification would be, and
      // skipping straight to `_lastActiveIndex = ...value` would swallow the
      // rebuild/auto-scroll that change deserves.
      _onActiveIndexChanged();
    }
    // Re-syncs both the LISTENER ATTACHMENT and the [_lastIsPlaying]
    // baseline against whatever should be observed right now -- covers an
    // `isPlaying` identity swap (the same "re-evaluate against the NEW
    // object's current value" reasoning as the `activeIndex` branch above),
    // AND [TurnTimeline.activeIndex] itself flipping null<->non-null (the
    // master gate) on an update where `isPlaying`'s own object never
    // changed at all. See [_syncIsPlayingListener] -- in particular, why
    // rebaselining on EVERY (re)attachment, not only an object swap, is
    // what closes the master gate for good.
    _syncIsPlayingListener();
    // Cheap and idempotent (see [_syncScrollObserver]'s own identity guard),
    // and the only hook that sees [activeIndex] flip null<->non-null without
    // an ancestor InheritedWidget change of its own to ride along on.
    _syncScrollObserver();
  }

  @override
  void dispose() {
    widget.activeIndex?.removeListener(_onActiveIndexChanged);
    _attachedIsPlaying?.removeListener(_onIsPlayingChanged);
    _observedPosition?.removeListener(_onAncestorScrollChanged);
    _observedPosition?.isScrollingNotifier.removeListener(
      _onAncestorScrollingChanged,
    );
    super.dispose();
  }

  /// (Re)attaches [_onIsPlayingChanged] to whichever `isPlaying` listenable
  /// should be observed right now, detaches it from whatever it was
  /// attached to before, and re-baselines [_lastIsPlaying] against it -- a
  /// no-op when nothing changed, so callers do not need to guard against
  /// calling this too often (mirrors [_syncScrollObserver]'s own
  /// idempotence).
  ///
  /// [TurnTimeline.activeIndex] is the master gate for the whole karaoke
  /// feature (the class doc): this widget must never observe [TurnTimeline.
  /// isPlaying] -- not even to attach a listener that does nothing but
  /// bookkeeping, and not even to read its `.value` once -- while
  /// [_karaokeEnabled] is false. A caller may wire a real, stream-backed
  /// [ValueListenable] there before a recording ever resolves; attaching to
  /// it regardless of the gate would let that stream start doing work
  /// (holding a subscription open, however cheap) while karaoke is fully
  /// disabled -- exactly what the gate exists to prevent.
  ///
  /// The re-baseline (via [_onIsPlayingChanged], never a bare
  /// `_lastIsPlaying = target?.value ?? false` here) is what actually closes
  /// the gate rather than merely relocating it: [_lastIsPlaying] cannot be
  /// updated by a real notification for as long as nothing is attached, so
  /// a value change that happens ENTIRELY while [_karaokeEnabled] is false
  /// -- including the ENTIRE stretch the gate spent closed, however long --
  /// would otherwise leave [_lastIsPlaying] stale the moment this reattaches,
  /// silently swallowing a false->true edge that never got a chance to
  /// resume auto-scroll (spec section 4). Routing through
  /// [_onIsPlayingChanged] treats this (re)attachment exactly like the
  /// listenable-swap case in [didUpdateWidget] already does: evaluate the
  /// CURRENT value via the same path a real notification takes, never
  /// silently adopt it as a fresh baseline. Harmless to call when
  /// [_karaokeEnabled] is false too (e.g. on the transition INTO a closed
  /// gate) -- [_onIsPlayingChanged]'s own guard makes that call a no-op.
  void _syncIsPlayingListener() {
    final target = _karaokeEnabled ? widget.isPlaying : null;
    if (identical(target, _attachedIsPlaying)) return;
    _attachedIsPlaying?.removeListener(_onIsPlayingChanged);
    _attachedIsPlaying = target;
    _attachedIsPlaying?.addListener(_onIsPlayingChanged);
    _onIsPlayingChanged();
  }

  /// Looks up the nearest ancestor `Scrollable`'s position and (re)attaches
  /// [_onAncestorScrollChanged] and [_onAncestorScrollingChanged] to it -- a
  /// no-op when nothing changed, so callers do not need to guard against
  /// calling this too often. Detaches (leaving [_observedPosition] null)
  /// whenever karaoke is disabled: with no [TurnTimeline.activeIndex] there
  /// is nothing to auto-scroll, so nothing to suspend either.
  void _syncScrollObserver() {
    final position = _karaokeEnabled
        ? Scrollable.maybeOf(context)?.position
        : null;
    if (identical(position, _observedPosition)) return;
    _observedPosition?.removeListener(_onAncestorScrollChanged);
    _observedPosition?.isScrollingNotifier.removeListener(
      _onAncestorScrollingChanged,
    );
    _observedPosition = position;
    _observedPosition?.addListener(_onAncestorScrollChanged);
    _observedPosition?.isScrollingNotifier.addListener(
      _onAncestorScrollingChanged,
    );
    // [_autoScrollInFlight] is meaningless relative to a DIFFERENT
    // `ScrollPosition` than whichever one (if any) last set it: an
    // in-flight scroll on the OLD position's own activity has no bearing
    // on the NEW one, and this widget just stopped listening to whatever
    // would eventually have told it that activity went idle. Carrying a
    // stale `true` across the swap would permanently ignore the new
    // position's first genuine scroll; resetting to `false` is the safe
    // default -- worst case, a still-genuinely-running scroll on the OLD
    // position is merely forgotten, never a stuck "always mine" reading on
    // the new one. Reachable whenever karaoke toggles off and back on, or
    // the ancestor `Scrollable` itself is replaced, while a scroll is mid-
    // flight.
    _autoScrollInFlight = false;
  }

  /// Deliberately NOT a `NotificationListener<UserScrollNotification>`,
  /// even though that is the first thing this feature calls to mind: this
  /// widget is a plain, non-scrolling `Column` placed INSIDE a scrollable
  /// its caller owns (the class doc; `transcript_view.dart` today, a future
  /// sliver tomorrow), so any `NotificationListener` planted in ITS OWN
  /// subtree sits BELOW that ancestor `Scrollable`'s `notificationContext` --
  /// which `ScrollContext.notificationContext`'s own doc describes as a
  /// context OUTSIDE the `Viewport` -- and a `ScrollNotification` dispatched
  /// from there walks UP the tree, never back down into a descendant. A
  /// `NotificationListener` nested inside the scrolled content the way this
  /// widget is placed simply never fires; confirmed empirically (a
  /// throwaway probe: an identical inner listener saw zero of the
  /// notifications an outer, wrapping one saw for the same drag), not only
  /// by reading the framework source.
  ///
  /// Watching [ScrollPosition] directly sidesteps that: [Scrollable.maybeOf]
  /// is an ordinary `InheritedWidget` lookup, which (unlike notification
  /// bubbling) works from a descendant. [_observedPosition] notifies for
  /// EVERY pixel change regardless of cause, including this widget's OWN
  /// [_autoScrollTo] calls -- [_autoScrollInFlight] is what tells the two
  /// apart MOST of the time (see that field's doc for how it stays correct,
  /// AND for a real, unclosed gap in what "apart" can mean here at all).
  ///
  /// [_startingAutoScroll] covers the one window [_autoScrollInFlight]
  /// itself cannot: `Scrollable.ensureVisible` calls `ScrollPosition.
  /// ensureVisible`, which for `Duration.zero` (reduced motion) does not go
  /// through `animateTo` at all -- it calls `jumpTo` directly, which
  /// disposes whatever was running (`goIdle`) and THEN moves `pixels`
  /// (`forcePixels`), reaching this listener, ALL synchronously, before
  /// [_autoScrollTo] ever reaches its own closing read of
  /// `isScrollingNotifier`. On the very first call (or any call where
  /// [_autoScrollInFlight] happens to already read false, e.g. after a
  /// previous scroll fully settled), that `forcePixels` would otherwise
  /// arrive here with [_autoScrollInFlight] still false -- a reduced-motion
  /// auto-scroll mistaking its OWN jump for a manual one and suspending
  /// itself. [_startingAutoScroll] is true for exactly that synchronous
  /// window regardless of which path `ensureVisible` takes, so checking it
  /// here too closes this specific ordering gap the same way it already
  /// closes the analogous one for [_onAncestorScrollingChanged].
  ///
  /// Any notification arriving while BOTH are false is treated as "not
  /// mine".
  ///
  /// Deliberately NOT keyed on `ScrollPosition.userScrollDirection` (an
  /// earlier version of this was): that field is set only by an actual
  /// drag or pointer-wheel gesture (`ScrollPositionWithSingleContext.
  /// applyUserOffset` / `.pointerScroll`), so it correctly ignores this
  /// widget's own driven scroll, but it ALSO stays idle for a keyboard
  /// `PageDown`/arrow-key scroll (`ScrollAction.invoke`, which calls
  /// `ScrollPosition.moveTo`, which for a non-zero duration calls
  /// `animateTo` -- a `DrivenScrollActivity`, exactly like this widget's
  /// own, never touching `userScrollDirection` either) and for a
  /// scrollbar-track tap -- genuine reader actions that field cannot see
  /// at all, so a design built on it would silently never suspend for
  /// them. See [_autoScrollInFlight]'s doc: the mechanism actually used
  /// here does not close that gap either, just in a different shape.
  void _onAncestorScrollChanged() {
    if (_autoScrollInFlight || _startingAutoScroll) return;
    _autoScrollSuspended = true;
  }

  /// Companion to [_onAncestorScrollChanged]: the ONE place
  /// [_autoScrollInFlight] is cleared once whatever this widget set moving
  /// stops being able to move `pixels` on its own -- see that field's doc
  /// for why this, rather than a per-call Future, is what it is grounded
  /// in.
  ///
  /// `ScrollPosition.beginActivity` sets `isScrollingNotifier.value =
  /// newActivity.isScrolling` -- so it reads false while the new activity
  /// taking over is one whose `isScrolling` is hard-coded false
  /// (`IdleScrollActivity`, at least; `HoldScrollActivity` reads false too,
  /// though that one is not this comment's concern), never while one
  /// `DrivenScrollActivity` supersedes another (both report
  /// `isScrolling: true`, so THAT transition never touches this notifier at
  /// all -- confirmed against the framework source, since a naive read of
  /// "false means clear the flag" that DID fire during a same-driven-to-
  /// driven transition would misread a still-ongoing SECOND auto-scroll as
  /// a manual one).
  ///
  /// [_startingAutoScroll] guards a NARROWER version of that same risk:
  /// `Scrollable.ensureVisible` can itself route through `jumpTo` (reduced
  /// motion, or a target already near the current position) rather than
  /// `animateTo`, and `jumpTo` DOES call `goIdle()` -- briefly, genuinely
  /// setting this notifier false -- before moving `pixels`. Left
  /// unguarded, a second `_autoScrollTo` call disposing a first one still
  /// in flight via THIS path would clear the flag here WHILE it is the one
  /// still legitimately scrolling. Suppressing the clear for that one
  /// call's own synchronous setup (see [_autoScrollTo]) is what keeps this
  /// listener's otherwise-unconditional "false means genuinely idle"
  /// reading correct in that case too -- any transition reachable from
  /// inside a call's own setup is that call's own business, never a later,
  /// genuinely external one.
  ///
  /// `ScrollPosition.pointerScroll` (a mouse wheel tick) calls `goIdle()`
  /// -- synchronously setting this notifier false -- BEFORE it sets it
  /// back to true and calls `forcePixels` (the call that reaches
  /// [_onAncestorScrollChanged]), all within that one synchronous method.
  /// Clearing [_autoScrollInFlight] the instant this notifier reads false
  /// therefore always happens strictly before that same tick's own
  /// pixel-change notification -- unlike a Dart [Future]'s `.whenComplete`,
  /// which is NEVER invoked synchronously (always deferred to a microtask)
  /// even for a future that completes synchronously, and so cannot promise
  /// that ordering; an earlier version of [_autoScrollInFlight]'s clearing
  /// was Future-based for exactly this reason, and missed a wheel tick
  /// that arrived in the gap.
  void _onAncestorScrollingChanged() {
    if (_startingAutoScroll) return;
    if (_observedPosition?.isScrollingNotifier.value == false) {
      _autoScrollInFlight = false;
    }
  }

  void _onActiveIndexChanged() {
    if (!mounted) return;
    final newIndex = widget.activeIndex?.value;
    final changed = newIndex != _lastActiveIndex;
    _lastActiveIndex = newIndex;
    // Rebuilds so the accent bar / tint actually move -- this widget reads
    // `activeIndex.value` directly in [build] rather than through a
    // `ValueListenableBuilder`, since the auto-scroll side effect below has
    // to live somewhere imperative anyway.
    setState(() {});
    // A notification whose value did NOT actually change invalidates
    // nothing: it is not what "a newer notification superseded this one"
    // means (see the generation comment below), and bumping the generation
    // here regardless would wrongly cancel an EARLIER, still-current
    // notification's pending callback for no reason -- e.g. `activeIndex`
    // genuinely changing to `i`, then (before that callback's frame)
    // `didUpdateWidget` swapping in a REPLACEMENT listenable that happens
    // to already be sitting on that SAME `i`: the swap's own call here
    // sees no change at all, and must leave the still-relevant pending
    // callback for `i` alone.
    if (!changed) return;
    // Bumped only for a REAL change (including one that returns just below
    // without scheduling anything, i.e. a change TO null) -- see the
    // generation check inside the deferred callback for why even that
    // still has to invalidate whichever EARLIER notification's callback is
    // pending.
    final notificationGeneration = ++_activeIndexNotificationGeneration;
    if (newIndex == null) return;
    // Deferred to the frame this `setState` itself schedules, rather than
    // resolved immediately against [_ordered]: that list is a cache
    // refreshed only inside [build], so a notification that arrives
    // synchronously alongside (or ahead of) a `widget.turns` update that has
    // not been rebuilt yet would otherwise resolve [newIndex] against the
    // WRONG, stale ordering -- e.g. late recording data both recomputing
    // the controller's active index AND handing this widget a reordered
    // turn list in the same tick (spec section 1's "recompute on late
    // data"). Waiting for the very next frame guarantees [_ordered]
    // reflects whatever `widget.turns` is by the time [newIndex] is
    // actually resolved to a turn -- PROVIDED the caller updates both the
    // controller and `widget.turns` within that same tick/frame (the
    // pattern the spec itself describes: one rebuild reacting to one future
    // completing). A caller that updates them across two SEPARATE frames
    // breaks that contract, and no amount of deferral inside this widget
    // alone can recover the right turn at that point -- there is nothing
    // here to tell a now-stale index from a current one.
    //
    // `isPlaying`, and whether this is still the LATEST notification, are
    // both re-read here, at the moment they actually gate something, rather
    // than trusted from the instant this method was entered: a newer
    // notification may have already superseded this one by the time this
    // frame ends. The check is a GENERATION compare, not
    // `widget.activeIndex?.value != newIndex` (an earlier version of this
    // was): a value compare lets an `i -> j -> i` sequence through TWICE --
    // the callback captured for the first `i` also matches the CURRENT
    // value once the third notification lands back on it, even though it
    // is no longer the latest notification -- calling `_autoScrollTo(i)`
    // an extra, redundant time (harmless on its own, since
    // [_autoScrollInFlight] is read fresh off `isScrollingNotifier` at the
    // end of every call regardless of how many ran, but not what "only the
    // latest notification acts" is supposed to mean).
    // Comparing notification ORDER instead of VALUE admits no such
    // coincidence: exactly one notification is ever the latest, and (per
    // the no-op guard above) only a notification that is an ACTUAL change
    // ever gets to invalidate an earlier one in the first place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (notificationGeneration != _activeIndexNotificationGeneration) return;
      if (widget.isPlaying?.value ?? false) _autoScrollTo(newIndex);
    });
  }

  void _onIsPlayingChanged() {
    if (!mounted) return;
    // The master gate (the class doc, [_karaokeEnabled]): none of
    // karaoke's isPlaying-driven behaviour may run while [TurnTimeline.
    // activeIndex] is null. A real notification cannot reach here in that
    // state any more ([_syncIsPlayingListener] never attaches this
    // listener while the gate is closed), and [_syncIsPlayingListener]'s
    // own direct call to this method already only fires when it actually
    // changes what is attached -- which itself cannot happen while the gate
    // stays closed throughout (its target is `null` both before and after,
    // so its own `identical` check short-circuits first). This guard is
    // therefore belt-and-suspenders against a caller of this method that
    // does not go through [_syncIsPlayingListener], not a case reachable
    // today -- kept because a private method's correctness should not
    // depend on every future caller remembering to gate at the call site.
    if (!_karaokeEnabled) return;
    final now = widget.isPlaying?.value ?? false;
    final was = _lastIsPlaying;
    _lastIsPlaying = now;
    // RESUME on a false->true edge (spec section 4). No rebuild needed --
    // nothing rendered depends on [isPlaying] by itself, only on
    // [TurnTimeline.activeIndex].
    if (!was && now) {
      _autoScrollSuspended = false;
    }
  }

  void _autoScrollTo(int index) {
    if (_autoScrollSuspended) return;
    if (index < 0 || index >= _ordered.length) return;
    final targetContext =
        _keysByIdentity[_ordered[index].identityKey]?.currentContext;
    if (targetContext == null) return;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Guards [_onAncestorScrollingChanged] against ITS OWN reentrant call:
    // `Scrollable.ensureVisible` takes a `jumpTo` path (not the ordinary
    // `animateTo`-driven one) both for reduced motion and whenever the
    // target already sits near the CURRENT position, and `jumpTo` calls
    // `goIdle()` -- synchronously disposing whatever activity was already
    // running (a still-in-flight EARLIER auto-scroll this same call is
    // about to supersede) and, exactly like a real wheel tick, briefly
    // setting `isScrollingNotifier` false before this call's own
    // `forcePixels` sets it true again. Left unguarded, that brief false
    // reading would reach [_onAncestorScrollingChanged] and clear
    // [_autoScrollInFlight] WHILE this call is the one still legitimately
    // scrolling. Suppressing the clear for the duration of this call's own
    // (synchronous) setup is sufficient: any transition `ensureVisible`
    // itself causes here is part of ITS OWN startup, never a later,
    // genuinely external one.
    _startingAutoScroll = true;
    try {
      Scrollable.ensureVisible(
        targetContext,
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
    } finally {
      _startingAutoScroll = false;
    }
    // Read directly, synchronously, right here -- rather than trusted from
    // having merely CALLED `ensureVisible` above -- because that call can
    // be a complete no-op: if the target is already fully visible (e.g.
    // against wherever an EARLIER, still-running auto-scroll currently
    // sits), `ensureVisible` touches no activity at all, and there is
    // nothing to be "in flight" about unless something ELSE already was.
    // By the time `ensureVisible` returns, everything it did (or didn't
    // do) to the activity has already happened SYNCHRONOUSLY -- starting a
    // new `DrivenScrollActivity` sets `isScrollingNotifier` true before the
    // call returns, same as leaving an existing one untouched leaves it
    // however it already was -- so this read is never stale.
    _autoScrollInFlight = _observedPosition?.isScrollingNotifier.value ?? false;
  }

  /// RESUME on the next seek tap (spec section 4), then forward to the
  /// caller -- a deliberate seek is the reader opting back into following
  /// the recording, same as playback resuming on its own.
  void _handleSeekTap(int index) {
    _autoScrollSuspended = false;
    widget.onSeekTurn?.call(index);
  }

  GlobalKey _keyFor(String identityKey) =>
      _keysByIdentity.putIfAbsent(identityKey, GlobalKey.new);

  void _pruneKeys() {
    final live = {for (final turn in _ordered) turn.identityKey};
    _keysByIdentity.removeWhere(
      (identityKey, _) => !live.contains(identityKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to say, not even a placeholder: an empty call is a call this
    // widget was never asked to describe, and a caller silently gets back
    // silence rather than an empty box to explain away.
    if (widget.turns.isEmpty) {
      _ordered = const [];
      _keysByIdentity.clear();
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    _ordered = TurnTimeline._byTime(widget.turns);
    final karaokeEnabled = _karaokeEnabled;
    _pruneKeys();
    final activeIndex = widget.activeIndex?.value;

    return Column(
      // Explicit, not left to the default: a Column's main-axis size
      // defaults to filling whatever its parent offers, and the parent this
      // widget is built for is someone else's scrollable -- which hands its
      // children UNBOUNDED height on purpose, so each can report its own
      // natural size. This widget must size to its CONTENT there, not to
      // however much of that unbounded space it happens to be handed; a
      // ListView lays out lazily, so anything a caller places after this
      // widget only renders if this one reports a sane height first.
      mainAxisSize: MainAxisSize.min,
      // Stretch, not start: each turn is a Row that aligns ITSELF to the
      // speaker's side, and it can only do that if it is handed the full
      // width to align within.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _ordered.length; i++)
          Padding(
            key: karaokeEnabled ? _keyFor(_ordered[i].identityKey) : null,
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : TurnTimeline._gapAbove(_ordered, i),
            ),
            child: _Turn(
              turn: _ordered[i],
              showHeader: TurnTimeline._opensATurn(_ordered, i),
              theme: theme,
              l10n: l10n,
              isActive: karaokeEnabled && activeIndex == i,
              onSeekTurn: (karaokeEnabled && widget.onSeekTurn != null)
                  ? () => _handleSeekTap(i)
                  : null,
            ),
          ),
      ],
    );
  }
}

class _Turn extends StatelessWidget {
  final CallTurn turn;
  final bool showHeader;
  final ThemeData theme;
  final L10n l10n;

  /// Whether this is the turn the "Full call" recording is playing right
  /// now. Always false while karaoke is disabled -- see [TurnTimeline]'s
  /// class doc.
  final bool isActive;

  /// Seeks the recording to this turn when its time is tapped, or null when
  /// this turn offers no seek affordance (karaoke disabled, no caller
  /// callback, or -- checked here, since it is a fact about THIS turn, not
  /// about the widget as a whole -- [CallTurn.audioStartMs] is null). Never
  /// wired to anything but the time/avatar: the bubble's transcript text
  /// stays a plain, selectable sibling.
  final VoidCallback? onSeekTurn;

  const _Turn({
    required this.turn,
    required this.showHeader,
    required this.theme,
    required this.l10n,
    this.isActive = false,
    this.onSeekTurn,
  });

  @override
  Widget build(BuildContext context) {
    final label = turn.isMe ? l10n.you : turn.name;
    final scheme = theme.colorScheme;

    // The chat's own convention, followed rather than reinvented: a reader
    // opening this screen has just come from the timeline, and a call is a
    // conversation between the same two people. Own turns sit right in the
    // primary fill, the peer's sit left in the surface fill, and the corner
    // adjacent to a same-speaker neighbour is squared off -- the shape that
    // says "still them" without repeating a name. See `message.dart`, which
    // is where these values come from.
    final baseColor = turn.isMe ? scheme.primary : scheme.surfaceContainerHigh;
    // ACTIVE HIGHLIGHT is never colour alone (see the accent `border` below
    // too): a wash blended OVER the turn's own fill, not a flat swap to it the
    // way `chat_list_item.dart:67` tints a chat row -- that row has no fill of
    // its own to protect, but replacing an own/peer bubble's colour outright
    // would erase the one thing that tells the two sides apart mid-call. The
    // wash LIFTS the fill rather than muting it: an own turn is already the
    // vivid `primary`, so a `secondaryContainer` wash greyed it out -- it takes
    // a `primaryContainer` lift instead (brighter, still its own colour); the
    // peer's surface fill has room for the softer `secondaryContainer` wash.
    final bubbleColor = !isActive
        ? baseColor
        : Color.alphaBlend(
            (turn.isMe ? scheme.primaryContainer : scheme.secondaryContainer)
                .withAlpha(turn.isMe ? 140 : 90),
            baseColor,
          );
    final textColor = turn.isMe ? scheme.onPrimary : scheme.onSurface;

    const hardCorner = Radius.circular(4);
    const roundedCorner = Radius.circular(AppConfig.borderRadius);
    final radius = BorderRadius.only(
      topLeft: !turn.isMe && !showHeader ? hardCorner : roundedCorner,
      topRight: turn.isMe && !showHeader ? hardCorner : roundedCorner,
      bottomLeft: roundedCorner,
      bottomRight: roundedCorner,
    );

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: radius,
        // A single accent-coloured side (the rest default to `BorderSide.
        // none`) combined with a `borderRadius` hits `BoxBorder`'s "visible
        // colours are uniform" fast path rather than the assertion that
        // guards a genuinely multi-coloured border ("A borderRadius can only
        // be given for borders with uniform colours") -- verified against
        // the framework source, since the two look identical until painted.
        // `BorderDirectional`, not `Border`, so the accent lands on the
        // reader's leading edge under RTL too.
        border: isActive
            ? BorderDirectional(
                start: BorderSide(color: scheme.primary, width: 3),
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The peer is named; you are not. A chat does not label your
                // own messages with your name and neither does this, but the
                // TIME is on every opening turn either way -- it is the one
                // thing a transcript is for.
                if (!turn.isMe) ...[
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Nothing at all for a turn whose device never said how exact
                // its times are, and "by 0:45" when only its chunk bounds it.
                // The bubble and the side still say whose words these are, so
                // a turn without a stamp still reads as theirs; only the claim
                // we cannot support is left off.
                if (_stampFor(turn) case final stamp?)
                  _buildStamp(
                    stamp,
                    theme.textTheme.bodySmall?.copyWith(
                      color: textColor.withAlpha(178),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          TranscriptTokens(
            text: turn.text,
            langCode: turn.langCode,
            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: turn.isMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        // Only the peer gets a face, on their side, exactly as the chat does:
        // you know who you are. The gutter is reserved on a continuation turn
        // so the bubble below lines up with the one above it rather than
        // sliding under the avatar.
        if (!turn.isMe) ...[
          SizedBox(
            width: TurnTimeline._avatarSize,
            child: showHeader
                ? Avatar(
                    userId: turn.senderId,
                    mxContent: turn.avatarUrl,
                    // The speaker's OWN name, never `label`: for your own
                    // turns that word is "You", and the fallback would draw a
                    // circle with a "Y" in it for every user alive.
                    name: turn.name,
                    size: TurnTimeline._avatarSize,
                  )
                : null,
          ),
          const SizedBox(width: TurnTimeline._avatarGap),
        ],
        // Bounded so a long turn wraps into a bubble instead of a full-width
        // slab, which is what makes the two sides read as a conversation.
        Flexible(
          child: Align(
            alignment: turn.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: bubble,
            ),
          ),
        ),
      ],
    );
  }

  /// What this turn's header may say about when it happened, or null when it
  /// may say nothing.
  String? _stampFor(CallTurn turn) => switch (turn.time) {
    TurnTime.exact => _stamp(turn.at),
    // "by 0:45", not "0:00-0:45". A range printed beside a turn reads as how
    // long the turn LASTED, which is a second false claim in place of the
    // first, and its lower edge is an estimate this feature cannot prove.
    //
    // Rounded UP, unlike every other stamp in this app. Truncating a bound
    // understates it: a turn known to have been said by 45.999s would print
    // "by 0:45", which is a moment it may well have been said after. The whole
    // value of this label is that the reader may rely on it, so the one
    // direction it may err in is the safe one.
    TurnTime.atOrBefore => l10n.callTranscriptByTime(
      _stamp(turn.at, roundUp: true),
    ),
    TurnTime.unstated => null,
  };

  /// `m:ss`, matching the stamp `CallRecord`'s own fallback text and the live
  /// call timer already print elsewhere in this feature -- minutes uncapped,
  /// seconds padded to two digits.
  ///
  /// [roundUp] is for a stamp that is an UPPER BOUND rather than a moment; see
  /// [_stampFor].
  static String _stamp(Duration at, {bool roundUp = false}) {
    final seconds = roundUp ? (at.inMilliseconds + 999) ~/ 1000 : at.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// The printed stamp, made a seek target when [onSeekTurn] and
  /// [CallTurn.audioStartMs] both allow it -- an unchanged, plain [Text]
  /// otherwise (in particular, always, while karaoke is disabled: [onSeekTurn]
  /// is only ever non-null when it is not).
  ///
  /// [Semantics.excludeSemantics] folds the [Text]'s own auto-generated node
  /// into this one: without it a screen reader would announce the printed
  /// stamp AND this label back to back for the same tap target.
  Widget _buildStamp(String stamp, TextStyle? style) {
    final seek = onSeekTurn;
    final startMs = turn.audioStartMs;
    final text = Text(stamp, style: style);
    if (seek == null || startMs == null) return text;

    return Semantics(
      button: true,
      // `excludeSemantics` folds the descendant `GestureDetector`'s own
      // auto-generated semantics node into this one (see the label comment
      // below for why that node alone would double-announce) -- but it also
      // DROPS that descendant's tap ACTION along with its node, so an
      // assistive-technology activation (e.g. a screen reader's
      // double-tap-to-activate) would otherwise land on a button with a
      // label and no way to invoke it. `onTap` here restores that action on
      // the node this widget keeps; the `GestureDetector`'s own `onTap`
      // below still separately serves an ordinary touch/mouse tap, which
      // never reaches semantics at all.
      onTap: seek,
      excludeSemantics: true,
      // The RECORDING-RELATIVE start, not [stamp]: an approximate turn's
      // printed "by 0:07" is an upper BOUND (see [_stampFor]), which can sit
      // several seconds after where a tap actually seeks to.
      //
      // `callTranscriptSeekTo`, a dedicated arb entry, not the `play
      // ({fileName})` string reused for shared-file playback elsewhere in
      // this app: spec section 4's D4 asks for "Play from {time}"
      // specifically, so a screen reader hears that the tap SEEKS the
      // recording to a position, not that it plays this turn as a clip of
      // its own -- which a bare "Play {time}" would suggest instead.
      //
      // A dedicated key DOES cost roughly one change per locale -- the same
      // order of magnitude this feature's first pass worried about, just
      // not the mechanism it named. The generated `lib/l10n/l10n_*.dart`
      // this adds a getter to is gitignored build output, regenerated by
      // `fvm flutter gen-l10n`, never committed: genuinely free. The real
      // cost is the OTHER locales' own tracked `intl_<locale>.arb` SOURCE
      // files (~115 of them) and `ai-translated-keys.json`'s provenance
      // record, which this repo's `l10n_sync_check` CI gate requires
      // translated before a PR merges
      // (`.github/instructions/localization.instructions.md`).
      //
      // THIS change adds the ENGLISH key only, and intentionally excludes
      // that backfill (`uv run scripts/translate/translate_new_keys.py`
      // then `fvm flutter gen-l10n` -- the former a real, billed
      // Vertex/Gemini call) from its own scope: every OTHER locale keeps
      // falling back to English for this one key, exactly as this repo's
      // l10n model already does for any untranslated key, until a
      // separate, explicitly-authorized pass backfills it.
      label: l10n.callTranscriptSeekTo(_stamp(Duration(milliseconds: startMs))),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: seek,
          child: text,
        ),
      ),
    );
  }
}
