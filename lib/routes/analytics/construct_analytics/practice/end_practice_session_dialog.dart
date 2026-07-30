import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/material.dart';

/// The one confirm-then-discard prompt for the held practice session. Ending
/// throws away in-progress work, so both paths that end one — the panel's End
/// control and starting the other section's practice over it — ask first. See
/// practice-exercises.instructions.md § Session Persistence & Lifecycle.
class EndPracticeSessionDialog {
  /// Asks, and drops the held session if confirmed. Returns whether it ended,
  /// so callers close or navigate only on a yes.
  ///
  /// [useRootNavigator] is false from inside the practice panel, which runs in
  /// its own nested [Navigator].
  static Future<bool> confirmAndEnd(
    BuildContext context, {
    bool useRootNavigator = true,
  }) async {
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      useRootNavigator: useRootNavigator,
      title: l10n.areYouSure,
      okLabel: l10n.yes,
      cancelLabel: l10n.cancel,
      message: l10n.exitPractice,
    );

    if (result != OkCancelResult.ok) return false;
    PracticeSessionHolder.instance.end();
    return true;
  }
}
