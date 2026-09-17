import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
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
  late final StreamSubscription<String> _ownProfileUpdates;

  /// How long the own-profile update stream must stay quiet before the
  /// signals that piled up during a burst are honored with one fetch.
  final Duration profileRefreshQuietPeriod;

  static const Duration defaultProfileRefreshQuietPeriod = Duration(seconds: 1);

  WorldUserClusterViewModel({
    required this.analyticsService,
    required this.client,
    this.profileRefreshQuietPeriod = defaultProfileRefreshQuietPeriod,
  }) {
    _levelUpdates = analyticsService.updateDispatcher.levelUpdateStream.stream
        .where(
          (_) => MatrixState
              .pangeaController
              .subscriptionController
              .showSubscriptionGatedContent,
        );
    ActivityPlanRepo.instance.addListener(_onPlanHydrate);
    // The cluster outlives the profile page that changes the avatar, so it
    // relies on the change being announced: by the page's own write
    // (OwnProfileClientExtension) and by the member events sync raises (#8330).
    _ownProfileUpdates = client.onUserProfileUpdate.stream
        .where((userId) => userId == client.userID)
        .listen((_) => _onOwnProfileUpdate());
  }

  final StreamController<void> _planHydrationStream =
      StreamController.broadcast();

  void _onPlanHydrate() => _planHydrationStream.add(null);

  bool _profileLoaded = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    ActivityPlanRepo.instance.removeListener(_onPlanHydrate);
    _ownProfileUpdates.cancel();
    _profileRefreshQuietTimer?.cancel();
    _planHydrationStream.close();
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

  // A stable stream instance (not a getter building a new merge per access),
  // so a StreamBuilder reading it across rebuilds keeps one subscription
  // instead of resubscribing every frame.
  @override
  late final Stream<void> starsUpdateStream = StreamGroup.mergeBroadcast([
    client.onRoomState.stream.where(
      // Stars bank when the session saves (archived_at on the role state), so
      // the counter listens for role-state changes as well as live awards.
      (e) =>
          e.state.type == PangeaEventTypes.orchestratorAwardedGoals ||
          e.state.type == PangeaEventTypes.activityRole,
    ),
    // totalStarsEarned matches sessions by their plan's target language, and
    // reading it kicks off hydration for thin v3 refs — recount when a plan
    // lands, or a fresh session shows 0 until the next role-state event.
    _planHydrationStream.stream,
  ]);

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
  DerivedAnalyticsDataModel? get cachedDerivedAnalyticsData {
    final l2 = userL2;
    return l2 == null
        ? null
        : analyticsService.cachedDerivedDataFor(l2.langCodeShort);
  }

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
      // The flag is a shortcut straight to learning settings, not a drill-in
      // from the menu, so it opens that page alone (#7961).
      seatMenu: false,
    ),
  );

  bool _loadingProfile = false;

  /// A signal not yet honored with a fetch: it landed while one was in flight
  /// (that fetch may predate the change it announces) or inside a burst.
  bool _profileRefreshPending = false;
  Timer? _profileRefreshQuietTimer;

  /// One avatar edit rewrites the member event in every joined room, so the
  /// update stream arrives as a burst spread over the sync that carries it —
  /// one fetch per signal is a request storm for an account in many rooms.
  /// The first signal fetches at once (a local edit shows immediately); the
  /// rest fold into a single trailing fetch once the stream has been quiet for
  /// [profileRefreshQuietPeriod] (#8330).
  void _onOwnProfileUpdate() {
    if (_profileRefreshQuietTimer == null && !_loadingProfile) {
      _loadProfile(fromServer: true);
    } else {
      _profileRefreshPending = true;
    }
    _profileRefreshQuietTimer?.cancel();
    _profileRefreshQuietTimer = Timer(profileRefreshQuietPeriod, () {
      _profileRefreshQuietTimer = null;
      _flushPendingProfileRefresh();
    });
  }

  /// Honors a pending signal once nothing stands in the way — the burst has
  /// gone quiet and no fetch is in flight. Called from both ends: when the
  /// quiet timer fires and when a fetch completes.
  void _flushPendingProfileRefresh() {
    if (!_profileRefreshPending ||
        _loadingProfile ||
        _profileRefreshQuietTimer != null) {
      return;
    }
    _profileRefreshPending = false;
    _loadProfile(fromServer: true);
  }

  /// Loads the own profile into [avatarUrl] / [displayName]. The initial load
  /// takes the SDK's cached profile; [fromServer] skips the cache, which the
  /// SDK refreshes with whatever the last fetch saw — an update signal must
  /// not be answered from it.
  Future<void> _loadProfile({bool fromServer = false}) async {
    if (_disposed) return;
    if (_loadingProfile) {
      _profileRefreshPending = true;
      return;
    }
    _loadingProfile = true;
    try {
      // Swallows network failures itself (the SDK answers from its cache, or
      // with an empty profile), so the avatar falls back to the initial.
      final profile = fromServer
          ? await client.getProfileFromUserId(
              client.userID!,
              maxCacheAge: Duration.zero,
            )
          : await client.fetchOwnProfile();
      if (_disposed) return;
      _avatarUrl.value = profile.avatarUrl;
      _displayName.value = profile.displayName;
    } finally {
      _loadingProfile = false;
      _flushPendingProfileRefresh();
    }
  }
}
