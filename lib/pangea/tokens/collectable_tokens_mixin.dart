import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/tokens/tokens_util.dart';
import 'package:fluffychat/widgets/matrix.dart';

mixin CollectableTokensMixin<T extends StatefulWidget> on State<T> {
  Future<void> collectToken({
    required PangeaToken token,
    required String tokenCacheKey,
    required String targetId,
    required String langCode,
  }) async {
    TokensUtil.instance.collectToken(tokenCacheKey, token.text);

    // Wait for analytics update to go through before refreshing the tokens
    // cache to ensure the same token isn't marked as new again on the next rebuild
    await Matrix.of(context).analyticsDataService.updateService.addAnalytics(
      targetId,
      [token.clickUse()],
      langCode.split('-').first,
    );
    TokensUtil.instance.clearNewTokenCache();
  }
}
