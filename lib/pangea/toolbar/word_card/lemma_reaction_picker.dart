import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_highlight_emoji_row.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaReactionPicker extends StatelessWidget with LemmaEmojiSetter {
  final Event? event;
  final ConstructIdentifier constructId;
  final String langCode;

  const LemmaReactionPicker({
    super.key,
    required this.constructId,
    required this.langCode,
    this.event,
  });

  Event? _sentReaction(String emoji, BuildContext context) {
    final userSentEmojis = event!
        .aggregatedEvents(
          event!.room.timeline!,
          RelationshipTypes.reaction,
        )
        .where(
          (e) => e.senderId == Matrix.of(context).client.userID,
        );

    return userSentEmojis.firstWhereOrNull(
      (e) => e.content.tryGetMap('m.relates_to')?['key'] == emoji,
    );
  }

  Future<void> _setEmoji(
    String emoji,
    BuildContext context,
    String targetId,
  ) async {
    await setLemmaEmoji(constructId, emoji, targetId);
    showLemmaEmojiSnackbar(context, constructId, emoji);
  }

  Future<void> _sendOrRedactReaction(String emoji, BuildContext context) async {
    if (event?.room.timeline == null) return;

    try {
      final reactionEvent = _sentReaction(emoji, context);
      if (reactionEvent != null) {
        await reactionEvent.redactEvent();
        return;
      }

      await event!.room.sendReaction(
        event!.eventId,
        emoji,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'emoji': emoji,
          'eventId': event?.eventId,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .lemmaUpdateStream(constructId);

    final targetId = "emoji-choice-item-${constructId.lemma}-$hashCode";
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        final selectedEmoji =
            snapshot.data?.emojis?.firstOrNull ?? constructId.userSetEmoji;

        return LemmaHighlightEmojiRow(
          cId: constructId,
          langCode: langCode,
          targetId: targetId,
          onEmojiSelected: (emoji, target) => emoji != selectedEmoji
              ? _setEmoji(emoji, context, target)
              : _sendOrRedactReaction(emoji, context),
          emoji: selectedEmoji,
          messageInfo: event?.content ?? {},
          selectedEmojiBadge: event != null &&
                  selectedEmoji != null &&
                  _sentReaction(selectedEmoji, context) == null
              ? const Icon(
                  Icons.add_reaction,
                  size: 12.0,
                )
              : null,
        );
      },
    );
  }
}
