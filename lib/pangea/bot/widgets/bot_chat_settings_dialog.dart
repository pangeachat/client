import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/chat_settings/models/bot_options_model.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/dropdown_text_button.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';

class BotChatSettingsDialog extends StatefulWidget {
  final Room room;

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

  Future<void> _setLanguage(LanguageModel? lang) async {
    setState(() {
      _selectedLang = lang;
      _selectedVoice = null;
    });

    final model = widget.room.botOptions ?? BotOptionsModel();
    model.targetLanguage = lang?.langCode;
    model.targetVoice = null;

    try {
      await widget.room.setBotOptions(model);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'roomId': widget.room.id,
          'langCode': lang?.langCode,
        },
      );
    }
  }

  Future<void> _setLevel(LanguageLevelTypeEnum? level) async {
    if (level == null) return;

    setState(() => _selectedLevel = level);
    final model = widget.room.botOptions ?? BotOptionsModel();
    model.languageLevel = level;
    try {
      await widget.room.setBotOptions(model);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'roomId': widget.room.id,
          'level': level.name,
        },
      );
    }
  }

  Future<void> _setVoice(String? voice) async {
    setState(() => _selectedVoice = voice);
    final model = widget.room.botOptions ?? BotOptionsModel();
    model.targetVoice = voice;
    try {
      await widget.room.setBotOptions(model);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'roomId': widget.room.id,
          'voice': voice,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        spacing: 12.0,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.room.isActivitySession)
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
            )
          else
            const SizedBox(),
          PLanguageDropdown(
            onChange: _setLanguage,
            initialLanguage: _selectedLang,
            languages:
                MatrixState.pangeaController.pLanguageStore.targetOptions,
            isL2List: true,
            decorationText: L10n.of(context).targetLanguage,
            enabled: !widget.room.isActivitySession,
          ),
          LanguageLevelDropdown(
            initialLevel: _selectedLevel,
            onChanged: _setLevel,
            enabled: !widget.room.isActivitySession,
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
          const SizedBox(),
        ],
      ),
    );
  }
}
