import 'dart:async';

import 'package:flutter/material.dart';

import 'package:country_picker/country_picker.dart';

import 'package:fluffychat/pangea/instructions/instruction_settings.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/language_service.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/tool_settings_enum.dart';
import 'package:fluffychat/pangea/user/user_model.dart';

class LearningSettingsViewModel extends ChangeNotifier {
  late Profile _originalProfile;
  late Profile _updatedProfile;
  final VoidCallback? onUpdateProfile;

  LearningSettingsViewModel(Profile profile, {this.onUpdateProfile}) {
    _originalProfile = profile;
    _updatedProfile = profile;
  }

  Timer? _textDebounce;

  @override
  void dispose() {
    _textDebounce?.cancel();
    super.dispose();
  }

  bool get haveSettingsChanged => _originalProfile != _updatedProfile;

  bool get hasIdenticalLanguages =>
      selectedSourceLanguage?.langCodeShort ==
      selectedTargetLanguage?.langCodeShort;

  LanguageModel? get selectedSourceLanguage {
    return _selectedBaseLanguage ?? LanguageService.systemLanguage;
  }

  LanguageModel? get selectedTargetLanguage {
    return _selectedTargetLanguage ??
        ((selectedSourceLanguage?.langCode != 'en')
            ? PLanguageStore.byLangCode('en')
            : PLanguageStore.byLangCode('es'));
  }

  LanguageModel? get _selectedBaseLanguage =>
      _updatedProfile.userSettings.sourceLanguage != null
      ? PLanguageStore.byLangCode(_updatedProfile.userSettings.sourceLanguage!)
      : null;

  LanguageModel? get _selectedTargetLanguage =>
      _updatedProfile.userSettings.targetLanguage != null
      ? PLanguageStore.byLangCode(_updatedProfile.userSettings.targetLanguage!)
      : null;

  LanguageLevelTypeEnum get cefrLevel => _updatedProfile.userSettings.cefrLevel;

  String? get selectedVoice => _updatedProfile.userSettings.voice;

  Country? get country =>
      CountryService().findByName(_updatedProfile.userSettings.country);

  String? get about => _updatedProfile.userSettings.about;

  Profile get updatedProfile => _updatedProfile;

  GenderEnum get gender => _updatedProfile.userSettings.gender;

  bool get publicProfile => _updatedProfile.userSettings.publicProfile ?? false;

  bool getToolSetting(ToolSetting toolSetting) {
    final toolSettings = _updatedProfile.toolSettings;
    switch (toolSetting) {
      case ToolSetting.interactiveTranslator:
        return toolSettings.interactiveTranslator;
      case ToolSetting.interactiveGrammar:
        return toolSettings.interactiveGrammar;
      case ToolSetting.immersionMode:
        return toolSettings.immersionMode;
      case ToolSetting.definitions:
        return toolSettings.definitions;
      case ToolSetting.autoIGC:
        return toolSettings.autoIGC;
      case ToolSetting.enableTTS:
        return _updatedProfile.userSettings.targetLanguage != null &&
            _selectedTargetLanguage != null &&
            toolSettings.enableTTS;
      case ToolSetting.enableAutocorrect:
        return toolSettings.enableAutocorrect;
      case ToolSetting.selectAudioMessagesOnPlay:
        return toolSettings.selectAudioMessagesOnPlay;
    }
  }

  void _updateProfile(Profile updated) {
    if (updated == _updatedProfile) return;
    _updatedProfile = updated;
    onUpdateProfile?.call();
    notifyListeners();
  }

  void updateToolSetting(ToolSetting toolSetting, bool value) {
    final updated = _updatedProfile.copyWith(
      toolSettings: _updatedProfile.toolSettings.copyWith(
        interactiveTranslator: toolSetting == ToolSetting.interactiveTranslator
            ? value
            : _updatedProfile.toolSettings.interactiveTranslator,
        interactiveGrammar: toolSetting == ToolSetting.interactiveGrammar
            ? value
            : _updatedProfile.toolSettings.interactiveGrammar,
        immersionMode: toolSetting == ToolSetting.immersionMode
            ? value
            : _updatedProfile.toolSettings.immersionMode,
        definitions: toolSetting == ToolSetting.definitions
            ? value
            : _updatedProfile.toolSettings.definitions,
        autoIGC: toolSetting == ToolSetting.autoIGC
            ? value
            : _updatedProfile.toolSettings.autoIGC,
        enableTTS: toolSetting == ToolSetting.enableTTS
            ? value
            : _updatedProfile.toolSettings.enableTTS,
        enableAutocorrect: toolSetting == ToolSetting.enableAutocorrect
            ? value
            : _updatedProfile.toolSettings.enableAutocorrect,
        selectAudioMessagesOnPlay:
            toolSetting == ToolSetting.selectAudioMessagesOnPlay
            ? value
            : _updatedProfile.toolSettings.selectAudioMessagesOnPlay,
      ),
    );
    _updateProfile(updated);
  }

  void resetInstructionTooltips() {
    final updated = _updatedProfile.copyWith(
      instructionSettings: InstructionSettings(),
    );
    _updateProfile(updated);
  }

  void setSelectedLanguage({
    LanguageModel? sourceLanguage,
    LanguageModel? targetLanguage,
  }) {
    Profile updated = _updatedProfile;
    if (sourceLanguage != null && sourceLanguage != selectedSourceLanguage) {
      updated = _updatedProfile.copyWith(
        userSettings: _updatedProfile.userSettings.copyWith(
          sourceLanguage: sourceLanguage.langCode,
        ),
      );
    }

    if (targetLanguage != null && targetLanguage != selectedTargetLanguage) {
      updated = _updatedProfile.copyWith(
        userSettings: _updatedProfile.userSettings.copyWith(
          targetLanguage: targetLanguage.langCode,
          voice: null,
          setVoiceNull: true,
        ),
        toolSettings: _updatedProfile.toolSettings.copyWith(enableTTS: true),
      );
    }

    _updateProfile(updated);
  }

  void setGender(GenderEnum? gender) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        gender: gender ?? GenderEnum.unselected,
      ),
    );
    _updateProfile(updated);
  }

  void setPublicProfile(bool isPublic) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        publicProfile: isPublic,
      ),
    );
    _updateProfile(updated);
  }

  void setCefrLevel(LanguageLevelTypeEnum? cefrLevel) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        cefrLevel: cefrLevel ?? LanguageLevelTypeEnum.a1,
      ),
    );
    _updateProfile(updated);
  }

  void setVoice(String? voice) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(voice: voice),
    );
    _updateProfile(updated);
  }

  void setCountry(Country? country) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        country: country?.name,
      ),
    );
    _updateProfile(updated);
  }

  void setAbout(String about) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(about: about),
    );
    _textDebounce?.cancel();
    _textDebounce = Timer(const Duration(milliseconds: 500), () {
      _updateProfile(updated);
    });
  }
}
