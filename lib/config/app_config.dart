import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';

abstract class AppConfig {
  // #Pangea
  static String get defaultHomeserver => Environment.synapseURL;
  // Pangea#
  // Const and final configuration values (immutable)
  // #Pangea
  // static const Color primaryColor = Color(0xFF5625BA);
  // static const Color primaryColorLight = Color(0xFFCCBDEA);
  // static const Color secondaryColor = Color(0xFF41a2bc);
  static const Color primaryColor = Color(0xFF8560E0);
  static const Color primaryColorLight = Color(0xFFDBC9FF);
  static const Color secondaryColor = Color.fromARGB(255, 253, 191, 1);
  // Pangea#

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'im.fluffychat://chat/';
  static const String schemePrefix = 'matrix:';
  // #Pangea
  // static const String pushNotificationsChannelId = 'fluffychat_push';
  // static const String pushNotificationsAppId = 'chat.fluffy.fluffychat';
  static const String pushNotificationsChannelId = 'pangeachat_push';
  static const String pushNotificationsAppId = 'com.talktolearn.chat';
  // Pangea#
  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;

  // #Pangea
  // static const String website = 'https://fluffy.chat';
  static const String website = "https://pangea.chat/";
  // Pangea#
  static const String enablePushTutorial =
      'https://fluffy.chat/faq/#push_without_google_services';
  static const String encryptionTutorial =
      'https://fluffy.chat/faq/#how_to_use_end_to_end_encryption';
  static const String startChatTutorial =
      'https://fluffy.chat/faq/#how_do_i_find_other_users';
  static const String appId = 'im.fluffychat.FluffyChat';
  // #Pangea
  // static const String appOpenUrlScheme = 'im.fluffychat';
  static const String appOpenUrlScheme = 'matrix.pangea.chat';
  // Pangea#

  static const String sourceCodeUrl =
      'https://github.com/krille-chan/fluffychat';
  // static const String supportUrl =
  //     'https://github.com/krille-chan/fluffychat/issues';
  // static const String changelogUrl = 'https://fluffy.chat/en/changelog/';
  // static const String donationUrl = 'https://ko-fi.com/krille';
  static const String supportUrl = 'https://www.pangeachat.com/faqs';
  static const String termsOfServiceUrl =
      'https://www.pangeachat.com/terms-of-service';
  // Pangea#

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/krille-chan/fluffychat/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'servers.joinmatrix.org',
    path: 'servers.json',
  );

  static final Uri privacyUrl = Uri(
    scheme: 'https',
    host: 'fluffy.chat',
    path: '/en/privacy',
  );

  // #Pangea
  static String assetsBaseURL =
      "https://pangea-chat-client-assets.s3.us-east-1.amazonaws.com";
  static String androidUpdateURL =
      "https://play.google.com/store/apps/details?id=com.talktolearn.chat";
  static String iosUpdateURL = "itms-apps://itunes.apple.com/app/id1445118630";
  static String googlePlayPaymentMethodUrl =
      "https://play.google.com/store/paymentmethods";
  static String appleMangementUrl =
      "https://apps.apple.com/account/subscriptions";
  static String googlePlayMangementUrl =
      "https://play.google.com/store/account/subscriptions";
  static String googlePlayHistoryUrl =
      "https://play.google.com/store/account/orderhistory";
  static bool useActivityImageAsChatBackground = true;
  static const int overlayAnimationDuration = 250;
  static const Color gold = Color.fromARGB(255, 253, 191, 1);
  static const Color goldLight = Color.fromARGB(255, 254, 223, 73);
  static const Color success = Color(0xFF33D057);
  static const Color error = Colors.red;
  static const Color warning = Color.fromARGB(255, 210, 124, 12);
  static const Color activeToggleColor = Color(0xFF33D057);
  static const Color yellowLight = Color.fromARGB(255, 247, 218, 120);
  static const Color yellowDark = Color.fromARGB(255, 253, 191, 1);
  static const double toolbarMaxHeight = 250.0;
  static const double toolbarMinWidth = 350.0;
  static const double toolbarMinHeight = 150.0;
  static const double toolbarMenuHeight = 50.0;
  static const double readingAssistanceInputBarHeight = 175.0;
  static String errorSubscriptionId = "pangea_subscription_error";

  static TextStyle messageTextStyle(
    Event? event,
    Color textColor,
  ) {
    final fontSize = messageFontSize * AppSettings.fontSizeFactor.value;
    final bigEmotes = event != null &&
        event.onlyEmotes &&
        event.numberEmotes > 0 &&
        event.numberEmotes <= 3;

    return TextStyle(
      color: textColor,
      fontSize: bigEmotes ? fontSize * 5 : fontSize,
      decoration:
          (event?.redacted ?? false) ? TextDecoration.lineThrough : null,
      height: 1.3,
    );
  }
  // Pangea#
}
