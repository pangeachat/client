import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/utils/platform_infos.dart';

class ErrorHandler {
  ErrorHandler();

  static Future<void> initialize() async {
    // Only a build positively identified as staging or production (see
    // Environment.sentryEnvironment) inits Sentry: local-dev and
    // misconfigured-build errors are visible in the console already, and
    // reporting them mislabelled buries staging/production signal (#8505).
    // Every capture below no-ops without init.
    final sentryEnvironment = Environment.sentryEnvironment;
    if (sentryEnvironment != null) {
      await SentryFlutter.init((options) {
        options.dsn = Environment.sentryDsn;
        options.tracesSampleRate = 0.02;
        options.environment = sentryEnvironment;
      });
      await applyBuildTags();
    }

    // Error handling. Both global sinks route through [logError] rather than
    // capturing directly, so a failure arriving here gets the same severity
    // table and grouping key as one reported from a repo — a raw
    // [Sentry.captureException] gets neither.
    FlutterError.onError = onFlutterError;

    PlatformDispatcher.instance.onError = (exception, stack) {
      logError(e: exception, s: stack, data: {});
      return true;
    };
  }

  /// The [FlutterError.onError] sink. Overriding the default sink must not
  /// drop [FlutterError.presentError]: without it a debug build discards
  /// every framework error — no console output, no `flutter run` log line —
  /// and a rendering bug thrown on every frame produces nothing anywhere a
  /// developer looks (#8677). Release builds skip it, so their surfacing is
  /// exactly what it was: [logError] alone.
  @visibleForTesting
  static Future<void> onFlutterError(FlutterErrorDetails details) async {
    if (kDebugMode) FlutterError.presentError(details);
    if (!kDebugMode || PlatformInfos.isMobile) {
      await logError(e: details.exception, s: details.stack, data: {});
    }
  }

  /// Puts [Environment.sentryBuildTags] on the global scope, so every event
  /// says which build produced it — including the native crashes and app-start
  /// failures the SDK captures without passing through [logError], which a
  /// per-report tag would miss.
  @visibleForTesting
  static Future<void> applyBuildTags() async => Sentry.configureScope(
    (scope) => Environment.sentryBuildTags.forEach(scope.setTag),
  );

  /// Whether [e] belongs in Sentry at all. [UnsubscribedException] does not:
  /// it is control flow — an unsubscribed user reaching a paid endpoint — and
  /// repos-and-error-handling.instructions.md states it is never reported.
  ///
  /// The invariant is enforced here, at the one sink, rather than by an
  /// `is! UnsubscribedException` guard at each call site. The guard had been
  /// copied to four sites while every hand-rolled repo that bypasses
  /// [BaseRepo], every `showFutureLoadingDialog`, and the global
  /// unhandled-async sink in [initialize] had no guard at all — so it reached
  /// production
  /// as `Instance of 'UnsubscribedException'` (CLIENT-E4T, #8373). A rule
  /// copied per call site drifts; a rule with one home cannot.
  static bool shouldReport(Object? e) => e is! UnsubscribedException;

  /// Keys already reported this session via [logErrorOnce].
  static final Set<String> _reportedOnceKeys = {};

  /// The grouping key and session cap key for the expired-token condition.
  static const List<String> _expiredTokenFingerprint = [
    'pangea-auth',
    'expired-matrix-token',
  ];

  /// Whether [e] is an expired (or otherwise invalidated) Matrix access token
  /// surfacing as a failed call. One expired token fails every surface at
  /// once — each call in flight at app boot 401s before the SDK's soft-logout
  /// refresh lands — so the condition scattered into seven per-endpoint
  /// Sentry issues (CLIENT-EHD/-EBG/-EBK/-EBM/-EBH/-EED/-EBJ, #8698) at
  /// ~30 events/day. [logError] collapses everything matching here into one
  /// grouping ([_expiredTokenFingerprint]) and one report per app session.
  ///
  /// Four shapes, all the same condition:
  /// - the Matrix SDK's own `M_UNKNOWN_TOKEN` failure;
  /// - a choreo 401 — choreo validates the bearer via Synapse WhoAmI, and an
  ///   expired token makes that check itself 401;
  /// - a Pangea Synapse-module 401 — the homeserver rejecting the bearer
  ///   directly;
  /// - a CMS read answered 403 ([_isCmsReadDenied]) — the same rejection,
  ///   one hop later and mislabelled.
  ///
  /// Any other 401 or 403 (a 401 with no expired-token detail, a 403 on a
  /// write) keeps its own per-endpoint grouping and is never capped.
  static bool _isExpiredTokenError(Object e) {
    if (e is MatrixException) return e.error == MatrixError.M_UNKNOWN_TOKEN;
    if (e is! PangeaHttpException) return false;
    if (e.statusCode == 403) return _isCmsReadDenied(e);
    if (e.statusCode != 401) return false;
    return (e.detail?.contains('Matrix WhoAmI non-200 (401)') ?? false) ||
        e.path.startsWith('/_synapse/client/pangea');
  }

  /// Whether [e] is a CMS read denied with Payload's generic 403. The CMS
  /// validates the bearer through its own Synapse whoami hop; a rejected
  /// token makes that hop 401, the auth strategy swallows it into "no user",
  /// and the read rule denies with a detail-less 403. Every collection the
  /// client reads admits any Matrix user, so on a read that 403 can only be
  /// the token — it landed in the same boot burst as the 401s, one hop later,
  /// as its own error-level issue (CLIENT-EBF, #8372). Writes are left out:
  /// their rules are per-role, so a 403 there can be a real permission bug
  /// and keeps the 403 row of the severity table.
  static bool _isCmsReadDenied(PangeaHttpException e) =>
      e.method == 'GET' && e.path.startsWith('/cms/api/');

