import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
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
  /// device's silence. The turn keeps its place in the order the device
  /// asserted, which is the only ordering available for it, and the transcript
  /// says why the time is missing.
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
  /// When the earliest placed turn is [TurnTime.exact] the origin is the first
  /// thing anybody said, which is what a reader wants: 0:00 is the opening
  /// word. When it is [TurnTime.atOrBefore] the origin is that turn's upper
  /// bound, so the whole call is measured from a moment at or after the first
  /// word rather than at it.
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

  const CallTurn({
    required this.senderId,
    required this.name,
    required this.isMe,
    this.avatarUrl,
    required this.at,
    this.time = TurnTime.exact,
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
    // A change of KIND opens a turn too, and it has to. Only the opening turn
    // of a run draws a header, and the header is the only thing that says what
    // is known about the time -- so an exact turn landing on the same moment as
    // an at-or-before one would slide under its "by", or an unstated turn under
    // a plain stamp, and inherit a claim that does not describe it.
    if (previous.time != current.time) return true;
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
                  mxContent: turn.avatarUrl,
                  // The speaker's OWN name, never `label`. Label is what the
                  // header prints, and for your own turns that is the word
                  // "You" -- handing it here drew a circle with a "Y" in it
                  // for every user, since the fallback takes the initial of
                  // whatever name it is given.
                  name: turn.name,
                  size: TurnTimeline._avatarSize,
                )
              : null,
        ),
        const SizedBox(width: TurnTimeline._avatarGap),
        Expanded(
          child: Column(
            // Same exposure as the outer Column, and for the same reason:
            // Expanded governs the ROW's main axis (width) only. Along the
            // Row's cross axis (height) a non-stretch child is simply handed
            // the Row's own incoming height constraint, and the Row is
            // itself a non-flex child of the outer Column -- which always
            // gives non-flex children an unbounded main-axis constraint,
            // regardless of the outer Column's own mainAxisSize. So this
            // Column inherits the same unbounded height once embedded in a
            // scrollable, and must size to content for the same reason.
            mainAxisSize: MainAxisSize.min,
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
                    // Nothing at all for a turn whose device never said how
                    // exact its times are. The name still draws, so the turn
                    // reads as somebody's; only the claim we cannot support is
                    // left off.
                    if (_stampFor(turn) case final stamp?) ...[
                      const SizedBox(width: 8),
                      Text(
                        stamp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

  /// What this turn's header may say about when it happened, or null when it
  /// may say nothing.
  String? _stampFor(CallTurn turn) => switch (turn.time) {
    TurnTime.exact => _stamp(turn.at),
    // "by 0:45", not "0:00-0:45". A range printed beside a turn reads as how
    // long the turn LASTED, which is a second false claim in place of the
    // first, and its lower edge is an estimate this feature cannot prove.
    TurnTime.atOrBefore => l10n.callTranscriptByTime(_stamp(turn.at)),
    TurnTime.unstated => null,
  };

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
