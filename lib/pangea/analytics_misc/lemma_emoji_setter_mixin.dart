import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_details_popup/vocab_analytics_list_tile.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin LemmaEmojiSetter<T extends StatefulWidget> on State<T> {
  Future<void> setLemmaEmoji(
    ConstructIdentifier constructId,
    String emoji,
    String? targetId,
  ) async {
    if (constructId.userSetEmoji.isEmpty) {
      _sendEmojiAnalytics(
        constructId,
        targetId: targetId,
      );
    }

    await constructId.setUserLemmaInfo(
      constructId.userLemmaInfo.copyWith(emojis: [emoji]),
    );

    _showSnackbar(constructId, emoji);
  }

  void _showSnackbar(ConstructIdentifier constructId, String emoji) {
    if (InstructionsEnum.setLemmaEmoji.isToggledOff) return;
    InstructionsEnum.setLemmaEmoji.setToggledOff(true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          spacing: 8.0,
          children: [
            VocabAnalyticsListTile(
              constructId: constructId,
              emoji: emoji,
              textColor: Theme.of(context).colorScheme.surface,
              icon: Text(
                emoji,
                style: const TextStyle(
                  fontSize: 22,
                ),
              ),
              onTap: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                context.go(
                  "/rooms/analytics/${constructId.type.name}/${Uri.encodeComponent(constructId.string)}",
                );
              },
            ),
            Flexible(
              child: Text(
                L10n.of(context).emojiSelectedSnackbar(constructId.lemma),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.surface,
                    ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );
  }

  void _sendEmojiAnalytics(
    ConstructIdentifier constructId, {
    String? eventId,
    String? roomId,
    String? targetId,
  }) {
    final constructs = [
      OneConstructUse(
        useType: ConstructUseTypeEnum.em,
        lemma: constructId.lemma,
        constructType: constructId.type,
        metadata: ConstructUseMetaData(
          roomId: roomId,
          timeStamp: DateTime.now(),
          eventId: eventId,
        ),
        category: constructId.category,
        form: constructId.lemma,
        xp: ConstructUseTypeEnum.em.pointValue,
      ),
    ];

    MatrixState.pangeaController.putAnalytics.addAnalytics(
      constructs,
      eventId: eventId,
      roomId: roomId,
      targetId: targetId,
    );
  }
}
