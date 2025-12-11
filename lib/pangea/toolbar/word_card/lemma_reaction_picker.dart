import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/lemma_emoji_picker.dart';

class LemmaReactionPicker extends StatelessWidget {
  final Event? event;
  final ConstructIdentifier construct;
  final String langCode;

  const LemmaReactionPicker({
    super.key,
    required this.construct,
    required this.langCode,
    this.event,
  });

  Future<void> setEmoji(
    String emoji,
    List<String> emojis,
  ) async {
    if (event?.room.timeline == null) {
      throw Exception("Timeline is null in reaction picker");
    }

    final client = event!.room.client;
    final userSentEmojis = event!
        .aggregatedEvents(
          event!.room.timeline!,
          RelationshipTypes.reaction,
        )
        .where(
          (e) =>
              e.senderId == client.userID &&
              emojis.contains(e.content.tryGetMap('m.relates_to')?['key']),
        );

    final reactionEvent = userSentEmojis.firstWhereOrNull(
      (e) => e.content.tryGetMap('m.relates_to')?['key'] == emoji,
    );

    try {
      if (reactionEvent != null) {
        await reactionEvent.redactEvent();
        return;
      }

      await Future.wait([
        ...userSentEmojis.map((e) => e.redactEvent()),
        event!.room.sendReaction(event!.eventId, emoji),
      ]);
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
    return LemmaMeaningBuilder(
      langCode: langCode,
      constructId: construct,
      builder: (context, controller) {
        final sentReactions = <String>{};
        if (event?.room.timeline != null) {
          sentReactions.addAll(
            event!
                .aggregatedEvents(
                  event!.room.timeline!,
                  RelationshipTypes.reaction,
                )
                .where(
                  (event) =>
                      event.senderId == event.room.client.userID &&
                      event.type == 'm.reaction',
                )
                .map(
                  (event) => event.content
                      .tryGetMap<String, Object?>('m.relates_to')
                      ?.tryGet<String>('key'),
                )
                .whereType<String>(),
          );
        }

        return LemmaEmojiPicker(
          emojis: controller.lemmaInfo?.emoji ?? [],
          onSelect: event?.room.timeline != null
              ? (emoji) => setEmoji(
                    emoji,
                    controller.lemmaInfo?.emoji ?? [],
                  )
              : null,
          disabled: (emoji) => sentReactions.contains(emoji),
          loading: controller.isLoading,
        );
      },
    );
  }
}
