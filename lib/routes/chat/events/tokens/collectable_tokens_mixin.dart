import 'package:flutter/material.dart';

import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin CollectableTokensMixin<T extends StatefulWidget> on State<T> {
  /// [retireNewTokenShimmer] gives up the chat shimmer that nudges a learner
  /// toward their first new word: collecting one anywhere is normally proof they
  /// have found the mechanic. Pass false where the collection did NOT come from
  /// a chat token — the welcome tutorial's greeting bubble — so the learner still
  /// gets the nudge on the first real message they receive.
  Future<void> collectToken({
    required PangeaToken token,
    required String tokenCacheKey,
    required String targetId,
    required String langCode,
    String? eventId,
    String? roomId,
    bool retireNewTokenShimmer = true,
  }) async {
    if (retireNewTokenShimmer) {
      InstructionsEnum.shimmerNewToken.setToggledOff(true);
    }
    TokensUtil.instance.collectToken(tokenCacheKey, token.text);

    // Wait for analytics update to go through before refreshing the tokens
    // cache to ensure the same token isn't marked as new again on the next rebuild
    await Matrix.of(context).analyticsDataService.updateService.addAnalytics(
      targetId,
      [token.clickUse(eventId: eventId, roomId: roomId)],
      langCode.split('-').first,
    );
    TokensUtil.instance.clearNewTokenCache();
  }
}
