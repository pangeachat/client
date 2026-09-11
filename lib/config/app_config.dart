import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/utils/text_scaler_extension.dart';

abstract class AppConfig {
  static String get defaultHomeserver => Environment.synapseURL;

  /// SYNAPSE_URL may carry an explicit scheme (local dev uses
  /// http://localhost:8008); only default to https when it has none.
  static Uri get defaultHomeserverUri {
    final url = defaultHomeserver;
    final hasScheme = url.startsWith('http://') || url.startsWith('https://');
    return Uri.parse(hasScheme ? url : 'https://$url');
  }

  // ---------------------------------------------------------------------------
  // Colours
  //
  // Widgets read colour roles from the theme (Theme.of(context).pangea and
  // colorScheme), per design-tokens.instructions.md. What lives here is:
  //  - the key colours PangeaColors derives its role families from;
  //  - the static colours older sites still read directly, which move to a
  //    theme role as each site is touched.
  // ---------------------------------------------------------------------------

  // Key colours. Each is the one place its hue is written; PangeaColors turns
  // it into a family of roles by tone.
  static const Color gold = Color.fromARGB(255, 253, 191, 1);
  static const Color warning = Color.fromARGB(255, 210, 124, 12);
  static const Color success = Color(0xFF33D057);

  // Static colours still read directly by widget code (migrating).
  static const Color primaryColor = Color(0xFF8560E0);
  static const Color primaryColorLight = Color(0xFFDBC9FF);
  static const Color primaryColorDark = Color.fromARGB(255, 81, 66, 126);
  static const Color chatColor = primaryColor;
  static const Color goldLight = Color.fromARGB(255, 254, 223, 73);
  static const Color error = Colors.red;
  static const Color activeToggleColor = Color(0xFF33D057);

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

  /// How many lines a `TextField`'s error message may wrap to before it is
  /// truncated. Sentence-length errors need several on a narrow screen.
  static const int inputErrorMaxLines = 4;

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
  static const double toolbarMaxHeight = 250.0;
  static const double toolbarMinWidth = 350.0;
  static const double toolbarMinHeight = 150.0;
  static const double toolbarMenuHeight = 50.0;
  static const double readingAssistanceInputBarHeight = 175.0;
  static String errorSubscriptionId = "pangea_subscription_error";

  /// [toolbarMaxHeight] grown by the device text scaler.
  ///
  /// The word card is a fixed-height box whose whole content is text — the
  /// word, its transcription and its meaning — so at a large device text size
  /// the unscaled 250 clips it. Everything that reserves room for that card
  /// must use the same value, or the card and the space held for it disagree.
  /// See accessibility.instructions.md, Text scaling.
  ///
  /// The card's height is driven by its stack of body lines, so it grows by the
  /// factor the scaler applies at [messageFontSize] — the card's smallest text,
  /// which under a non-linear system scaler takes the largest factor of
  /// anything in the card. The box therefore errs toward extra room rather than
  /// clipping.
  static double scaledToolbarMaxHeight(BuildContext context) =>
      toolbarMaxHeight *
      MediaQuery.textScalerOf(context).factorAt(messageFontSize);

  static TextStyle messageTextStyle(Event? event, Color textColor) {
    final fontSize = messageFontSize;
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
}
