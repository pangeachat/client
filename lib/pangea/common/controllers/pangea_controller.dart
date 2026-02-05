import 'dart:async';

import 'package:flutter/material.dart';

import 'package:get_storage/get_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/chat_settings/utils/bot_client_extension.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/pangea/languages/locale_provider.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/pangea/text_to_speech/tts_controller.dart';
import 'package:fluffychat/pangea/user/pangea_push_rules_extension.dart';
import 'package:fluffychat/pangea/user/style_settings_repo.dart';
import 'package:fluffychat/pangea/user/user_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../utils/firebase_analytics.dart';

class PangeaController {
  ///pangeaControllers
  late UserController userController;
  late SubscriptionController subscriptionController;

  ///store Services
  final pLanguageStore = PLanguageStore();

  StreamSubscription? _languageSubscription;
  StreamSubscription? _settingsSubscription;
  StreamSubscription? _joinSpaceSubscription;

  ///Matrix Variables
  final MatrixState matrixState;

  PangeaController({required this.matrixState}) {
    userController = UserController();
    subscriptionController = SubscriptionController(this);
    PAuthGaurd.pController = this;
    _registerSubscriptions();
  }

  /// Initializes various controllers and settings.
  /// While many of these functions are asynchronous, they are not awaited here,
  /// because of order of execution does not matter,
  /// and running them at the same times speeds them up.
  void initControllers() {
    _initAnalytics();
    subscriptionController.initialize();
    matrixState.client.setPangeaPushRules();
    TtsController.setAvailableLanguages();
  }

  void _onLogin(BuildContext context, String? userID) {
    initControllers();
    _registerSubscriptions();

    userController.reinitialize().then((_) {
      final l1 = userController.profile.userSettings.sourceLanguage;
      Provider.of<LocaleProvider>(context, listen: false).setLocale(l1);
    });
    subscriptionController.reinitialize();

    StyleSettingsRepo.settings(userID!).then((settings) {
      AppSettings.fontSizeFactor.setItem(settings.fontSizeFactor);
      AppConfig.useActivityImageAsChatBackground =
          settings.useActivityImageBackground;
    });
  }

  void _onLogout(BuildContext context) {
    userController.clear();
    _languageSubscription?.cancel();
    _settingsSubscription?.cancel();
    _joinSpaceSubscription?.cancel();
    _languageSubscription = null;
    _settingsSubscription = null;
    _joinSpaceSubscription = null;

    GoogleAnalytics.logout();
    _clearCache();
    Provider.of<LocaleProvider>(context, listen: false).setLocale(null);
  }

  void handleLoginStateChange(
    LoginState state,
    String? userID,
    BuildContext context,
  ) {
    switch (state) {
      case LoginState.loggedOut:
      case LoginState.softLoggedOut:
        _onLogout(context);
        break;
      case LoginState.loggedIn:
        _onLogin(context, userID);
        break;
    }

    Sentry.configureScope(
      (scope) => scope.setUser(SentryUser(id: userID, name: userID)),
    );
    GoogleAnalytics.analyticsUserUpdate(userID);
  }

  void _registerSubscriptions() {
    _languageSubscription?.cancel();
    _languageSubscription = userController.languageStream.stream.listen(
      _onLanguageUpdate,
    );

    _settingsSubscription?.cancel();
    _settingsSubscription = userController.settingsUpdateStream.stream.listen(
      (update) => matrixState.client.updateBotOptions(update.userSettings),
    );

    _joinSpaceSubscription?.cancel();
    _joinSpaceSubscription ??= matrixState.client.onSync.stream
        .where(matrixState.client.isJoinSpaceSyncUpdate)
        .listen((_) => matrixState.client.addAnalyticsRoomsToSpaces());
  }

  Future<void> _clearCache({List<String> exclude = const []}) async {
    final List<Future<void>> futures = [];
    for (final key in _storageKeys) {
      if (exclude.contains(key)) continue;
      futures.add(GetStorage(key).erase());
    }

    await Future.wait(futures);
  }

  Future<void> _initAnalytics() async {
    await GetStorage.init("activity_analytics_storage");

    matrixState.client.updateAnalyticsRoomJoinRules();
    matrixState.client.addAnalyticsRoomsToSpaces();
  }

  Future<void> resetAnalytics() async {
    await _initAnalytics();
  }

  Future<void> _onLanguageUpdate(LanguageUpdate update) async {
    final exclude = [
      'course_location_media_storage',
      'course_location_storage',
      'course_media_storage',
    ];

    // only clear course data if the base language has changed
    if (update.prevBaseLang == update.baseLang) {
      exclude.addAll([
        'course_storage',
        'course_topic_storage',
        'course_activity_storage',
      ]);
    }

    _clearCache(exclude: exclude);
    matrixState.client.updateBotOptions(userController.profile.userSettings);
  }

  static final List<String> _storageKeys = [
    'mode_list_storage',
    'activity_plan_storage',
    'bookmarked_activities',
    'objective_list_storage',
    'topic_list_storage',
    'activity_plan_search_storage',
    "version_storage",
    'lemma_storage',
    'svg_cache',
    'morphs_storage',
    'morph_meaning_storage',
    'practice_record_cache',
    'practice_selection_cache',
    'subscription_storage',
    'vocab_storage',
    'onboarding_storage',
    'analytics_request_storage',
    'activity_analytics_storage',
    'course_storage',
    'course_topic_storage',
    'course_media_storage',
    'course_location_storage',
    'course_activity_storage',
    'course_location_media_storage',
    'language_mismatch',
  ];
}
