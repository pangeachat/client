import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/constants/local.key.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class Environment {
  /// The 8-character git commit SHA this build was compiled from, passed in by
  /// the build workflows as `--dart-define=BUILD_COMMIT_SHA=...`.
  ///
  /// This is the only part of the version display that identifies *what code*
  /// is running. Build numbers cannot: they are per-platform monotonic counters
  /// owned by the stores (or, on web, a clock), so they order builds without
  /// saying what is in one. See `ci.instructions.md`.
  ///
  /// Compile-time, so it must be `const` — a non-const read would always be
  /// empty. Empty on any locally-run build, which is not built from a pushed
  /// commit; the Settings tile omits it then.
  static const String buildCommitSha = String.fromEnvironment(
    "BUILD_COMMIT_SHA",
  );

  /// What a LOCAL build is, when [buildCommitSha] cannot say — passed in by
  /// the dev launcher as `--dart-define=LOCAL_BUILD_STAMP=...`. Typically a
  /// short SHA, a dirty marker, and the time the run was started.
  ///
  /// Deliberately a separate key rather than reusing [buildCommitSha]: that
  /// one being empty is how [sentryBuildTagsFor] tells a local build from a CI
  /// one, so filling it in locally would file every dev session under
  /// `build_channel: ci`.
  ///
  /// The problem it solves is narrow and real: on a local build the version
  /// tile could only show `<version>+<buildNumber>`, which is identical across
  /// every rebuild of the same checkout. Asking "is the thing I am looking at
  /// the code I just changed?" had no answer, and a whole debugging session
  /// went sideways on that question.
  static const String localBuildStamp = String.fromEnvironment(
    "LOCAL_BUILD_STAMP",
  );

  /// The build identifier to show and to paste into a bug report: the pushed
  /// commit when there is one, otherwise the local stamp. Empty when neither
  /// is set, in which case there is nothing honest to show.
  static String get buildIdentifier =>
      buildCommitSha.isNotEmpty ? buildCommitSha : localBuildStamp;

  static bool get itIsTime =>
      DateTime.utc(2023, 1, 25).isBefore(DateTime.now());

  static bool get isStagingEnvironment =>
      dotenv.env["ENVIRONMENT"] == "staging";

  /// The Sentry-reportable environment for this build, per the allow-list in
  /// sentry.instructions.md (only `staging`/`production` are valid; anything
  /// else must not report).
  ///
  /// Deliberately NOT derived from [isStagingEnvironment]: the production
  /// `.env` secret never sets `ENVIRONMENT` at all, so that key can't
  /// positively identify production.
  ///
  /// Deliberately NOT derived from [userSearchDomain]: see the note on that
  /// getter. Replicates [AppConfig.defaultHomeserverUri]'s scheme-then-host
  /// parse of [synapseURL] locally to avoid importing `AppConfig` (which
  /// imports [Environment] and would cycle).
  static String? get sentryEnvironment {
    final url = synapseURL;
    final hasScheme = url.startsWith('http://') || url.startsWith('https://');
    final host = Uri.tryParse(
      hasScheme ? url : 'https://$url',
    )?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    final normalized = host.startsWith('matrix.')
        ? host.substring('matrix.'.length)
        : host;
    switch (normalized) {
      case 'pangea.chat':
        return 'production';
      case 'staging.pangea.chat':
        return 'staging';
      default:
        return null;
    }
  }

  /// Tags saying WHICH BUILD produced a Sentry event, applied to every event
  /// by [ErrorHandler.applyBuildTags].
  ///
  /// The SDK's default release is
  /// `<package>@<pubspec version>+<build number>`, and pubspec's `+N` is
  /// hand-bumped, so every locally-built app reports one byte-identical
  /// release string for months and a local build is indistinguishable in
  /// Sentry from a deployed one (#8544). These are tags,
  /// not environments: the `production`/`staging` allow-list is untouched, and
  /// a build that cannot positively identify one still does not report at all
  /// (see [sentryEnvironment]).
  static Map<String, String> get sentryBuildTags =>
      sentryBuildTagsFor(buildCommitSha);

  /// [sentryBuildTags] for a build compiled from [commitSha], empty when the
  /// build has no pushed commit. Split out only so both channels are reachable
  /// from a test: [buildCommitSha] is a compile-time constant, so a test
  /// process cannot vary it.
  @visibleForTesting
  static Map<String, String> sentryBuildTagsFor(String commitSha) => {
    'build_channel': commitSha.isEmpty ? 'local' : 'ci',
    if (commitSha.isNotEmpty) 'build_commit': commitSha,
    // An override persists in local storage and outranks dotenv, so it
    // survives a pull and a rebuild: without this, "aimed at the production
    // homeserver" and "pointed at production once and never un-pointed" look
    // identical.
    'config_override': (appConfigOverride != null).toString(),
  };

  /// Force Flutter's accessibility semantics tree always-on (opt-in).
  ///
  /// Flutter keeps semantics off until an assistive tech is detected or the
  /// off-screen placeholder is activated. With this on, the tree is populated
  /// from startup, so automation and assistive tech can drive the
  /// canvas-rendered UI by role+name instead of screenshots. Off by default —
  /// it carries Flutter's semantics perf cost, so it is never enabled in
  /// production. See `playwright-testing.instructions.md`.
  static bool get enableSemantics => dotenv.env["ENABLE_SEMANTICS"] == "true";

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

  /// The bare domain to complete a directory-search username into a full
  /// Matrix ID (`@user:<domain>` — see `UserSearchExtension.searchUser`).
  /// Single-purpose: NOT a general "which environment/host is this build"
  /// signal, because the `HOME_SERVER` override below is returned raw,
  /// unlike the scheme/`matrix.`-stripped `SYNAPSE_URL` fallback. Use
  /// [synapseURL] for that instead (see [sentryEnvironment]).
  static String get userSearchDomain {
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

  /// Base URL of the teacher-BFF (admin-dash-api). Used only by the best-effort
  /// analytics dual-write (see [AnalyticsEventsRepo]); empty when unconfigured,
  /// in which case the dual-write is skipped. Trailing slash is trimmed so the
  /// caller can concatenate a leading-slash path safely.
  static String get teacherBffApi {
    final envEntry =
        appConfigOverride?.teacherBffApi ?? dotenv.env['TEACHER_BFF_API'];
    if (envEntry == null || envEntry.isEmpty) {
      return "";
    }
    return envEntry.endsWith("/")
        ? envEntry.substring(0, envEntry.length - 1)
        : envEntry;
  }

  /// Feature flag for the best-effort analytics dual-write to the teacher-BFF.
  /// Defaults to `false` so the behavior ships dark; the dual-write is also a
  /// no-op whenever [teacherBffApi] is empty, so both must be set for it to run.
  static bool get analyticsDualWriteEnabled {
    return appConfigOverride?.analyticsDualWriteEnabled ??
        (dotenv.env["ANALYTICS_DUAL_WRITE_ENABLED"]?.toLowerCase() == 'true');
  }

  /// Feature flag for the best-effort dosage signals (see [DosageSignalsRepo]).
  /// Defaults to `false` so the behavior ships dark. This is the third gate on
  /// top of [analyticsDualWriteEnabled] + [teacherBffApi]: dosage signals ride
  /// the same BFF door as the analytics dual-write, so all three must be set.
  static bool get dosageSignalsEnabled {
    return appConfigOverride?.dosageSignalsEnabled ??
        (dotenv.env["DOSAGE_SIGNALS_ENABLED"]?.toLowerCase() == 'true');
  }

  /// Capability gate for the client-reported voice-message durations that
  /// populate speaking (`voice_messages` on the audio-signals lane; see
  /// [DosageSignalsRepo] and admin-dash-api#150). Defaults to `false` so it
  /// ships dark, and it is deliberately SEPARATE from [dosageSignalsEnabled]:
  /// the audio lane is already live against servers that predate the
  /// `voice_messages` field, whose `extra="forbid"` ingest 422s an unknown key
  /// and takes the sibling playback + coverage lanes down with it. So this flag
  /// is turned on ONLY once every target server has shipped #150 — reversing the
  /// usual client-ahead-of-server hazard the sibling routes guard against.
  static bool get dosageVoiceMessagesEnabled {
    return appConfigOverride?.dosageVoiceMessagesEnabled ??
        (dotenv.env["DOSAGE_VOICE_MESSAGES_ENABLED"]?.toLowerCase() == 'true');
  }

  /// Feature flag for the voice-transcript tokenizer-decouple send path.
  /// Defaults to `false` so it ships dark: when OFF, `onVoiceMessageSend` uses
  /// today's blocking tokenized path byte-for-byte. When ON, the send awaits
  /// only the ASR transcript text (skip_tokenize), embeds it with
  /// `stt_tokens: []`, sends, and tokenizes + attaches + records analytics in
  /// the background. Gates the NEW SEND PATH only -- the token-aware read and
  /// the compatibility token-repair stay active for already-sent token-less
  /// messages regardless of this flag.
  static bool get voiceTranscriptDecoupleEnabled {
    return appConfigOverride?.voiceTranscriptDecoupleEnabled ??
        (dotenv.env["VOICE_TRANSCRIPT_DECOUPLE_ENABLED"]?.toLowerCase() ==
            'true');
  }

  /// Feature flag for the live streaming-STT capture path (Phase-2 pilot, D11).
  /// Defaults to `false` so it ships dark: when OFF, the recorder uses today's
  /// `AudioEncoder.wav` batch record-then-transcribe path byte-for-byte. When
  /// ON *and* the message language is in the evaluated streaming set, the
  /// recorder streams PCM16 to the relay for live partials, tees the same frames
  /// into a retained WAV, and renders the settling transcript. Any other case
  /// (flag off, batch-only language, streaming unavailable) falls back to
  /// today's path unchanged (see [StreamingSttGate]).
  static bool get liveStreamingSttEnabled {
    return appConfigOverride?.liveStreamingSttEnabled ??
        (dotenv.env["LIVE_STREAMING_STT_ENABLED"]?.toLowerCase() == 'true');
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
  final String? teacherBffApi;
  final bool? analyticsDualWriteEnabled;
  final bool? dosageSignalsEnabled;
  final bool? dosageVoiceMessagesEnabled;
  final bool? voiceTranscriptDecoupleEnabled;
  final bool? liveStreamingSttEnabled;
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
    this.teacherBffApi,
    this.analyticsDualWriteEnabled,
    this.dosageSignalsEnabled,
    this.dosageVoiceMessagesEnabled,
    this.voiceTranscriptDecoupleEnabled,
    this.liveStreamingSttEnabled,
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
      teacherBffApi: json['teacherBffApi'] as String?,
      analyticsDualWriteEnabled: json['analyticsDualWriteEnabled'] as bool?,
      dosageSignalsEnabled: json['dosageSignalsEnabled'] as bool?,
      dosageVoiceMessagesEnabled: json['dosageVoiceMessagesEnabled'] as bool?,
      voiceTranscriptDecoupleEnabled:
          json['voiceTranscriptDecoupleEnabled'] as bool?,
      liveStreamingSttEnabled: json['liveStreamingSttEnabled'] as bool?,
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
      'teacherBffApi': teacherBffApi,
      'analyticsDualWriteEnabled': analyticsDualWriteEnabled,
      'dosageSignalsEnabled': dosageSignalsEnabled,
      'dosageVoiceMessagesEnabled': dosageVoiceMessagesEnabled,
      'voiceTranscriptDecoupleEnabled': voiceTranscriptDecoupleEnabled,
      'liveStreamingSttEnabled': liveStreamingSttEnabled,
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
        teacherBffApi.hashCode ^
        analyticsDualWriteEnabled.hashCode ^
        dosageSignalsEnabled.hashCode ^
        dosageVoiceMessagesEnabled.hashCode ^
        voiceTranscriptDecoupleEnabled.hashCode ^
        liveStreamingSttEnabled.hashCode ^
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
        teacherBffApi == other.teacherBffApi &&
        analyticsDualWriteEnabled == other.analyticsDualWriteEnabled &&
        dosageSignalsEnabled == other.dosageSignalsEnabled &&
        dosageVoiceMessagesEnabled == other.dosageVoiceMessagesEnabled &&
        voiceTranscriptDecoupleEnabled ==
            other.voiceTranscriptDecoupleEnabled &&
        liveStreamingSttEnabled == other.liveStreamingSttEnabled &&
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
