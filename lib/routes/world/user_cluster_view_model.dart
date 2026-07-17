import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

abstract class UserClusterViewModel {
  ValueNotifier<Uri?> get avatarUrl;

  ValueNotifier<String?> get displayName;

  Stream<LevelUpdate> get levelUpdates;

  Stream<LanguageUpdate> get languageStream;

  Stream<AnalyticsStreamUpdate> get constructUpdateStream;

  Stream<void> get starsUpdateStream;

  bool get isAnalyticsInitializing;

  LanguageModel? get userL2;

  int get starsEarned;

  int get numVocabConstructs;

  int get numGrammarConstruct;

  DerivedAnalyticsDataModel? get cachedDerivedAnalyticsData;

  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData;

  void reloadProfile();

  void openAnalytics(BuildContext context, AnalyticsPanelTab tab);

  void openAnalyticsSummary(BuildContext context);

  void openProfile(BuildContext context);

  void openLevel(BuildContext context);

  void openLearningSettings(BuildContext context);

  void dispose();
}

class WorldUserClusterViewModel implements UserClusterViewModel {
  final AnalyticsDataService analyticsService;
  final Client client;

  final ValueNotifier<Uri?> _avatarUrl = ValueNotifier(null);
  final ValueNotifier<String?> _displayName = ValueNotifier(null);

  late final Stream<LevelUpdate> _levelUpdates;

  WorldUserClusterViewModel({
    required this.analyticsService,
    required this.client,
  }) {
    _levelUpdates = analyticsService.updateDispatcher.levelUpdateStream.stream
        .where(
          (_) => MatrixState
              .pangeaController
              .subscriptionController
              .showSubscriptionGatedContent,
        );
  }

  bool _profileLoaded = false;

  @override
  void dispose() {
    _avatarUrl.dispose();
    _displayName.dispose();
  }

  @override
  ValueNotifier<Uri?> get avatarUrl => _avatarUrl;

  @override
  ValueNotifier<String?> get displayName => _displayName;

  @override
  Stream<LevelUpdate> get levelUpdates => _levelUpdates;

  @override
  Stream<LanguageUpdate> get languageStream =>
      MatrixState.pangeaController.userController.languageStream.stream;

  @override
  Stream<AnalyticsStreamUpdate> get constructUpdateStream =>
      analyticsService.updateDispatcher.constructUpdateStream.stream;

  @override
  Stream<void> get starsUpdateStream => client.onRoomState.stream.where(
    // Stars bank when the session saves (archived_at on the role state), so
    // the counter listens for role-state changes as well as live awards.
    (e) =>
        e.state.type == PangeaEventTypes.orchestratorAwardedGoals ||
        e.state.type == PangeaEventTypes.activityRole,
  );

  @override
  bool get isAnalyticsInitializing => analyticsService.isInitializing;

  @override
  LanguageModel? get userL2 =>
      MatrixState.pangeaController.userController.userL2;

  @override
  int get starsEarned {
    final userL2 = this.userL2;
    return userL2 != null ? client.totalStarsEarned(userL2) : 0;
  }

  @override
  int get numVocabConstructs =>
      analyticsService.numConstructs(ConstructTypeEnum.vocab);

  @override
  int get numGrammarConstruct =>
      analyticsService.numConstructs(ConstructTypeEnum.morph);

  @override
  DerivedAnalyticsDataModel? get cachedDerivedAnalyticsData =>
      analyticsService.cachedDerivedData;

  @override
  Future<DerivedAnalyticsDataModel> get derivedAnalyticsData {
    final l2 = userL2;
    return l2 != null
        ? analyticsService.derivedData(l2.langCodeShort)
        : Future.value(DerivedAnalyticsDataModel());
  }

  bool _closeSections(BuildContext context) =>
      !FluffyThemes.isColumnMode(context);

  @override
  void reloadProfile() {
    if (_profileLoaded) return;
    _profileLoaded = true;
    _loadProfile();
  }

  /// While [type] has a live practice session, its analytics is off-limits (no
  /// peeking at definitions mid-exercise) — the tap resumes the session
  /// instead. See routing.instructions.md § Practice is a persistent
  /// background session.
  bool _resumePracticeInsteadOfAnalytics(
    BuildContext context,
    ConstructTypeEnum type,
  ) {
    if (!PracticeSessionHolder.instance.blocksAnalytics(type)) return false;
    context.go(WorkspaceNav.openPractice(GoRouterState.of(context).uri, type));
    return true;
  }

  @override
  void openAnalytics(BuildContext context, AnalyticsPanelTab tab) {
    final constructType = switch (tab) {
      AnalyticsPanelTab.vocab => ConstructTypeEnum.vocab,
      AnalyticsPanelTab.grammar => ConstructTypeEnum.morph,
      AnalyticsPanelTab.sessions => null,
    };
    if (constructType != null &&
        _resumePracticeInsteadOfAnalytics(context, constructType)) {
      return;
    }

    context.go(
      WorkspaceNav.openAnalytics(
        GoRouterState.of(context).uri,
        subpage: tab.indicator,
        closeSections: _closeSections(context),
      ),
    );
  }

  @override
  void openAnalyticsSummary(BuildContext context) {
    // The summary opens on the vocab tab, so a live vocab session blocks it.
    if (_resumePracticeInsteadOfAnalytics(context, ConstructTypeEnum.vocab)) {
      return;
    }

    context.go(
      WorkspaceNav.setRight(GoRouterState.of(context).uri, [
        AnalyticsPanelToken(
          AnalyticsTokenParam(subpage: ProgressIndicatorEnum.wordsUsed),
        ),
      ], closeSections: _closeSections(context)),
    );
  }

  @override
  void openProfile(BuildContext context) => context.go(
    WorkspaceNav.openSettings(
      GoRouterState.of(context).uri,
      closeSections: _closeSections(context),
    ),
  );

  @override
  void openLevel(BuildContext context) => context.go(
    WorkspaceNav.openAnalytics(
      GoRouterState.of(context).uri,
      subpage: ProgressIndicatorEnum.level,
      closeSections: _closeSections(context),
    ),
  );

  @override
  void openLearningSettings(BuildContext context) => context.go(
    WorkspaceNav.openSettings(
      GoRouterState.of(context).uri,
      page: 'learning',
      closeSections: _closeSections(context),
    ),
  );

  Future<void> _loadProfile() async {
    try {
      final profile = await client.fetchOwnProfile();
      _avatarUrl.value = profile.avatarUrl;
      _displayName.value = profile.displayName;
    } catch (_) {
      // Avatar falls back to the initial; not worth surfacing.
    }
  }
}
