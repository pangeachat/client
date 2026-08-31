import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/turn_timeline.dart';

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

/// Who could have written a half of THIS CALL.
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
@visibleForTesting
List<String> callParticipants({required String? me, required String? peerId}) {
  final ids = <String>{?me, ?peerId};

  // Sorted, so the sections do not reorder between two reads of the same call.
  return ids.toList()..sort();
}

class CallTranscriptView extends StatefulWidget {
  final Room room;
  final String callKey;

  /// Injected only by tests, which have no homeserver to read from.
  final RelationsFetcher? fetcher;

  const CallTranscriptView({
    required this.room,
    required this.callKey,
    this.fetcher,
    super.key,
  });

  @override
  State<CallTranscriptView> createState() => _CallTranscriptViewState();
}

class _CallTranscriptViewState extends State<CallTranscriptView> {
  late Future<CallTranscript> _transcript;

  @override
  void initState() {
    super.initState();
    _transcript = _load();
  }

  Future<CallTranscript> _load() {
    // Worked out ONCE and both facts carried together: who we think took part,
    // and whether that is an answer or a guess. Read separately, the second
    // one is what gets forgotten -- and a guess presented as an answer is how
    // a real half comes to be discarded in silence.
    final peer = callPeerOf(widget.room);
    return fetchCallTranscript(
      fetch: widget.fetcher ?? relationsFetcherFor(widget.room.client),
      roomId: widget.room.id,
      callKey: widget.callKey,
      selfId: widget.room.client.userID,
      expectedSenders: callParticipants(
        me: widget.room.client.userID,
        peerId: peer,
      ),
      participantsKnown: peer != null,
      encrypted: widget.room.encrypted,
    );
  }

  // A block body, not an arrow: an arrow returns the assignment's value, and
  // setState refuses a callback that returns a Future. Retry did nothing.
  void _retry() {
    setState(() {
      _transcript = _load();
    });
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // One caveat per REASON the read could not conclude, and every
              // reason that applies. They used to share a single line -- the
              // one about a call being too long -- so a room we could not
              // decrypt and a peer we could not name were both explained away
              // as length. That is the failure this whole feature is built
              // against, reached from the only direction still open: not a
              // claim about what somebody said, but a confident, specific,
              // wrong account of why we cannot say.
              //
              // Not one winner. Unlike the clock caveats below, none of these
              // makes another WRONG -- they are independent facts about one
              // read, and suppressing a true one to keep the list short is the
              // same collapse in miniature. Ordered by how much of the screen
              // each explains: encryption accounts for the whole of it, an
              // unnamed participant for a person missing from it, our own
              // ceiling for words missing from a section that is there.
              if (transcript.readLimits.contains(
                TranscriptReadLimit.roomEncrypted,
              ))
                _Caveat(text: l10n.callTranscriptRoomEncrypted),
              if (transcript.readLimits.contains(
                TranscriptReadLimit.participantsUnknown,
              ))
                _Caveat(text: l10n.callTranscriptParticipantsUnknown),
              if (transcript.readLimits.contains(
                TranscriptReadLimit.readerCeiling,
              ))
                _Caveat(text: l10n.callTranscriptStoppedEarly),
              if (clocksUnreconciled)
                _Caveat(text: l10n.callTranscriptUnreconciledClocks),
              if (approximate)
                _Caveat(text: l10n.callTranscriptApproximateTimes),
              if (unstated) _Caveat(text: l10n.callTranscriptUnstatedTimes),

              if (turns.isNotEmpty)
                TurnTimeline(turns: turns)
              else
                for (final half in transcript.halves)
                  _HalfSection(
                    half: half,
                    name: _nameFor(half.senderId, l10n),
                    theme: theme,
                    l10n: l10n,
                  ),

              // BELOW the conversation, never inside it. Absent, silent and
              // unreadable are facts about a HALF and have no moment they
              // happened at; giving them a place in the timeline would invent
              // one, at an instant nobody spoke. The per-speaker view says
              // these things itself, inside each section, so they are only
              // added out here when the timeline is what is drawn.
              if (turns.isNotEmpty)
                for (final note in notes) _Muted(text: note),
            ],
          );
        },
      ),
    );
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
  List<CallTurn> _turnsOf(CallTranscript transcript, L10n l10n) {
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
    final start = (vouched.isNotEmpty ? vouched : keys).reduce(
      (a, b) => a < b ? a : b,
    );

    return [
      for (final entry in placed)
        for (final segment in entry.half.segments)
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
          ),
    ];
  }

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
    if (half.saidNothing) return l10n.callTranscriptSaidNothing(name);
    // Ahead of the general empty-half line, which says nothing could be READ
    // from what they said -- true of a corrupt or unreadable half, and wrong
    // here: there was nothing to read because we never sent any of it.
    if (half.audioSuppressedLocally) {
      return l10n.callTranscriptNoSpeechDetected(name);
    }
    if (half.segments.isEmpty) return l10n.callTranscriptNothingRead(name);
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

    if (half.segments.isEmpty) {
      return [
        _Muted(
          // Asked of the half rather than re-derived here. "They said nothing"
          // is a definite claim about a person, and the only thing separating
          // it from "we could not find out" is which state an empty half is
          // in -- a distinction too easy to invert at each site that needs it.
          //
          // Three answers, not two: an empty half whose audio our own detector
          // held back was never read by anything, and saying either that they
          // were silent or that we could not read them names the wrong cause.
          text: half.saidNothing
              ? l10n.callTranscriptSaidNothing(name)
              : half.audioSuppressedLocally
              ? l10n.callTranscriptNoSpeechDetected(name)
              : l10n.callTranscriptNothingRead(name),
        ),
      ];
    }

    return [
      for (final segment in half.segments)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(
            segment.text,
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
