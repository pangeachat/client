import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/tokens_util.dart';

mixin TokenRenderingMixin {
  Future<void> collectNewToken(
    String cacheKey,
    String targetId,
    PangeaToken token,
    String language,
    AnalyticsDataService analyticsService, {
    String? roomId,
    String? eventId,
  }) async {
    TokensUtil.collectToken(cacheKey, token.text);
    if (!InstructionsEnum.shimmerNewToken.isToggledOff) {
      InstructionsEnum.shimmerNewToken.setToggledOff(true);
    }

    final constructs = [
      OneConstructUse(
        useType: ConstructUseTypeEnum.click,
        lemma: token.lemma.text,
        constructType: ConstructTypeEnum.vocab,
        metadata: ConstructUseMetaData(
          roomId: roomId,
          timeStamp: DateTime.now(),
          eventId: eventId,
        ),
        category: token.pos,
        form: token.text.content,
        xp: ConstructUseTypeEnum.click.pointValue,
      ),
    ];

    await analyticsService.updateService.addAnalytics(
      targetId,
      constructs,
      language,
    );
    TokensUtil.clearNewTokenCache();
  }
}