  /// The grouping key and session cap key for a request that never reached a
  /// server.
  static const List<String> _noResponseFingerprint = [
    'pangea-network',
    'no-response',
  ];

  /// Whether [e] is a request that got no response at all — offline, DNS,
  /// CORS, a blocked request. `package:http` raises every one of those as a
  /// [ClientException] (on mobile it wraps the socket failure in one); a
  /// status code would mean a server answered. A dead connection fails every
  /// surface at once, the same shape as the expired token — one learner
  /// offline for seven seconds produced ten flag reports (CLIENT-EGM) on top
  /// of a 3,588-event catch-all (CLIENT-5XY, #8890) — so it collapses the same
  /// way: one grouping, one report per app session, warning per the
  /// no-response row of the severity table.
  static bool _isNoResponse(Object e) => e is ClientException;

  @visibleForTesting
  static void resetReportedOnceKeysForTest() => _reportedOnceKeys.clear();

  /// [logError], capped at one report per app session per [key]. For known
  /// recurring degrade paths — e.g. a joined course whose quest plan no longer
  /// resolves, retried on every sync (#8083) — the first event per session
  /// carries the signal (Sentry tallies affected users per issue); each repeat
  /// is pure event volume. Returns whether this call reported.
  static Future<bool> logErrorOnce({
    required String key,
    required Object e,
    StackTrace? s,
    required Map<String, dynamic> data,
    SentryLevel? level,
  }) async {
    // Checked before the key is spent, so suppressing control flow does not
    // consume the one report a genuine failure on this key is owed.
    if (!shouldReport(e)) return false;
    if (!_reportedOnceKeys.add(key)) return false;
    await logError(e: e, s: s, data: data, level: level);
    return true;
  }

  /// Reports [e] to Sentry at [level], defaulting to the one severity table
  /// ([PangeaHttpException.severityOf]): a timeout, a request that never
  /// reached a server, and the routine statuses (401, 404, 410, 429) are
  /// warnings, everything else — including any other failure carrying no HTTP
  /// status — an error. Severity is a property of the
  /// failure, not of the author's judgment at the call site, so it is decided
  /// here rather than at each of ~240 reporting sites, which is where it
  /// drifted before (repos-and-error-handling.instructions.md § Severity
  /// policy). An explicit [level] still wins: a caller with context the
  /// failure lacks may escalate.
  ///
  /// There is deliberately no `m:` message parameter. One existed and was
  /// silently dropped whenever [e] was non-null — `captureException(e ?? ...)`
  /// only ever read it in the no-exception case — so 37 call sites passed a
  /// hand-written message that reached `debugPrint` and nothing else, and
  /// searching Sentry for one of our own strings returned nothing (#8660).
  /// Put the description in [e] instead; it is what Sentry actually reports.
  ///
  /// [e] is required for the same reason: a report with no error attached
  /// carried no information the moment `m` stopped backing it.
  ///
  /// A [PangeaHttpException] additionally reaches Sentry with an explicit
  /// grouping key ([PangeaHttpException.fingerprintOf]) so it lands in an issue
  /// per status + endpoint. Sentry groups by stack trace otherwise, and these
  /// all share one frame in [Requests], so every HTTP failure in the app
  /// collapsed into a single catch-all issue (#8469).
  static Future<void> logError({
    required Object e,
    StackTrace? s,
    required Map<String, dynamic> data,
    SentryLevel? level,
  }) async {
    if (!shouldReport(e)) return;

    // One condition is one report regardless of which call surfaced it. An
    // expired token or a connection that never reaches a server fails every
    // in-flight call at once, so each collapses into a single grouping and
    // one report per app session ([logErrorOnce] semantics — the first event
    // carries the signal, Sentry tallies users) at warning, per the 401 and
    // no-response rows of the severity table.
    final collapsed = _isExpiredTokenError(e)
        ? _expiredTokenFingerprint
        : _isNoResponse(e)
        ? _noResponseFingerprint
        : null;
    if (collapsed != null && !_reportedOnceKeys.add(collapsed.last)) return;

    debugPrint("error message: $e");

    Sentry.addBreadcrumb(Breadcrumb(data: data));
    debugPrint(data.toString());

    Sentry.captureException(
      e,
      stackTrace: s ?? StackTrace.current,
      withScope: (scope) {
        scope.level =
            level ??
            (collapsed != null
                ? SentryLevel.warning
                : PangeaHttpException.severityOf(e));
        final fingerprint = collapsed ?? PangeaHttpException.fingerprintOf(e);
        if (fingerprint != null) scope.fingerprint = fingerprint;
      },
    );
  }
}

class ErrorCopy {
  Object error;
  ErrorCopy(this.error);

  int? get errorCode => PangeaHttpException.statusCodeOf(error);

  String toLocalizedString(BuildContext context) {
    try {
      final L10n l10n = L10n.of(context);

      if (error is TimeoutException) {
        return l10n.errorTryAgainSoon;
      }

      switch (errorCode) {
        // Waiting is the remedy, so the generic "try again later" default
        // would overstate the outage (#8705).
        case 429:
          return l10n.errorRateLimited;
        case 502:
        case 504:
        case 500:
          return l10n.error502504Desc;
        case 520:
          return l10n.error520Desc;
        case 404:
          return l10n.error404Desc;
        case 405:
          return l10n.error405Desc;
        case 601:
          return l10n.errorDisableITUserDesc;
        case 602:
          return l10n.errorDisableIGCUserDesc;
        case 603:
          return l10n.errorDisableITClassDesc;
        case 604:
          return l10n.errorDisableIGCClassDesc;
        default:
          return l10n.errorTryAgainLater;
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});
      return L10n.of(context).errorTryAgainLater;
    }
  }
}
