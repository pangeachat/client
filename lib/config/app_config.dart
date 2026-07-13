import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';

abstract class AppConfig {
  static String get defaultHomeserver => Environment.synapseURL;

  /// SYNAPSE_URL may carry an explicit scheme (local dev uses
  /// http://localhost:8008); only default to https when it has none.
  static Uri get defaultHomeserverUri {
    final url = defaultHomeserver;
    final hasScheme = url.startsWith('http://') || url.startsWith('https://');
    return Uri.parse(hasScheme ? url : 'https://$url');
  }

  static const Color primaryColor = Color(0xFF8560E0);
  static const Color primaryColorLight = Color(0xFFDBC9FF);
  static const Color secondaryColor = Color.fromARGB(255, 253, 191, 1);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String schemePrefix = 'matrix:';

  static const String pushNotificationsChannelId = 'pangeachat_push';
  static const String pushNotificationsAppId = 'com.talktolearn.chat';

  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;

  static const String website = "https://pangea.chat/";
  static const String appOpenUrlScheme = 'matrix.pangea.chat';

  static const String supportUrl = 'https://www.pangeachat.com/faqs';
  static const String termsOfServiceUrl =
      'https://www.pangeachat.com/terms-of-service';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'servers.joinmatrix.org',
    path: 'servers.json',
  );

  static final Uri privacyUrl = Uri.parse('https://www.pangeachat.com/privacy');

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';

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
  static const String goldHexCode = "#fdbf01";
  static const String goldLightHexCode = "#fedf49";

  static Color goldByTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? gold : goldLight;

  static String goldHexByTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? goldHexCode
      : goldLightHexCode;

  // The "powerups" gold palette for the right-nav cluster (Figma
  // AvatarLangFlags). See the cluster section of routing.instructions.md.
  static const Color goldPill = Color(0xFFFDCE47); // powerups pill background
  static const Color goldMedal = Color(0xFFF3C141); // level shield fill
  static const Color goldMedalText = Color(0xFFC29B32); // level number
  static const Color goldPale = Color(0xFFFCF2D0); // shield inner field
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

  static TextStyle messageTextStyle(Event? event, Color textColor) {
    final fontSize = messageFontSize * AppSettings.fontSizeFactor.value;
    final bigEmotes =
        event != null &&
        event.onlyEmotes &&
        event.numberEmotes > 0 &&
        event.numberEmotes <= 3;

    return TextStyle(
      color: textColor,
      fontSize: bigEmotes ? fontSize * 5 : fontSize,
      decoration: (event?.redacted ?? false)
          ? TextDecoration.lineThrough
          : null,
      height: 1.3,
    );
  }

  static final Set<String> _allowedImageHosts = {
    "pangea.chat",
    "staging.pangea.chat",
    "pangea-chat-client-assets.s3.us-east-1.amazonaws.com",
    "api.pangea.chat",
    "api.staging.pangea.chat",
    // Media CDN (image-cdn consolidation): activity/course/topic images are now
    // served from here. Without this, ImageByUrl rejects every CDN image and
    // shows a placeholder. See devops image-cdn.instructions.md.
    "content.pangea.chat",
    // YouTube poster thumbnails for activity `youtube` media blocks. Both hosts
    // send `Access-Control-Allow-Origin: *`, so ImageByUrl's web XHR fetch works
    // (no auth, no platform-view needed).
    "img.youtube.com",
    "i.ytimg.com",
  };

  static bool isAllowedImage(Uri imageUrl) =>
      _allowedImageHosts.contains(imageUrl.host);

  static Set<String> get allowedMimeTypes => {
    "image/jpeg",
    "image/jpg",
    "image/webp",
    "image/gif",
    "image/png",
  };

  static const Color green = Color(0xFF34A853);
  static const Color purple = Color(0xFF7B61FF);
  static const Color gray = Color(0xFFB4B2A9);
  static const Color grayText = Color(0xFF5F5E5A);
  static const Color completedGreen = Color(0xFF3B6D11);
}
