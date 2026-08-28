import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';

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

  /// Elapsed time from the FIRST SPOKEN TURN of the call, not from the moment
  /// the call connected. Already the number this widget prints, not a
  /// wall-clock instant left for it to convert.
  ///
  /// The distinction is deliberate and worth knowing, because it means this
  /// clock can disagree with the duration the call card shows. The transcript
  /// wire carries one absolute time per segment and nothing about when capture
  /// began, so the moment the call connected is not recoverable here; ringing,
  /// greetings before anyone spoke, and any opening silence are all outside
  /// what this can see. Normalising to the earliest turn is therefore the only
  /// origin the data supports, and it is also the one a reader wants: 0:00 is
  /// the first thing anybody said.
  ///
  /// If these times ever need to line up with the call's own duration, the
  /// call's start has to be written into the transcript event at capture time
  /// -- a wire change, not a display one.
  final Duration at;

  final String text;

  const CallTurn({
    required this.senderId,
    required this.name,
    required this.isMe,
    this.avatarUrl,
    required this.at,
    required this.text,
  });
}

/// The turn-by-turn view of a call transcript: one column, ordered by
/// [CallTurn.at].
///
/// A call is a shared recording, not messages each side sent to the other, so
/// drawing it as opposing chat bubbles would claim a back-and-forth the audio
/// itself does not distinguish. It stays one column for that reason, and the
/// rule doing most of the work of making a plain list of turns read as a
/// conversation anyway is this: a speaker CHANGE draws an avatar, a name and
/// a time; a turn from the same speaker as the one before it draws none of
/// that, and indents underneath.
///
/// Deliberately not a [ListView] or [SliverList] itself -- the caller already
/// owns a scrollable (the transcript dialog's, today), and a scrollable
/// nested inside another only fights it for gesture ownership. A transcript
/// is read start to finish, not queried at an offset, so there is nothing to
/// buy by making this one lazy.
class TurnTimeline extends StatelessWidget {
  /// Need not arrive sorted by [CallTurn.at] -- [build] sorts it. A caller
  /// that forgets to order its own list is not a caller this widget trusts
  /// to have gotten it right; an unenforced precondition is a hazard, not a
  /// contract, and the one direction it can fail in here is a teacher reading
  /// a call in the wrong order with full confidence that it is correct.
  final List<CallTurn> turns;

  const TurnTimeline({required this.turns, super.key});

  static const double _avatarSize = 32;
  static const double _avatarGap = 12;

  @override
  Widget build(BuildContext context) {
    // Nothing to say, not even a placeholder: an empty call is a call this
    // widget was never asked to describe, and a caller silently gets back
    // silence rather than an empty box to explain away.
    if (turns.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final ordered = _byTime(turns);

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
        for (var i = 0; i < ordered.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gapAbove(ordered, i)),
            child: _Turn(
              turn: ordered[i],
              showHeader: _opensATurn(ordered, i),
              theme: theme,
              l10n: l10n,
            ),
          ),
      ],
    );
  }

  /// Sorted by [CallTurn.at], stable by construction rather than by trusting
  /// `List.sort` to behave that way -- it is not guaranteed to.
  ///
  /// Two turns can legitimately share one instant: the backend's own
  /// arithmetic stamps every chunk cut from one oversized audio batch with a
  /// position derived from frame count, and a batch split into several
  /// chunks in a single pass can produce equal timestamps for chunks that
  /// were still spoken in a real order. Sorting the ORIGINAL INDEX alongside
  /// the timestamp turns every comparison into a strict total order, so two
  /// same-instant turns keep the order they were given -- the order they
  /// were spoken -- regardless of which algorithm runs underneath, and
  /// regardless of how many times this rebuilds.
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
    return current.at - previous.at >= _newTurnAfter;
  }
}

class _Turn extends StatelessWidget {
  final CallTurn turn;
  final bool showHeader;
  final ThemeData theme;
  final L10n l10n;

  const _Turn({
    required this.turn,
    required this.showHeader,
    required this.theme,
    required this.l10n,
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
    final bubbleColor = turn.isMe
        ? scheme.primary
        : scheme.surfaceContainerHigh;
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
      decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
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
                Text(
                  _stamp(turn.at),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor.withAlpha(178),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          SelectableText(
            turn.text,
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

  /// `m:ss`, matching the stamp `CallRecord`'s own fallback text and the live
  /// call timer already print elsewhere in this feature -- minutes uncapped,
  /// seconds padded to two digits.
  static String _stamp(Duration at) {
    final seconds = at.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
