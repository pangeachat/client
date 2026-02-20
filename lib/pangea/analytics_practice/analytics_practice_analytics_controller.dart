import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AnalyticsPracticeAnalyticsController {
  final AnalyticsDataService analyticsService;

  const AnalyticsPracticeAnalyticsController(this.analyticsService);

  Future<double> levelProgress(String language) async {
    final derviedData = await analyticsService.derivedData(language);
    return derviedData.levelProgress;
  }

  Future<void> addCompletedActivityAnalytics(
    List<OneConstructUse> uses,
    String targetId,
    String language,
  ) => analyticsService.updateService.addAnalytics(targetId, uses, language);

  Future<void> addSkippedActivityAnalytics(
    PangeaToken token,
    ConstructTypeEnum type,
    String language,
  ) async {
    final use = OneConstructUse(
      useType: ConstructUseTypeEnum.ignPA,
      constructType: type,
      metadata: ConstructUseMetaData(roomId: null, timeStamp: DateTime.now()),
      category: token.pos,
      lemma: token.lemma.text,
      form: token.lemma.text,
      xp: 0,
    );

    await analyticsService.updateService.addAnalytics(null, [use], language);
  }

  Future<void> addSessionAnalytics(
    List<OneConstructUse> uses,
    String language,
  ) async {
    await analyticsService.updateService.addAnalytics(
      null,
      uses,
      language,
      forceUpdate: true,
    );
  }

  Future<ConstructUses> getTargetTokenConstruct(
    PangeaToken token,
    PracticeTarget target,
    String language,
  ) async {
    final token = target.tokens.first;
    final construct = target.targetTokenConstructID(token);
    return analyticsService.getConstructUse(construct, language);
  }

  Future<void> waitForAnalytics() async {
    if (!analyticsService.initCompleter.isCompleted) {
      MatrixState.pangeaController.initControllers();
      await analyticsService.initCompleter.future;
    }
  }

  Future<void> waitForUpdate() => analyticsService
      .updateDispatcher
      .constructUpdateStream
      .stream
      .first
      .timeout(const Duration(seconds: 10));
}
