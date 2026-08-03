import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/enable_autocorrect_dialog.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

/// Autocorrect depends on the device keyboard, so it's only available on
/// mobile. On web the switch is disabled with a "Mobile only" subtitle, and
/// tapping the tile shows a snackbar explaining why — which backs off after a
/// few attempts.
class AutocorrectSettingsTile extends StatefulWidget {
  final LearningSettingsViewModel viewModel;

  /// Injectable because kIsWeb is a compile-time constant, which widget tests
  /// on the VM can't flip.
  final bool isWeb;

  const AutocorrectSettingsTile({
    super.key,
    required this.viewModel,
    this.isWeb = kIsWeb,
  });

  @override
  State<AutocorrectSettingsTile> createState() =>
      AutocorrectSettingsTileState();
}

class AutocorrectSettingsTileState extends State<AutocorrectSettingsTile> {
  static const int _maxWarnings = 3;
  int _warningCount = 0;

  Future<void> _onChanged(bool value) async {
    if (value) {
      final resp = await showDialog(
        context: context,
        builder: (context) => const EnableAutocorrectDialog(),
      );
      if (resp == false) return;
    }
    widget.viewModel.updateToolSetting(ToolSetting.enableAutocorrect, value);
  }

  void _showMobileOnlyWarning() {
    if (_warningCount >= _maxWarnings) return;
    _warningCount++;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBarAnnounced(
      SnackBar(
        content: Text(L10n.of(context).autocorrectNotAvailable),
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile.adaptive(
      value: widget.viewModel.getToolSetting(ToolSetting.enableAutocorrect),
      title: Text(ToolSetting.enableAutocorrect.toolName(context)),
      subtitle: Text(
        widget.isWeb
            ? L10n.of(context).autocorrectMobileOnly
            : ToolSetting.enableAutocorrect.toolDescription(context),
      ),
      activeThumbColor: AppConfig.activeToggleColor,
      onChanged: widget.isWeb ? null : _onChanged,
    );

    if (!widget.isWeb) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showMobileOnlyWarning,
      child: tile,
    );
  }
}
