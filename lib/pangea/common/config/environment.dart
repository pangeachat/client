import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class Environment {
  static bool get itIsTime =>
      DateTime.utc(2023, 1, 25).isBefore(DateTime.now());

  static bool get isStagingEnvironment =>
      dotenv.env["ENVIRONMENT"] == "staging";

  /// Force Flutter's accessibility semantics tree always-on (opt-in).
  ///
  /// Flutter keeps semantics off until an assistive tech is detected or the
  /// off-screen placeholder is activated. With this on, the tree is populated
  /// from startup, so automation and assistive tech can drive the
  /// canvas-rendered UI by role+name instead of screenshots. Off by default —
  /// it carries Flutter's semantics perf cost, so it is never enabled in
  /// production. See `playwright-testing.instructions.md`.
  static bool get enableSemantics => dotenv.env["ENABLE_SEMANTICS"] == "true";

  /// Subscriptions v2 web path (D1). When unset/false, the web subscription
  /// flow keeps today's RevenueCat-shaped choreo endpoints byte-for-byte; when
  /// "true", the client uses the four v2 endpoints (`/products`, `/checkout`,
  /// `/status`, `/cancel`). Ships dark; flipped on only in lockstep with the
  /// backend Plan-7 gate flip. Mirrors `enableSemantics`.
  static bool get subsV2WebEnabled => dotenv.env["SUBS_V2_WEB"] == "true";

  static String get frontendURL {
    return appConfigOverride?.frontendURL ??
        dotenv.env["FRONTEND_URL"] ??
        "Frontend URL NOT FOUND";
  }

  static String? get testUsername => dotenv.env["TEST_MATRIX_USERNAME"];

  static String? get testPassword => dotenv.env["TEST_MATRIX_PASSWORD"];

  static String get synapseURL {
    return appConfigOverride?.synapseURL ??
        dotenv.env['SYNAPSE_URL'] ??
        'Synapse Url not found';
  }

  static String get homeServer {
    String? homeServerFromSynapseURL =
        appConfigOverride?.synapseURL ?? dotenv.env['SYNAPSE_URL'];
    if (homeServerFromSynapseURL != null) {
      if (homeServerFromSynapseURL.startsWith("http://")) {
        homeServerFromSynapseURL = homeServerFromSynapseURL.replaceFirst(
          "http://",
          "",
        );
      }
      if (homeServerFromSynapseURL.startsWith("https://")) {
        homeServerFromSynapseURL = homeServerFromSynapseURL.replaceFirst(
          "https://",
          "",
        );
      }
      if (homeServerFromSynapseURL.startsWith("matrix.")) {
        homeServerFromSynapseURL = homeServerFromSynapseURL.replaceFirst(
          "matrix.",
          "",
        );
      }
    }
    return appConfigOverride?.homeServer ??
        dotenv.env["HOME_SERVER"] ??
        homeServerFromSynapseURL ??
        'Home Server not found';
  }

  static String get choreoApi {
    final envEntry = appConfigOverride?.choreoApi ?? dotenv.env['CHOREO_API'];
    if (envEntry == null) {
      return "Not found";
    }
    if (envEntry.endsWith("/choreo")) {
      return envEntry.replaceAll("/choreo", "");
    }
    if (envEntry.endsWith("/choreo/")) {
      return envEntry.replaceAll("/choreo/", "");
    }
    return envEntry;
  }

  static String get cmsApi {
    final envEntry =
        dotenv.env['CMS_API'] ??
        appConfigOverride?.choreoApi ??
        dotenv.env['CHOREO_API'];
    if (envEntry == null) {
      return "Not found";
    }
    return envEntry;
  }

  static String get pushGatewayUrl => isStagingEnvironment
      ? 'https://sygnal.staging.pangea.chat/_matrix/push/v1/notify'
      : 'https://sygnal.pangea.chat/_matrix/push/v1/notify';

  static String get sentryDsn {
    return appConfigOverride?.sentryDsn ??
        dotenv.env["SENTRY_DSN"] ??
        'https://c2fd19ab2cdc4ebb939a32d01c0e9fa1@o225078.ingest.sentry.io/1376295';
  }

  static String? get googleAnalyticsFirebaseOptionsBase64 {
    return appConfigOverride?.googleAnalyticsFirebaseOptionsBase64 ??
        dotenv.env["GOOGLE_ANALYTICS_FIREBASE_OPTIONS_BASE64"];
  }

  static String get rcGoogleKey {
    return appConfigOverride?.rcGoogleKey ??
        dotenv.env["RC_GOOGLE_KEY"] ??
        'goog_paQMrzFKGzuWZvcMTPkkvIsifJe';
  }

  static String get rcIosKey {
    return appConfigOverride?.rcIosKey ??
        dotenv.env["RC_IOS_KEY"] ??
        'appl_DUPqnxuLjkBLzhBPTWeDjqNENuv';
  }

  static String get rcOfferingName {
    return appConfigOverride?.rcOfferingName ??
        dotenv.env["RC_OFFERING_NAME"] ??
        'default';
  }

  static String get stripeManagementUrl {
    return appConfigOverride?.stripeManagementUrl ??
        dotenv.env["STRIPE_MANAGEMENT_LINK"] ??
        (isStagingEnvironment
            ? 'https://billing.stripe.com/p/login/test_9AQaI8d3O9lmaXe5kk'
            : 'https://billing.stripe.com/p/login/dR6dSkf5p6rBc4EcMM');
  }

  static String get supportUserId {
    return synapseURL.contains('staging')
        ? '@support:staging.pangea.chat'
        : '@support:pangea.chat';
  }

  static String? get botName {
    return appConfigOverride?.botName ?? dotenv.env["BOT_NAME"];
  }

  static final GetStorage appConfigurationStorage = GetStorage('env_override');

  static Future<List<AppConfigOverride>> getAppConfigOverrides() async {
    if (!isStagingEnvironment) {
      return [];
    }

    List<dynamic> data = [];
    try {
      final String jsonString = await rootBundle.loadString('envs.json');
      data = jsonDecode(jsonString);
    } catch (e) {
      return [];
    }

    final List<AppConfigOverride> overrides = [];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) {
        ErrorHandler.logError(
          e: Exception("Invalid entry in envs.json"),
          s: StackTrace.current,
          data: entry,
        );
        continue;
      }

      try {
        final override = AppConfigOverride.fromJson(entry);
        overrides.add(override);
      } catch (e, s) {
        ErrorHandler.logError(e: e, s: s, data: entry);
        continue;
      }
    }
    return overrides;
  }

  static AppConfigOverride? get appConfigOverride {
    final entry = appConfigurationStorage.read(PLocalKey.appConfigOverride);
    if (entry == null) return null;
    try {
      return AppConfigOverride.fromJson(entry);
    } catch (e) {
      ErrorHandler.logError(e: e, s: StackTrace.current, data: entry);
      return null;
    }
  }

  static Future<void> setAppConfigOverride(AppConfigOverride? override) async {
    appConfigurationStorage.write(
      PLocalKey.appConfigOverride,
      override?.toJson(),
    );
  }
}

