import 'package:flutter/cupertino.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/routes/world/user_cluster_view_model.dart';

class MockUserClusterViewModel implements UserClusterViewModel {
  late final Stream<LevelUpdate> _levelUpdates;
  MockUserClusterViewModel({Stream<LevelUpdate>? levelUpdates})
    : _levelUpdates = levelUpdates ?? const Stream.empty();

  int taps = 0;
  int avatarTaps = 0;
  int levelTaps = 0;
  int flagTaps = 0;
  AnalyticsPanelTab? tappedTab;

  @override
  ValueNotifier<Uri?> get avatarUrl => ValueNotifier(null);

  @override
  ValueNotifier<String?> get displayName => ValueNotifier(null);

  @override
  Stream<LevelUpdate> get levelUpdates => _levelUpdates;

  @override
  Stream<LanguageUpdate> get languageStream => Stream.empty();

  @override
  Stream<AnalyticsStreamUpdate> get constructUpdateStream => Stream.empty();

  @override
  Stream<void> get starsUpdateStream => Stream.empty();

  @override
  bool get isAnalyticsInitializing => false;

  @override
  LanguageModel? get userL2 =>
      LanguageModel(langCode: 'es', displayName: 'Spanish');

  @override
  int get starsEarned => 0;

  @override
  int get numVocabConstructs => 0;

  @override
  int get numGrammarConstruct => 0;

  @override
  DerivedAnalyticsDataModel? get cachedDerivedAnalyticsData =>
      DerivedAnalyticsDataModel();

  @override
  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData =>
      Future.value(DerivedAnalyticsDataModel());

  @override
  void reloadProfile() {}

  @override
  void openAnalytics(BuildContext context, AnalyticsPanelTab tab) =>
      tappedTab = tab;

  @override
  void openAnalyticsSummary(BuildContext context) => taps++;

  @override
  void openProfile(BuildContext context) => avatarTaps++;

  @override
  void openLevel(BuildContext context) => levelTaps++;

  @override
  void openLearningSettings(BuildContext context) => flagTaps++;

  @override
  void dispose() {}
}
