import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_page.dart';
import 'package:fluffychat/routes/world/right_panel/panel_card_with_header.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class RightPanelAnalyticsPracticeSubpage extends StatelessWidget {
  final PanelToken token;
  final IconData icon;
  final String tooltip;
  final VoidCallback close;

  const RightPanelAnalyticsPracticeSubpage({
    super.key,
    required this.token,
    required this.icon,
    required this.tooltip,
    required this.close,
  });

  Future<void> _onLeading(BuildContext context) async {
    if (!AnalyticsPractice.bypassExitConfirmation) {
      final l10n = L10n.of(context);
      final result = await showOkCancelAlertDialog(
        useRootNavigator: false,
        context: context,
        title: l10n.areYouSure,
        okLabel: l10n.yes,
        cancelLabel: l10n.cancel,
        message: l10n.exitPractice,
      );
      if (result != OkCancelResult.ok) return;
    }
    AnalyticsPractice.bypassExitConfirmation = true;
    if (context.mounted) close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // A practice session — a normal right-column panel that takes over the
    // analytics surface (opened via WorkspaceNav.openPractice). Its close
    // confirms before abandoning an in-progress session (unsaved progress);
    // the confirm is skipped once the session completes/errors (the widget
    // flips `bypassExitConfirmation`). See routing.instructions.md.
    // Canonical param is `grammar`/`vocab`; the legacy `morph` spelling is
    // accepted as an inbound alias (ConstructTypeEnum is the one source of
    // truth for the token vocabulary).
    final constructType = ConstructTypeEnum.fromTokenParam(token.param);

    return PanelCardWithHeader(
      title: l10n.practice,
      icon: icon,
      onLeading: () => _onLeading(context),
      tooltip: tooltip,
      child: Navigator(
        key: MatrixState.pAnyState
            .layerLinkAndKey("${constructType.name}_analytics_practice_page")
            .key,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => AnalyticsPractice(type: constructType),
        ),
      ),
    );
  }
}
