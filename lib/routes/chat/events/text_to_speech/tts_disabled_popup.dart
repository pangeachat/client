import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/card_header.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Shown when an explicit audio button is pressed while the audio toggle
/// gating it ([setting]) is off. Names the toggle using the same copy as
/// learning settings, and offers to turn it back on in place.
class TtsDisabledPopup extends StatelessWidget {
  static const _overlayKey = 'tts_disabled_popup';

  final ToolSetting setting;

  const TtsDisabledPopup({super.key, required this.setting});

  static void show(BuildContext context, String targetID, ToolSetting setting) {
    OverlayUtil.showPositionedCard(
      context: context,
      cardToShow: TtsDisabledPopup(setting: setting),
      displayDetails: PositionedOverlayDisplayDetails(
        maxHeight: 300,
        maxWidth: 300,
        transformTargetId: targetID,
        closePrevOverlay: false,
        overlayKey: _overlayKey,
      ),
    );
  }

  Future<void> _enable() {
    return MatrixState.pangeaController.userController.updateProfile(
      (profile) => profile.copyWith(
        toolSettings: profile.toolSettings.copyWith(
          audioWords: setting == ToolSetting.audioWords ? true : null,
          audioChoices: setting == ToolSetting.audioChoices ? true : null,
          audioOnNewMessage: setting == ToolSetting.audioOnNewMessage
              ? true
              : null,
          audioOnMessageClick: setting == ToolSetting.audioOnMessageClick
              ? true
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toolName = setting.toolName(context);
    return Column(
      spacing: 12.0,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CardHeader(L10n.of(context).audioSettingDisabledTitle(toolName)),
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: Column(
            spacing: 12.0,
            children: [
              Text(
                L10n.of(context).audioSettingDisabledBody(toolName),
                style: BotStyle.text(context),
              ),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await _enable();
                    MatrixState.pAnyState.closeOverlay(_overlayKey);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(25),
                  ),
                  child: Text(L10n.of(context).audioSettingDisabledEnable),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
