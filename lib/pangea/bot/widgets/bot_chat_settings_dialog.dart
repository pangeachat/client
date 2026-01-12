import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/common/widgets/dropdown_text_button.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class BotChatSettingsDialog extends StatefulWidget {
  final Room room;

  static Future<void> show({
    required BuildContext context,
    required Room room,
  }) async {
    final resp = await showAdaptiveDialog<BotOptionsModel?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => BotChatSettingsDialog(room: room),
    );
    if (resp == null) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setBotOptions(resp),
    );
  }

  const BotChatSettingsDialog({
    required this.room,
    super.key,
  });

  @override
  BotChatSettingsDialogState createState() => BotChatSettingsDialogState();
}

class BotChatSettingsDialogState extends State<BotChatSettingsDialog> {
  LanguageModel? _selectedLang;
  LanguageLevelTypeEnum? _selectedLevel;
  String? _selectedVoice;

  @override
  void initState() {
    final botSettings = widget.room.botOptions;
    final activityPlan = _isActivity ? widget.room.activityPlan : null;

    _selectedLevel = activityPlan?.req.cefrLevel ?? botSettings?.languageLevel;
    _selectedVoice = botSettings?.targetVoice;
    final lang =
        activityPlan?.req.targetLanguage ?? botSettings?.targetLanguage;
    if (lang != null) {
      _selectedLang = PLanguageStore.byLangCode(lang);
    }
    super.initState();
  }

  bool get _isActivity => widget.room.isActivitySession;

  void _setLanguage(LanguageModel? lang) =>
      setState(() => _selectedLang = lang);
  void _setLevel(LanguageLevelTypeEnum? level) =>
      setState(() => _selectedLevel = level);
  void _setVoice(String? voice) => setState(() => _selectedVoice = voice);

  BotOptionsModel get _updatedModel {
    final botSettings = widget.room.botOptions ?? BotOptionsModel();
    if (_selectedLang != null) {
      botSettings.targetLanguage = _selectedLang!.langCode;
    }
    if (_selectedLevel != null) {
      botSettings.languageLevel = _selectedLevel!;
    }
    if (_selectedVoice != null) {
      botSettings.targetVoice = _selectedVoice;
    }
    return botSettings;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Center(
          child: Text(
            L10n.of(context).botSettings,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      content: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.only(top: 16.0),
          constraints: const BoxConstraints(
            maxWidth: 256,
            maxHeight: 300,
          ),
          child: SingleChildScrollView(
            child: Column(
              spacing: 16.0,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isActivity)
                  ListTile(
                    contentPadding: const EdgeInsets.all(0.0),
                    minLeadingWidth: 12.0,
                    leading: Icon(
                      Icons.info_outline,
                      size: 12.0,
                      color: Theme.of(context).disabledColor,
                    ),
                    title: Text(
                      L10n.of(context).activitySettingsOverrideWarning,
                      style: TextStyle(
                        color: Theme.of(context).disabledColor,
                        fontSize: 12.0,
                      ),
                    ),
                  ),
                PLanguageDropdown(
                  onChange: _setLanguage,
                  initialLanguage: _selectedLang,
                  languages:
                      MatrixState.pangeaController.pLanguageStore.targetOptions,
                  isL2List: true,
                  decorationText: L10n.of(context).targetLanguage,
                  enabled: !_isActivity,
                ),
                LanguageLevelDropdown(
                  initialLevel: _selectedLevel,
                  onChanged: _setLevel,
                  enabled: !_isActivity,
                ),
                DropdownButtonFormField2<String>(
                  customButton: _selectedVoice != null
                      ? CustomDropdownTextButton(text: _selectedVoice!)
                      : null,
                  menuItemStyleData: const MenuItemStyleData(
                    padding: EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 16.0,
                    ),
                  ),
                  decoration: InputDecoration(
                    labelText: L10n.of(context).voice,
                  ),
                  isExpanded: true,
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: kIsWeb ? 250 : null,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                  items: (_selectedLang?.voices ?? <String>[]).map((voice) {
                    return DropdownMenuItem(
                      value: voice,
                      child: Text(voice),
                    );
                  }).toList(),
                  onChanged: _setVoice,
                  value: _selectedVoice,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          bigButtons: true,
          onPressed: () => Navigator.of(context).pop(_updatedModel),
          child: Text(L10n.of(context).submit),
        ),
      ],
    );
  }
}
