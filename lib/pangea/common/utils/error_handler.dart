import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    FlutterError.onError = (FlutterErrorDetails details) async {
      if (!kDebugMode || PlatformInfos.isMobile) {
        await logError(e: details.exception, s: details.stack, data: {});
      }
    };

    PlatformDispatcher.instance.onError = (exception, stack) {
      logError(e: exception, s: stack, data: {});
      return true;
    };
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
  /// ([PangeaHttpException.severityOf]): a timeout and the routine statuses
  /// (401, 404, 410, 429) are warnings, everything else — including any
  /// failure carrying no HTTP status — an error. Severity is a property of the
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

    debugPrint("error message: $e");

    Sentry.addBreadcrumb(Breadcrumb(data: data));
    debugPrint(data.toString());

    Sentry.captureException(
      e,
      stackTrace: s ?? StackTrace.current,
      withScope: (scope) {
        scope.level = level ?? PangeaHttpException.severityOf(e);
        final fingerprint = PangeaHttpException.fingerprintOf(e);
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
