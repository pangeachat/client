import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

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
class CallTimelineEvent extends StatelessWidget {
  final Event event;

  const CallTimelineEvent(this.event, {super.key});

  bool get _outgoing => event.senderId == event.room.client.userID;

  bool get _video => event.content['video'] == true;

  /// Whether a conversation actually happened. False is a missed call.
  bool get _answered => event.content['answered'] == true;

  /// Turned down, as opposed to simply not picked up. Both are unanswered; only
  /// this one was a deliberate no.
  bool get _declined => event.content['declined'] == true;

  Duration get _duration => Duration(
    milliseconds: (event.content['duration_ms'] as num?)?.round() ?? 0,
  );

  @override
  Widget build(BuildContext context) {
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
                    '  ${_formatDuration(_duration)}',
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
  static String _formatDuration(Duration d) {
    final seconds = d.inSeconds;
    final s = (seconds % 60).toString().padLeft(2, '0');
    final m = (seconds ~/ 60) % 60;
    final h = seconds ~/ 3600;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
    return '$m:$s';
  }
}
