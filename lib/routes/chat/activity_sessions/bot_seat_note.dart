import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension BotSeatNoteEvent on Event {
  /// The bot's own pangea.bot_participant marker: it took the session's open
  /// seat on its own. A marker a learner wrote ("Play with Pangea Bot") is not
  /// one.
  bool get isBotSeatNote =>
      type == PangeaEventTypes.botParticipant &&
      senderId == BotName.byEnvironment;
}

/// Where the bot took a waiting session's open seat on its own, the reason in
/// the chat (activities.instructions.md, "When the bot took the seat on its
/// own"). Past a day the bot fills quietly and sends nothing, so the note says
/// the learner starts.
class BotSeatNote extends StatelessWidget {
  final Event event;
  const BotSeatNote(this.event, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return InlineTooltip(
      message: event.content['quiet'] == true
          ? l10n.botTookSeatAfterADay
          : l10n.botTookSeatAfterAnHour,
      isClosed: false,
      closable: false,
      animate: false,
      icon: Icons.smart_toy_outlined,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    );
  }
}
