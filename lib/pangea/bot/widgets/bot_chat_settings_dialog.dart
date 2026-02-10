import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/bot/utils/bot_room_extension.dart';
import 'package:fluffychat/pangea/chat_settings/utils/bot_client_extension.dart';
import 'package:fluffychat/pangea/chat_settings/widgets/language_level_dropdown.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/pangea/learning_settings/voice_dropdown.dart';
import 'package:fluffychat/pangea/user/user_model.dart' as user;
import 'package:fluffychat/widgets/matrix.dart';

class BotChatSettingsDialog extends StatefulWidget {
  final Room room;

  const BotChatSettingsDialog({required this.room, super.key});

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

  user.Profile get _userProfile =>
      MatrixState.pangeaController.userController.profile;

  Future<void> _update(user.Profile Function(user.Profile) update) async {
    try {
      await MatrixState.pangeaController.userController
          .updateProfile(update, waitForDataInSync: true)
          .timeout(const Duration(seconds: 15));
      await Matrix.of(
        context,
      ).client.updateBotOptions(_userProfile.userSettings);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'roomId': widget.room.id, 'model': _userProfile.toJson()},
      );
    }
  }

  Future<void> _setLanguage(LanguageModel? lang) async {
    if (lang == null ||
        lang.langCode == _userProfile.userSettings.targetLanguage) {
      return;
    }

    setState(() {
      _selectedLang = lang;
      _selectedVoice = null;
    });

    await _update((model) {
      model.userSettings.targetLanguage = lang.langCode;
      model.userSettings.voice = null;
      return model;
    });
  }

  Future<void> _setLevel(LanguageLevelTypeEnum? level) async {
    if (level == null || level == _userProfile.userSettings.cefrLevel) return;
    setState(() => _selectedLevel = level);

    await _update((model) {
      model.userSettings.cefrLevel = level;
      return model;
    });
  }

  Future<void> _setVoice(String? voice) async {
    if (voice == _userProfile.userSettings.voice) return;

    setState(() => _selectedVoice = voice);
    await _update((model) {
      model.userSettings.voice = voice;
      return model;
    });
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
            // width: 300,
            // maxHeight: 300,
          ),
          VoiceDropdown(
            onChanged: _setVoice,
            value: _selectedVoice,
            language: _selectedLang,
            enabled:
                !widget.room.isActivitySession ||
                (_selectedLang != null &&
                    _selectedLang ==
                        MatrixState.pangeaController.userController.userL2),
          ),
          const SizedBox(),
        ],
      ),
    );
  }
}
