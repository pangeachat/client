import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/routes/chat/calls/call_timeline_event.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (transcript.readerStoppedEarly)
                _Caveat(text: l10n.callTranscriptStoppedEarly),

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
  List<CallTurn> _turnsOf(CallTranscript transcript, L10n l10n) {
    final me = widget.room.client.userID;
    return [
      for (final half in transcript.halves)
        for (final segment in half.segments)
          CallTurn(
            senderId: half.senderId,
            name: _nameFor(half.senderId, l10n),
            isMe: half.senderId == me,
            at: Duration(milliseconds: segment.atMs!),
            text: segment.text,
          ),
    ];
  }

  /// What still needs saying about a half once its words are in the timeline,
  /// or null when the half is a clean record and needs nothing.
  String? _noteFor(TranscriptHalf half, L10n l10n) {
    final name = _nameFor(half.senderId, l10n);
    if (half.state == HalfState.absent) return l10n.callTranscriptNone(name);
    if (half.saidNothing) return l10n.callTranscriptSaidNothing(name);
    if (half.segments.isEmpty) return l10n.callTranscriptNothingRead(name);
    if (half.state == HalfState.incomplete) {
      return l10n.callTranscriptPartial(name);
    }
    return null;
  }

  String _nameFor(String userId, L10n l10n) {
    if (userId == widget.room.client.userID) return l10n.you;
    return widget.room
        .unsafeGetUserFromMemoryOrFallback(userId)
        .calcDisplayname();
  }
}

/// One speaker's side of the call.
///
/// Per speaker, not interleaved. The two halves are recorded independently on
/// two devices with no shared clock, so ordering one against the other would
/// be a guess presented as a record of who said what when.
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
          text: half.saidNothing
              ? l10n.callTranscriptSaidNothing(name)
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
