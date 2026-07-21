import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fluffychat/features/bot/bot_target_event_name_enum.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/select_mode_buttons.dart';
import '../../../config/firebase_options.dart';

// PageRoute import

// Add import:
// import 'package:pangea/common/utils/firebase_analytics.dart';
// Call method: GoogleAnalytics.logout()

class GoogleAnalytics {
  static FirebaseAnalytics? analytics;
  static String? _pendingLoginMethod;

  GoogleAnalytics();

  static Future<void> initialize() async {
    final isNativeMobile =
        !kIsWeb &&
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform);
    // Web/desktop reads the Firebase analytics config from the env
    // (GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64), which is only set in deploy
    // builds. Local dev has none, so skip analytics init rather than crash
    // startup on the null-assert in DefaultFirebaseOptions.currentPlatform.
    // analytics stays null and every call site already uses analytics?.
    final webFirebaseOptions = Environment.googleAnalyticsFirebaseOptionsBase64;
    if (!isNativeMobile &&
        (webFirebaseOptions == null || webFirebaseOptions.isEmpty)) {
      debugPrint(
        'Skipping Firebase analytics init: no '
        'GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64 configured.',
      );
      return;
    }
    final FirebaseApp app;
    if (isNativeMobile) {
      app = Firebase.apps.isNotEmpty
          ? Firebase.app()
          : await Firebase.initializeApp();
    } else {
      app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    analytics = FirebaseAnalytics.instanceFor(app: app);
    // Client is not automatically set on web
    await _setClientVersion();
    await _setEnvironment();

    debugPrint("Firebase App Name: ${app.name}");
    debugPrint("Firebase App Options:");
    debugPrint("  App ID: ${app.options.appId}");
    debugPrint("  Project ID: ${app.options.projectId}");
    debugPrint("  Database URL: ${app.options.databaseURL}");
    debugPrint("  Messaging Sender ID: ${app.options.messagingSenderId}");
    debugPrint("  Storage Bucket: ${app.options.storageBucket}");
  }

