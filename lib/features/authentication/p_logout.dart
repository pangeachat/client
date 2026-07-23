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

  final client = matrix.client;
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
      // before wiping out locally cached construct data, save it to the server
      saveAnalytics: () => matrix.analyticsDataService.updateService
          .sendLocalAnalyticsToAnalyticsRoom(),
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
/// the bearer is still valid (logout invalidates it). Save + flush are
/// best-effort and MUST NOT block or fail the logout, so they are swallowed and
/// logout always runs; the actual service disposal happens on the `loggedOut`
/// listener once logout is confirmed (so a failed logout doesn't tear down a
/// still-live account). Extracted so the ordering is unit-testable.
@visibleForTesting
Future<void> saveFlushAndLogout({
  required Future<void> Function() saveAnalytics,
  required Future<void> Function() flushTelemetry,
  required Future<void> Function() logout,
}) async {
  try {
    await saveAnalytics();
    await flushTelemetry();
  } catch (_) {
    // Best-effort — never block or fail the logout on telemetry.
  }
  await logout();
}
