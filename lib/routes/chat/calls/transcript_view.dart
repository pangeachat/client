import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/routes/chat/audio_player.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_event.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_merged_selection.dart';
import 'package:fluffychat/routes/chat/calls/call_audio_repo.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
import 'package:fluffychat/routes/chat/calls/transcript_segments.dart';
import 'package:fluffychat/routes/chat/calls/transcript_tokens.dart';
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
    setState(_load);
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

              // The conversation timeline and the recordings both read the
              // call's audio, and share ONE resolution of it here: the merged
              // "Full call" row is drawn beneath the turns, AND its start is the
              // origin those turns' times are measured from (see [_turnsOf]), so
              // a printed time is a position in that recording. Nested futures,
              // each `data ?? const []`, so the FIRST frame renders with no
              // recording and the first-turn origin -- the transcript is on
              // screen at once, and a slow or failed recordings/merged read
              // never holds it up or takes it down; the row and the
              // recording-anchored times just appear when the read lands. See
              // `_loadRecordings` / `_loadMerged`.
              FutureBuilder<List<CallAudioRecording>>(
                future: _recordings,
                builder: (context, recordingsSnapshot) {
                  final recordings =
                      recordingsSnapshot.data ?? const <CallAudioRecording>[];
                  return FutureBuilder<List<CallAudioMergedRecording>>(
                    future: _merged,
                    builder: (context, mergedSnapshot) {
                      final mergedList =
                          mergedSnapshot.data ??
                          const <CallAudioMergedRecording>[];
                      // The ONE merged row to show, or null when there is no
                      // merge or the call switched devices mid-way (more than
                      // two halves, out of v1 scope). Suppression is keyed on
                      // the number of halves the room actually shows, which is
                      // why the count comes from `recordings` rather than from
                      // the merge's own coverage.
                      final mergedRow = selectMergedRow(
                        mergedList,
                        recordings.length,
                      );

                      // Rebuilt here, not reused from above, because only here
                      // is the merged row known: with one on screen the turn
                      // times anchor to its start; without one they keep the
                      // first-turn origin. Re-anchoring shifts every time by one
                      // constant, so it changes no order and no time KIND -- the
                      // eligibility and the caveats worked out above still hold.
                      final displayTurns = turns.isEmpty
                          ? const <CallTurn>[]
                          : _turnsOf(
                              transcript,
                              l10n,
                              recordingOriginMs:
                                  mergedRow?.content.mergedStartSfuMs,
                              mergedRow: mergedRow,
                              recordings: recordings,
                            );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (displayTurns.isNotEmpty)
                            TurnTimeline(turns: displayTurns)
                          else
                            for (final half in transcript.halves)
                              _HalfSection(
                                half: half,
                                name: _nameFor(half.senderId, l10n),
                                theme: theme,
                                l10n: l10n,
                              ),

                          // BELOW the conversation, never inside it. Absent,
                          // silent and unreadable are facts about a HALF and
                          // have no moment they happened at; a place in the
                          // timeline would invent one, at an instant nobody
                          // spoke. The per-speaker view says these itself, so
                          // they are added out here only when the timeline is
                          // what is drawn.
                          if (displayTurns.isNotEmpty)
                            for (final note in notes) _Muted(text: note),

                          // The recording rows, on the same footing as the
                          // notes above: a recording is a fact about the CALL,
                          // not a moment inside it, so it earns no place inside
                          // the conversation. The merged full-call row FIRST,
                          // above the per-device halves.
                          if (mergedRow != null)
                            ..._mergedRecordingSection(mergedRow, theme, l10n),
                          ..._recordingsSection(recordings, theme, l10n),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
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

  /// The merged, full-call recording rendered as the PRIMARY row, above the
  /// per-device halves -- or nothing when [row] is null (no merge for this
  /// call, or a mid-call device switch the player suppresses; see
  /// [selectMergedRow]).
  ///
  /// Mirrors [_recordingsSection]'s own header-then-player shape: a "Full call"
  /// heading styled exactly as the "Recordings" heading it sits above, then one
  /// [AudioPlayerWidget] fed the SAME relabel-to-`m.audio` event the halves use
  /// (see [_mergedRecordingEvent]) and keyed by the merged event's OWN id.
  List<Widget> _mergedRecordingSection(
    CallAudioMergedRecording row,
    ThemeData theme,
    L10n l10n,
  ) => [
    Text(
      l10n.callTranscriptFullCall,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 6),
    AudioPlayerWidget(
      // The same relabel the halves rely on -- see `_mergedRecordingEvent` and
      // `_recordingEvent` for why a `pangea.call_audio_merged` event cannot be
      // handed to the player directly.
      _mergedRecordingEvent(row, widget.room),
      color: theme.colorScheme.primary,
      linkColor: theme.colorScheme.primary,
      fontSize: 14,
      eventId: row.eventId,
      roomId: widget.room.id,
      senderId: row.senderId,
    ),
    const SizedBox(height: 12),
  ];

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
