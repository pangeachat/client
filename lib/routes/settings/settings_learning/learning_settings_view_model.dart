import 'dart:async';

import 'package:flutter/material.dart';

import 'package:country_picker/country_picker.dart';

import 'package:fluffychat/features/instructions/instruction_settings.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/chat/events/text_to_speech/tts_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/gender_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LearningSettingsViewModel extends ChangeNotifier {
  late Profile _updatedProfile;
  final VoidCallback? onUpdateProfile;

  LearningSettingsViewModel(Profile profile, {this.onUpdateProfile}) {
    _updatedProfile = profile;
    final userController = MatrixState.pangeaController.userController;
    _profileListeners = [
      userController.settingsUpdateStream.stream.listen(
        (_) => _onProfileSynced(),
      ),
      userController.languageStream.stream.listen((_) => _onProfileSynced()),
    ];
    refreshKnownGoodVoice();
  }

  Timer? _textDebounce;
  late final List<StreamSubscription> _profileListeners;
  bool _hasResetTooltips = false;
  bool _hasKnownGoodVoice = false;
  bool _disposed = false;

  @override
  void dispose() {
    _textDebounce?.cancel();
    for (final listener in _profileListeners) {
      listener.cancel();
    }
    _disposed = true;
    super.dispose();
  }

  /// The profile also changes from outside this page — the word card's audio
  /// prompt writes the same profile, as do the language-mismatch prompts and
  /// other devices. Adopt what synced so the tiles stop showing the snapshot
  /// this page opened with (#8334).
  void _onProfileSynced() {
    final synced = MatrixState.pangeaController.userController.profile;
    if (synced == _updatedProfile) return;

    final targetLanguageChanged =
        synced.userSettings.targetLanguage !=
        _updatedProfile.userSettings.targetLanguage;

    _updatedProfile = synced;
    notifyListeners();

    // The voice gate is per-language, so a new target language re-runs it.
    if (targetLanguageChanged) refreshKnownGoodVoice();
  }

  bool get hasResetTooltips => _hasResetTooltips;

  /// Re-runs the known-good-voice gate for the selected target language and
  /// notifies if the answer changed, so the message-audio toggles show the
  /// device's current state after the learner downloads a voice.
  Future<bool> refreshKnownGoodVoice() async {
    final langCode = selectedTargetLanguage?.langCode;
    final hasVoice =
        langCode != null && await TtsController.hasKnownGoodVoiceFor(langCode);
    // The engine query outlives a page the learner backs out of.
    if (_disposed) return hasVoice;
    if (hasVoice != _hasKnownGoodVoice) {
      _hasKnownGoodVoice = hasVoice;
      notifyListeners();
    }
    return hasVoice;
  }

  bool get haveSettingsChanged {
    final originalProfile = MatrixState.pangeaController.userController.profile;
    return originalProfile != _updatedProfile;
  }

  bool get hasIdenticalLanguages =>
      selectedSourceLanguage?.langCodeShort ==
      selectedTargetLanguage?.langCodeShort;

  Profile get _validProfile {
    if (!hasIdenticalLanguages) return _updatedProfile;
    final originalProfile = MatrixState.pangeaController.userController.profile;
    return _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        targetLanguage: originalProfile.userSettings.targetLanguage,
        sourceLanguage: originalProfile.userSettings.sourceLanguage,
      ),
    );
  }

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

  Profile get updatedProfile => _validProfile;

  GenderEnum get gender => _updatedProfile.userSettings.gender;

  bool get publicProfile => _updatedProfile.userSettings.publicProfile ?? false;

  bool get showDeveloperOptions =>
      _updatedProfile.toolSettings.showDeveloperOptions;

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
      case ToolSetting.audioWords:
        return _updatedProfile.userSettings.targetLanguage != null &&
            _selectedTargetLanguage != null &&
            toolSettings.audioWords;
      case ToolSetting.audioChoices:
        return _updatedProfile.userSettings.targetLanguage != null &&
            _selectedTargetLanguage != null &&
            toolSettings.audioChoices;
      // Read-aloud is silent without a known-good device voice, so the toggle
      // reads off there whatever the account setting says — otherwise a
      // default-on toggle claims audio the device cannot produce (#8326).
      case ToolSetting.audioOnNewMessage:
        return _hasKnownGoodVoice && toolSettings.audioOnNewMessage;
      case ToolSetting.audioOnMessageClick:
        return _hasKnownGoodVoice && toolSettings.audioOnMessageClick;
      case ToolSetting.enableAutocorrect:
        return toolSettings.enableAutocorrect;
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
        audioWords: toolSetting == ToolSetting.audioWords
            ? value
            : _updatedProfile.toolSettings.audioWords,
        audioChoices: toolSetting == ToolSetting.audioChoices
            ? value
            : _updatedProfile.toolSettings.audioChoices,
        audioOnNewMessage: toolSetting == ToolSetting.audioOnNewMessage
            ? value
            : _updatedProfile.toolSettings.audioOnNewMessage,
        audioOnMessageClick: toolSetting == ToolSetting.audioOnMessageClick
            ? value
            : _updatedProfile.toolSettings.audioOnMessageClick,
        enableAutocorrect: toolSetting == ToolSetting.enableAutocorrect
            ? value
            : _updatedProfile.toolSettings.enableAutocorrect,
      ),
    );
    _updateProfile(updated);
  }

  bool get appLanguageIsTarget =>
      _updatedProfile.userSettings.appLanguageIsTarget;

  void setAppLanguageIsTarget(bool value) {
    final updated = _updatedProfile.copyWith(
      userSettings: _updatedProfile.userSettings.copyWith(
        appLanguageIsTarget: value,
      ),
    );
    _updateProfile(updated);
  }

  void resetInstructionTooltips() {
    final updated = _updatedProfile.copyWith(
      instructionSettings: InstructionSettings(),
    );
    _hasResetTooltips = true;
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
        toolSettings: _updatedProfile.toolSettings.copyWith(
          audioWords: true,
          audioChoices: true,
        ),
      );
    }

    _updateProfile(updated);
    // The voice gate is per-language, so a new target language re-runs it.
    if (targetLanguage != null) refreshKnownGoodVoice();
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

  void setShowDeveloperOptions(bool value) {
    final updated = _updatedProfile.copyWith(
      toolSettings: _updatedProfile.toolSettings.copyWith(
        showDeveloperOptions: value,
      ),
    );
    _updateProfile(updated);
  }
}
