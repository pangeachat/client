import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';
import 'package:fluffychat/routes/chat/calls/transcript_assembly.dart';
import 'package:fluffychat/routes/chat/calls/transcript_repo.dart';

/// Opens the transcript of one finished call.
///
/// A dialog rather than a route: it is read from a card in the timeline and
/// dismissed back to it, and [FullWidthDialog] already gives a full screen on
/// a phone and a panel on a wide window.
Future<void> showCallTranscript(
  BuildContext context, {
  required Room room,
  required String callKey,
  required String? callerId,
}) => showDialog(
  context: context,
  useRootNavigator: false,
  builder: (_) => FullWidthDialog(
    maxWidth: 640,
    maxHeight: 800,
    dialogContent: CallTranscriptView(
      room: room,
      callKey: callKey,
      callerId: callerId,
    ),
  ),
);

/// Who could have written a half of THIS CALL.
///
/// Taken from the call, not from the room. Room membership was the obvious
/// proxy and it is the wrong one: it answers "who has ever been in this
/// conversation", so every person who ever left the room earned a permanent
/// "no transcript from them" section on every future call in it, having never
/// been on any of them. The two questions only coincide in a room nobody has
/// left.
///
/// A 1:1 call has exactly two sides: whoever placed it, and whoever they
/// called. [callerId] comes off the call's own card, so it names the caller
/// even if they have since left the room -- which is the case room membership
/// was reached for in the first place, and this covers it without the rest.
///
/// [peerId] is the other side. The reader is always one of the two, so between
/// this account and the caller only one gap remains, and the room's direct-chat
/// peer fills it.
///
/// Needed at all because assembly reports a participant who wrote nothing as
/// ABSENT rather than omitting them, and DROPS a half from anyone not named --
/// which is what stops a stranger writing themselves a section. Both behaviours
/// depend on this list being right.
@visibleForTesting
List<String> callParticipants({
  required String? me,
  required String? callerId,
  required String? peerId,
}) {
  final ids = <String>{?me, ?callerId, ?peerId};

  // Sorted, so the sections do not reorder between two reads of the same call.
  return ids.toList()..sort();
}

class CallTranscriptView extends StatefulWidget {
  final Room room;
  final String callKey;

  /// Who placed the call, off its own card. Null on a card old enough not to
  /// carry one, where the room's peer is the best available answer.
  final String? callerId;

  /// Injected only by tests, which have no homeserver to read from.
  final RelationsFetcher? fetcher;

  const CallTranscriptView({
    required this.room,
    required this.callKey,
    required this.callerId,
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

  Future<CallTranscript> _load() => fetchCallTranscript(
    fetch: widget.fetcher ?? relationsFetcherFor(widget.room.client),
    roomId: widget.room.id,
    callKey: widget.callKey,
    expectedSenders: callParticipants(
      me: widget.room.client.userID,
      callerId: widget.callerId,
      peerId: widget.room.directChatMatrixID,
    ),
    encrypted: widget.room.encrypted,
  );

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (transcript.readerStoppedEarly)
                _Caveat(text: l10n.callTranscriptStoppedEarly),
              for (final half in transcript.halves)
                _HalfSection(
                  half: half,
                  name: _nameFor(half.senderId, l10n),
                  theme: theme,
                  l10n: l10n,
                ),
            ],
          );
        },
      ),
    );
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
          text: half.state == HalfState.incomplete
              ? l10n.callTranscriptNothingRead(name)
              : l10n.callTranscriptSaidNothing(name),
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
