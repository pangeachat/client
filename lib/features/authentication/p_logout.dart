import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

void pLogoutAction(BuildContext context, {bool? isDestructiveAction}) async {
  if (await showOkCancelAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).areYouSureYouWantToLogout,
        message: L10n.of(context).dontForgetPassword,
        okLabel: L10n.of(context).logout,
        cancelLabel: L10n.of(context).cancel,
      ) ==
      OkCancelResult.cancel) {
    return;
  }

  final matrix = Matrix.of(context);
  await matrix.backgroundPush?.cancelAllNotifications();

  // Capture THE account being logged out AND its analytics service up front, so
  // save/flush/logout all target this account even if the active client switches
  // during the flow — never the wrong account's analytics via the active getter.
  final client = matrix.client;
  final analytics = matrix.analyticsServiceFor(client.clientName);
  final redirect = client.onLoginStateChanged.stream
      .where((state) => state != LoginState.loggedIn)
      .first
      .then((_) {
        final route = FluffyChatApp.router.state.fullPath;
        if (route == null || !route.contains("/home")) {
          context.go("/home");
        }
      })
      .timeout(const Duration(seconds: 30));

  await showFutureLoadingDialog(
    context: context,
    future: () => saveFlushAndLogout(
      // before wiping out locally cached construct data, save it to the server —
      // the CAPTURED account's service, not the active-client getter.
      saveAnalytics: () =>
          analytics?.updateService.sendLocalAnalyticsToAnalyticsRoom() ??
          Future.value(),
      // NON-destructive flush of the final dosage span while the bearer is still
      // valid; the loggedOut listener disposes the services once logout lands.
      flushTelemetry: () => matrix.flushAccountTelemetry(client.clientName),
      logout: () => client.logout(),
    ),
  );

  await redirect;
}

/// The logout ordering: save cached analytics, then NON-DESTRUCTIVELY flush this
/// account's final dosage span, and only THEN log out — the flush must run while
/// the bearer is still valid (logout invalidates it). Save and flush are
/// best-effort and MUST NOT block or fail the logout:
///  - they are guarded INDEPENDENTLY, so a failing save can't skip the flush;
///  - the analytics save is time-boxed (its network write is otherwise
///    unbounded and would hang the whole logout), with the abandoned future
///    detached so a late failure never surfaces as unhandled; and
///  - logout always runs afterward.
/// The actual service disposal happens on the `loggedOut` listener once logout
/// is confirmed (so a failed logout doesn't tear down a still-live account).
/// Extracted so the ordering is unit-testable.
@visibleForTesting
Future<void> saveFlushAndLogout({
  required Future<void> Function() saveAnalytics,
  required Future<void> Function() flushTelemetry,
  required Future<void> Function() logout,
  Duration saveTimeout = const Duration(seconds: 8),
}) async {
  final save = saveAnalytics();
  try {
    await save.timeout(saveTimeout);
  } catch (_) {
    // Swallow failure/timeout and detach the abandoned save so a late error
    // from a timed-out write never surfaces as an unhandled async error.
    unawaited(save.catchError((_) {}));
  }
  try {
    await flushTelemetry();
  } catch (_) {
    // Best-effort — never block or fail the logout on the dosage flush.
  }
  await logout();
}