class AppConfigOverride {
  final String? environment;
  final String? frontendURL;
  final String? synapseURL;
  final String? homeServer;
  final String? choreoApi;
  final String? sentryDsn;
  final String? googleAnalyticsFirebaseOptionsBase64;
  final String? rcGoogleKey;
  final String? rcIosKey;
  final String? rcOfferingName;
  final String? stripeManagementUrl;
  final String? botName;

  const AppConfigOverride({
    this.environment,
    this.frontendURL,
    this.synapseURL,
    this.homeServer,
    this.choreoApi,
    this.sentryDsn,
    this.googleAnalyticsFirebaseOptionsBase64,
    this.rcGoogleKey,
    this.rcIosKey,
    this.rcOfferingName,
    this.stripeManagementUrl,
    this.botName,
  });

  static AppConfigOverride fromJson(Map<String, dynamic> json) {
    return AppConfigOverride(
      environment: json['environment'] as String?,
      frontendURL: json['frontendURL'] as String?,
      synapseURL: json['synapseURL'] as String?,
      homeServer: json['homeServer'] as String?,
      choreoApi: json['choreoApi'] as String?,
      sentryDsn: json['sentryDsn'] as String?,
      googleAnalyticsFirebaseOptionsBase64:
          json['googleAnalyticsFirebaseOptionsBase64'] as String?,
      rcGoogleKey: json['rcGoogleKey'] as String?,
      rcIosKey: json['rcIosKey'] as String?,
      rcOfferingName: json['rcOfferingName'] as String?,
      stripeManagementUrl: json['stripeManagementUrl'] as String?,
      botName: json['botName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'environment': environment,
      'frontendURL': frontendURL,
      'synapseURL': synapseURL,
      'homeServer': homeServer,
      'choreoApi': choreoApi,
      'sentryDsn': sentryDsn,
      'googleAnalyticsFirebaseOptionsBase64':
          googleAnalyticsFirebaseOptionsBase64,
      'rcGoogleKey': rcGoogleKey,
      'rcIosKey': rcIosKey,
      'rcOfferingName': rcOfferingName,
      'stripeManagementUrl': stripeManagementUrl,
      'botName': botName,
    };
  }

  @override
  int get hashCode {
    return environment.hashCode ^
        frontendURL.hashCode ^
        synapseURL.hashCode ^
        homeServer.hashCode ^
        choreoApi.hashCode ^
        sentryDsn.hashCode ^
        googleAnalyticsFirebaseOptionsBase64.hashCode ^
        rcGoogleKey.hashCode ^
        rcIosKey.hashCode ^
        rcOfferingName.hashCode ^
        stripeManagementUrl.hashCode ^
        botName.hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppConfigOverride) return false;
    return environment == other.environment &&
        frontendURL == other.frontendURL &&
        synapseURL == other.synapseURL &&
        homeServer == other.homeServer &&
        choreoApi == other.choreoApi &&
        sentryDsn == other.sentryDsn &&
        googleAnalyticsFirebaseOptionsBase64 ==
            other.googleAnalyticsFirebaseOptionsBase64 &&
        rcGoogleKey == other.rcGoogleKey &&
        rcIosKey == other.rcIosKey &&
        rcOfferingName == other.rcOfferingName &&
        stripeManagementUrl == other.stripeManagementUrl &&
        botName == other.botName;
  }
}
