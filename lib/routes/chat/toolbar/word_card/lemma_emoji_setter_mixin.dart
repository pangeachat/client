import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/vocab_analytics_list_tile.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin LemmaEmojiSetter {
  /// Constructs whose one-time emoji XP this app run has already awarded.
  ///
  /// Never cleared. It can only ever suppress a second award, so growing it is
  /// safe, and losing it on restart just hands the decision back to the durable
  /// record in [ConstructIdentifier.userSetEmoji].
  static final Set<String> _claimedEmojiXP = {};

  /// Whether this selection is the one that earns [constructId]'s one-time
  /// emoji XP.
  ///
  /// [alreadySet] is the durable answer — the learner already has an emoji on
  /// this construct — but it is read back from the analytics room's state
  /// event, which only becomes readable once the write has round-tripped
  /// through sync. Two selections inside that window both read it as false and
  /// both award (#9005). The claim closes the window: it is taken
  /// synchronously, in the same turn as the decision, so the second selection
  /// loses even while the durable answer is still catching up. Keyed by account
  /// and language so that neither an account switch nor an L2 switch inherits
  /// the other's claims.
  @visibleForTesting
  static bool claimEmojiXP(
    ConstructIdentifier constructId, {
    required String accountId,
    required String language,
    required bool alreadySet,
  }) {
    if (alreadySet) return false;
    return _claimedEmojiXP.add(
      '$accountId|$language|${constructId.storageKey}',
    );
  }

  Future<void> setLemmaEmoji(
    ConstructIdentifier constructId,
    String langCode,
    String emoji,
    String? targetId,
    String? roomId,
    String? eventId,
    String? form,
  ) async {
    final language = langCode.split("-").first;
    final userL2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    if (language != userL2) {
      // only set emoji for user's L2 language
      return;
    }

    final isFirstSelection = claimEmojiXP(
      constructId,
      accountId: MatrixState.pangeaController.matrixState.client.userID ?? '',
      language: language,
      alreadySet: constructId.userSetEmoji != null,
    );

    if (isFirstSelection) {
      _getEmojiAnalytics(
        constructId,
        language: language,
        targetId: targetId,
        roomId: roomId,
        eventId: eventId,
        form: form,
      );
    }

    await MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .updateService
        .setLemmaInfo(constructId, emoji: emoji);
  }

  Future<void> showLemmaEmojiSnackbar(
    ScaffoldMessengerState messenger,
    BuildContext context,
    ConstructIdentifier constructId,
    VoidCallback onTap,
  ) async {
    if (InstructionsEnum.setLemmaEmoji.isToggledOff) return;
    InstructionsEnum.setLemmaEmoji.setToggledOff(true);

    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    messenger.showSnackBarAnnounced(
      SnackBar(
        showCloseIcon: false,
        padding: const EdgeInsets.all(8.0),
        content: Row(
          spacing: 8.0,
          children: [
            VocabAnalyticsListTile(
              constructId: constructId,
              langCode: MatrixState.pangeaController.userController.userL2Code,
              textColor: theme.colorScheme.surface,
              listen: false,
              onTap: () {
                messenger.hideCurrentSnackBar();
                onTap();
              },
            ),
            Expanded(
              child: Text(
                l10n.emojiSelectedSnackbar(constructId.lemma),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.surface,
                ),
              ),
            ),
            IconButton(
              tooltip: L10n.of(context).close,
              icon: const Icon(Icons.close),
              color: theme.colorScheme.surface,
              onPressed: () => messenger.hideCurrentSnackBar(),
            ),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
      announcement: l10n.emojiSelectedSnackbar(constructId.lemma),
    );
  }

  void _getEmojiAnalytics(
    ConstructIdentifier constructId, {
    required String language,
    String? eventId,
    String? roomId,
    String? targetId,
    String? form,
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
        form: form ?? constructId.lemma,
        xp: ConstructUseTypeEnum.em.pointValue,
      ),
    ];

    MatrixState.pangeaController.matrixState.analyticsDataService.updateService
        .addAnalytics(targetId, constructs, language);
  }
}