  static Future<void> _setClientVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await analytics?.setUserProperty(
        name: 'client_version',
        value: packageInfo.version,
      );
    } catch (error) {
      debugPrint('Unable to set analytics client version: $error');
    }
  }

  static Future<void> _setEnvironment() async {
    await analytics?.setUserProperty(
      name: 'environment',
      value: Environment.isStagingEnvironment ? 'staging' : 'prod',
    );
  }

  static Future<void> analyticsUserUpdate(String? userID) async {
    debugPrint("user update $userID");
    await analytics?.setUserId(id: userID);
  }

  static void updateUserSubscriptionStatus(bool subscribed) {
    analytics?.setUserProperty(name: 'subscribed', value: "$subscribed");
  }

  static void setUserProperties({
    required String targetLanguage,
    required String sourceLanguage,
    String? userType,
  }) {
    analytics?.setUserProperty(
      name: ModelKey.targetLanguage,
      value: targetLanguage,
    );
    analytics?.setUserProperty(
      name: ModelKey.sourceLanguage,
      value: sourceLanguage,
    );
    if (userType != null) {
      analytics?.setUserProperty(name: 'user_type', value: userType);
    }
  }

  static void logEvent(String name, {Map<String, Object>? parameters}) {
    debugPrint("event: $name - parameters: $parameters");

    analytics?.logEvent(name: name, parameters: parameters);
  }

  /// A GA4 screen view for a workspace screen. [screenName] is the token-derived
  /// name from `ScreenNames` (identity stripped), wired by
  /// `WorkspaceScreenTracker`. See `google-analytics.instructions.md`.
  static void logScreenView(String screenName) {
    analytics?.logScreenView(screenName: screenName);
  }

  static void prepareLogin(String method) {
    _pendingLoginMethod = method;
  }

  static void cancelPendingLogin() {
    _pendingLoginMethod = null;
  }

  static void login() {
    final method = _pendingLoginMethod;
    _pendingLoginMethod = null;
    if (method == null) return;

    logEvent('login', parameters: {'method': method});
  }

  static void signUp(String type) {
    logEvent('sign_up', parameters: {'method': type});
  }

  /// User logs out. Removes user from the current GA session.
  static void logout() {
    logEvent('logout');
  }

  /// User send a message
  static void sendMessage(String chatRoomId, String classCode) {
    logEvent(
      'sent_message',
      parameters: {"chat_id": chatRoomId, 'group_id': classCode},
    );
  }

  /// User opened a word card
  static void viewWordCard() {
    logEvent('word_card');
  }

  /// User opened the message toolbar
  static void openMessageToolbar() {
    logEvent('message_toolbar', parameters: {"action": "open"});
  }

  /// User executed an action on the message tool bar
  static void messageToolbarAction(SelectMode action) {
    logEvent('message_toolbar', parameters: {"action": action.name});
  }

  static void messageTranslate() {
    logEvent('message_translate');
  }

  static void createClass(String className, String classCode) {
    logEvent(
      'create_class',
      parameters: {'name': className, 'group_id': classCode},
    );
  }

  static void createChat(String newChatRoomId) {
    logEvent('create_chat', parameters: {"chat_id": newChatRoomId});
  }

  static void addParent(String chatRoomId, String classCode) {
    logEvent(
      'add_room_to_class',
      parameters: {"chat_id": chatRoomId, 'group_id': classCode},
    );
  }

  static void removeChatFromClass(String chatRoomId, String classCode) {
    logEvent(
      'remove_room_from_class',
      parameters: {"chat_id": chatRoomId, 'group_id': classCode},
    );
  }

  static void joinClass(String classCode) {
    logEvent('join_group', parameters: {'group_id': classCode});
  }

  static void beginPurchaseSubscription(
    String planId,
    String? promoCode,
    BuildContext context,
  ) {
    logEvent(
      'begin_checkout',
      parameters: {
        "currency": "USD",
        'item_id': planId,
        'item_category': "subscription",
        'quantity': 1,
      },
    );
  }

  /// Checkout completed: the subscription turned active after a begun payment
  /// (detected on return from Stripe). Closes the begin_checkout funnel with
  /// GA4's recommended `purchase` event.
  static void purchaseSubscription(String? planId) {
    logEvent(
      'purchase',
      parameters: {
        'currency': 'USD',
        'item_id': ?planId,
        'item_category': 'subscription',
        'quantity': 1,
      },
    );
  }

  static void startActivity(
    String activityId,
    String roomId, {
    bool? versionPinHonored,
    String? fallbackCause,
  }) {
    logEvent(
      'start_activity',
      parameters: {
        'activity_id': activityId,
        'room_id': roomId,
        'version_pin_honored': ?versionPinHonored,
        'fallback_cause': ?fallbackCause,
      },
    );
  }

  static void completeActivity(
    String activityId,
    String roomId, {
    bool? versionPinHonored,
    String? fallbackCause,
  }) {
    logEvent(
      'complete_activity',
      parameters: {
        'activity_id': activityId,
        'room_id': roomId,
        'version_pin_honored': ?versionPinHonored,
        'fallback_cause': ?fallbackCause,
      },
    );
  }

  static void failUpdateNotificationBadge() {
    logEvent('fail_update_notification_badge');
  }

  static void openBotNotification({
    required BotTargetEventName targetEventName,
    String? variant,
    String? notificationType,
    String? chatId,
    String? groupId,
    String? activityId,
    String? roomId,
    String? action,
    String? name,
  }) {
    logEvent(
      'bot_notification_opened',
      parameters: {
        'target_event_name': targetEventName.name,
        'variant': ?variant,
        'notification_type': ?notificationType,
        'chat_id': ?chatId,
        'group_id': ?groupId,
        'activity_id': ?activityId,
        'room_id': ?roomId,
        'action': ?action,
        'name': ?name,
      },
    );
  }

  static void completeTutorialStep(String tutorialName, int step) {
    logEvent(
      'tutorial_progress',
      parameters: {'tutorial_name': tutorialName, 'tutorial_step': step},
    );
  }

  static FirebaseAnalyticsObserver? getAnalyticsObserver() {
    // analytics is null when Firebase init was skipped (no env config, e.g.
    // local dev). Return null so the router simply runs without the observer
    // rather than failing to build. See initialize().
    final analytics = GoogleAnalytics.analytics;
    if (analytics == null) {
      return null;
    }
    return FirebaseAnalyticsObserver(
      analytics: analytics,
      nameExtractor: (settings) {
        final name = settings.name?.trim();
        if (name == null || name.isEmpty) {
          return null;
        }
        return name;
      },
      routeFilter: (route) {
        // By default firebase only tracks page routes
        if (route is! PageRoute) {
          return false;
        }

        final name = route.settings.name?.trim();
        if (name == null || name.isEmpty) {
          return false;
        }

        // The workspace route ('/') is tracked by WorkspaceScreenTracker with
        // token-derived names; logging it here would double-count it as '/'.
        if (name == '/') {
          return false;
        }

        debugPrint("navigating to route: $name");
        return true;
      },
    );
  }
}
