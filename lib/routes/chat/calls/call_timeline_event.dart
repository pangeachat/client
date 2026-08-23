import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/calls/call_record.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// One finished call, drawn in the timeline.
///
/// Centred, like a join or an invitation, because a call is something that
/// HAPPENED in the conversation rather than something one side said. Drawing it
/// as a chat bubble would attribute it to whoever's client wrote it and align it
/// to their edge, which reads as a message from them.
///
/// The same event is read from both sides of a direct message, so direction is
/// derived per viewer: the account that placed the call sees it as outgoing, the
/// other as incoming.
/// What the CHAT LIST says about a room whose newest event is a call.
///
/// The same words the card in the conversation uses, so the list and the
/// conversation agree. Hiding the membership plumbing stopped the list
/// reading "sent a com.famedly.call.member event", but on its own it left
/// "No messages yet" on a room where two people had just talked -- and the
/// SDK's own fallback for an unknown message type is no better ("User sent a
/// pangea.call event"). A call is worth a line of its own.
String callPreviewLine(L10n l10n, Event event, {required bool outgoing}) {
  final declined = event.content['declined'] == true;
  final answered = event.content['answered'] == true;
  final video = event.content['video'] == true;
  if (declined) {
    return outgoing ? l10n.callHistoryDeclined : l10n.callHistoryYouDeclined;
  }
  if (!answered) {
    if (outgoing) return l10n.callHistoryNoAnswer;
    return video ? l10n.callHistoryMissedVideoCall : l10n.callHistoryMissedCall;
  }
  final label = video ? l10n.callHistoryVideoCall : l10n.callHistoryVoiceCall;
  final duration = CallRecord.durationOf(event.content);
  if (duration == Duration.zero) return label;
  return '$label · ${CallTimelineEvent.formatDuration(duration)}';
}

class CallTimelineEvent extends StatelessWidget {
  final Event event;

  /// The surrounding timeline, for the first-per-key rule below. Required so
  /// no call site can forget it exists; nullable because a card can render
  /// where no timeline is at hand (a preview, a test) -- there the rule
  /// simply cannot run and the card draws.
  final Timeline? timeline;

  const CallTimelineEvent(this.event, {required this.timeline, super.key});

  /// Whether this account placed the call.
  ///
  /// From the stated caller, not from who wrote the event: the writer is chosen
  /// deterministically so exactly one card exists, and that is not always the
  /// side that called. Older events carry no caller, so the sender stands in.
  bool get _outgoing {
    final me = event.room.client.userID;
    final caller = event.content['caller'];
    if (caller is String) return caller == me;
    return event.senderId == me;
  }

  bool get _video => event.content['video'] == true;

  /// Whether a conversation actually happened. False is a missed call.
  bool get _answered => event.content['answered'] == true;

  /// Turned down, as opposed to simply not picked up. Both are unanswered; only
  /// this one was a deliberate no.
  bool get _declined => event.content['declined'] == true;

  /// Read through the record's own rule, so the card and the thing that wrote
  /// it cannot disagree about what a duration is.
  Duration get _duration => CallRecord.durationOf(event.content);

  /// Whether another card for the SAME call precedes this one.
  ///
  /// Matrix transaction ids dedup PER DEVICE, so two devices writing the same
  /// call -- the writer and the survivor racing across the settle window --
  /// cannot be collapsed by the server. The idempotency lives HERE instead,
  /// per the idempotent-receiver rule: every writer stamps the call's shared
  /// key, and only the FIRST card per key in timeline order is drawn. Order is
  /// origin_server_ts with the event id as the final tie-break, so every
  /// client picks the same one. Keyless cards -- older clients, calls whose
  /// identity was never learned -- always draw, exactly as before.
  bool get _duplicateOfEarlier {
    final t = timeline;
    return t != null && isDuplicateOfEarlier(event, t.events);
  }

  /// The rule itself, pure so it can be pinned directly: [event] is a
  /// duplicate iff some other sent call card in [all] carries the same key
  /// and sorts earlier -- origin_server_ts first, event id as the final
  /// tie-break, so every client picks the same survivor of a double-write.
  @visibleForTesting
  static bool isDuplicateOfEarlier(Event event, Iterable<Event> all) {
    final key = event.content[CallRecord.callKeyField];
    if (key is! String) return false;
    for (final other in all) {
      if (identical(other, event) || other.eventId == event.eventId) continue;
      if (other.type != PangeaEventTypes.call) continue;
      if (other.content[CallRecord.callKeyField] != key) continue;
      if (other.status.isError) continue;
      final byTime = other.originServerTs.compareTo(event.originServerTs);
      if (byTime < 0 ||
          (byTime == 0 && other.eventId.compareTo(event.eventId) < 0)) {
        return true;
      }
    }
    return false;
  }

  /// Whether this card ever reached the homeserver.
  ///
  /// A send that failed is not dropped by the SDK: it keeps the optimistic echo
  /// in the LOCAL timeline and marks it errored. Nothing ever retries it, and
  /// the peer never receives it, so drawing it puts a call in one person's
  /// history that is absent from the other's -- which is what a call card must
  /// never do. It states a SHARED fact, and a copy only one side has is a claim
  /// the other cannot see.
  bool get _neverSent => event.status.isError;

  @override
  Widget build(BuildContext context) {
    // Nothing, rather than a phantom. The call itself still happened; what
    // failed is the record of it, and a record only one side holds is worse
    // than no record -- it reads as an extra call that never took place.
    if (_neverSent) return const SizedBox.shrink();
    if (_duplicateOfEarlier) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final missed = !_answered && !_declined;
    final connected = _answered && !_declined;

    // A call that connected is unremarkable; one that was missed or turned down
    // is the thing a learner scrolls back to find. Colour follows that, not the
    // call's direction.
    final color = connected ? const Color(0xFF2E7D32) : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: Material(
          color: theme.colorScheme.surface.withAlpha(128),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(missed), size: 16, color: color),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    _label(l10n, missed),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (connected) ...[
                  Text(
                    '  ${formatDuration(_duration)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _icon(bool missed) {
    if (_declined) return Icons.phone_disabled_outlined;
    if (missed) {
      return _outgoing ? Icons.call_missed_outgoing : Icons.call_missed;
    }
    if (_video) return Icons.videocam;
    return _outgoing ? Icons.call_made : Icons.call_received;
  }

  String _label(L10n l10n, bool missed) {
    if (_declined) {
      return _outgoing ? l10n.callHistoryDeclined : l10n.callHistoryYouDeclined;
    }
    if (missed) {
      if (_outgoing) return l10n.callHistoryNoAnswer;
      return _video
          ? l10n.callHistoryMissedVideoCall
          : l10n.callHistoryMissedCall;
    }
    return _video ? l10n.callHistoryVideoCall : l10n.callHistoryVoiceCall;
  }

  /// `M:SS`, or `H:MM:SS` once a call runs past an hour. Seconds are always two
  /// digits so the colon does not jump around as a call ticks over.
  static String formatDuration(Duration d) {
    final seconds = d.inSeconds;
    final s = (seconds % 60).toString().padLeft(2, '0');
    final m = (seconds ~/ 60) % 60;
    final h = seconds ~/ 3600;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }
}
