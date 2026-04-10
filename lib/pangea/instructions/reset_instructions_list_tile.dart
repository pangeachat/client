import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';

class ResetInstructionsListTile extends StatelessWidget {
  final VoidCallback resetInstructionTooltips;
  const ResetInstructionsListTile(this.resetInstructionTooltips, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lightbulb),
      title: Text(L10n.of(context).resetInstructionTooltipsTitle),
      subtitle: Text(L10n.of(context).resetInstructionTooltipsDesc),
      onTap: () async {
        final resp = await showOkCancelAlertDialog(
          context: context,
          title: L10n.of(context).areYouSure,
        );
        if (resp == OkCancelResult.ok) {
          resetInstructionTooltips();
        }
      },
    );
  }
}
