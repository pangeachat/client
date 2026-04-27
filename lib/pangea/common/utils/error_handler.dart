import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/utils/platform_infos.dart';

class PangeaWarningError implements Exception {
  final String message;
  PangeaWarningError(String message)
    : message = "Pangea Warning Error: $message";

  @override
  String toString() => message;
}

class ErrorHandler {
  ErrorHandler();

  static Future<void> initialize() async {
    await SentryFlutter.init((options) {
      options.dsn = Environment.sentryDsn;
      options.tracesSampleRate = 0.02;
      options.debug = kDebugMode;
      options.environment = kDebugMode
          ? "debug"
          : Environment.isStagingEnvironment
          ? "staging"
          : "productionC";
    });

    // Error handling
    FlutterError.onError = (FlutterErrorDetails details) async {
      if (!kDebugMode || PlatformInfos.isMobile) {
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack ?? StackTrace.current,
        );
      }
    };

    PlatformDispatcher.instance.onError = (exception, stack) {
      logError(e: exception, s: stack, data: {});
      return true;
    };
  }

  static Future<void> logError({
    Object? e,
    StackTrace? s,
    String? m,
    required Map<String, dynamic> data,
    SentryLevel level = SentryLevel.error,
  }) async {
    if (e is PangeaWarningError) {
      // Custom handling for PangeaWarningError
      debugPrint("PangeaWarningError: ${e.message}");
    } else {
      debugPrint("error message: ${m ?? e}");
    }

    Sentry.addBreadcrumb(Breadcrumb(data: data));
    debugPrint(data.toString());

    Sentry.captureException(
      e ?? Exception(m ?? "no message supplied"),
      stackTrace: s ?? StackTrace.current,
      withScope: (scope) {
        scope.level = level;
      },
    );
  }
}

class ErrorCopy {
  Object error;
  ErrorCopy(this.error);

  int? get errorCode {
    if (error is http.Response) {
      return (error as http.Response).statusCode;
    } else {
      return null;
    }
  }

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
