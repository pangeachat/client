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

  /// The speaker's display name. Ignored when [isMe] is true -- the widget
  /// substitutes the localised "You" itself, so no caller has to remember to.
  final String name;

  final bool isMe;

  /// Elapsed time from the start of the call. Already the number this widget
  /// prints, not a wall-clock instant left for it to convert.
  final Duration at;

  final String text;

  const CallTurn({
    required this.senderId,
    required this.name,
    required this.isMe,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < ordered.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _gapAbove(ordered, i)),
            child: _Turn(
              turn: ordered[i],
              showHeader:
                  i == 0 || ordered[i - 1].senderId != ordered[i].senderId,
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
      ordered[i - 1].senderId == ordered[i].senderId ? 6 : 20;
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reserved whether or not this turn draws into it, so a continuation
        // turn's text lands at exactly the x-coordinate the header's name
        // did -- indentation by shared geometry, not by a second number that
        // could drift from the first.
        SizedBox(
          width: TurnTimeline._avatarSize,
          child: showHeader
              ? Avatar(
                  userId: turn.senderId,
                  name: label,
                  size: TurnTimeline._avatarSize,
                )
              : null,
        ),
        const SizedBox(width: TurnTimeline._avatarGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _stamp(turn.at),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              _TurnText(turn: turn, theme: theme),
            ],
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

class _TurnText extends StatelessWidget {
  final CallTurn turn;
  final ThemeData theme;

  const _TurnText({required this.turn, required this.theme});

  @override
  Widget build(BuildContext context) {
    final text = SelectableText(turn.text, style: theme.textTheme.bodyMedium);
    if (!turn.isMe) return text;

    // No gold: gold reads as achievement everywhere else in this app --
    // stars, levels -- and a transcript is a record, not a reward. The one
    // turn worth marking at all is the reader's own, and a tint this quiet is
    // the whole difference between "these are your words" and "look what you
    // earned".
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(AppConfig.borderRadius / 3),
      ),
      child: text,
    );
  }
}
