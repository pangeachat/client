import 'package:country_picker/country_picker.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/pages/settings_learning_view.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';
import 'package:fluffychat/pangea/spaces/models/space_model.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import 'package:fluffychat/pangea/user/models/user_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class SettingsLearning extends StatefulWidget {
  const SettingsLearning({super.key});

  @override
  SettingsLearningController createState() => SettingsLearningController();
}

class SettingsLearningController extends State<SettingsLearning> {
  PangeaController pangeaController = MatrixState.pangeaController;
  late Profile _profile;
  final tts = TtsController();

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  String? languageMatchError;

  @override
  void initState() {
    super.initState();
    _profile = pangeaController.userController.profile.copy();
    tts.setupTTS().then((_) => setState(() {}));
  }

  @override
  void dispose() {
    tts.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (selectedSourceLanguage?.langCodeShort ==
        selectedTargetLanguage?.langCodeShort) {
      setState(() {
        languageMatchError = L10n.of(context).noIdenticalLanguages;
      });
      return;
    }

    setState(() {
      languageMatchError = null; // Clear error if languages don't match
    });

    if (formKey.currentState!.validate()) {
      if (!isTTSSupported) {
        updateToolSetting(ToolSetting.enableTTS, false);
      }

      await showFutureLoadingDialog(
        context: context,
        future: () async => pangeaController.userController.updateProfile(
          (_) => _profile,
          waitForDataInSync: true,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> setSelectedLanguage({
    LanguageModel? sourceLanguage,
    LanguageModel? targetLanguage,
  }) async {
    if (sourceLanguage != null) {
      _profile.userSettings.sourceLanguage = sourceLanguage.langCode;
    }
    if (targetLanguage != null) {
      _profile.userSettings.targetLanguage = targetLanguage.langCode;
      if (!_profile.toolSettings.enableTTS && isTTSSupported) {
        updateToolSetting(ToolSetting.enableTTS, true);
      }
    }

    if (mounted) setState(() {});
  }

  void setPublicProfile(bool isPublic) {
    _profile.userSettings.publicProfile = isPublic;
    if (mounted) setState(() {});
  }

  void setCefrLevel(LanguageLevelTypeEnum? cefrLevel) {
    _profile.userSettings.cefrLevel = cefrLevel ?? LanguageLevelTypeEnum.a1;
    if (mounted) setState(() {});
  }

  void changeCountry(Country? country) {
    _profile.userSettings.country = country?.name;
    if (mounted) setState(() {});
  }

  void updateToolSetting(ToolSetting toolSetting, bool value) {
    switch (toolSetting) {
      case ToolSetting.interactiveTranslator:
        _profile.toolSettings.interactiveTranslator = value;
        break;
      case ToolSetting.interactiveGrammar:
        _profile.toolSettings.interactiveGrammar = value;
        break;
      case ToolSetting.immersionMode:
        _profile.toolSettings.immersionMode = value;
        break;
      case ToolSetting.definitions:
        _profile.toolSettings.definitions = value;
        break;
      case ToolSetting.autoIGC:
        _profile.toolSettings.autoIGC = value;
        break;
      case ToolSetting.enableTTS:
        _profile.toolSettings.enableTTS = value;
        break;
      case ToolSetting.enableAutocorrect:
        _profile.toolSettings.enableAutocorrect = value;
        break;
    }
    if (mounted) setState(() {});
  }

  LanguageModel? get _targetLanguage =>
      _profile.userSettings.targetLanguage != null
          ? PLanguageStore.byLangCode(_profile.userSettings.targetLanguage!)
          : null;

  bool getToolSetting(ToolSetting toolSetting) {
    final toolSettings = _profile.toolSettings;
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
        return _profile.userSettings.targetLanguage != null &&
            _targetLanguage != null &&
            tts.isLanguageSupported(_targetLanguage!) &&
            toolSettings.enableTTS;
      case ToolSetting.enableAutocorrect:
        return toolSettings.enableAutocorrect;
    }
  }

  bool get isTTSSupported =>
      _profile.userSettings.targetLanguage != null &&
      _targetLanguage != null &&
      tts.isLanguageSupported(_targetLanguage!);

  LanguageModel? get selectedSourceLanguage {
    return userL1 ?? pangeaController.languageController.systemLanguage;
  }

  LanguageModel? get selectedTargetLanguage {
    return userL2 ??
        ((selectedSourceLanguage?.langCode != 'en')
            ? PLanguageStore.byLangCode('en')
            : PLanguageStore.byLangCode('es'));
  }

  LanguageModel? get userL1 => _profile.userSettings.sourceLanguage != null
      ? PLanguageStore.byLangCode(_profile.userSettings.sourceLanguage!)
      : null;
  LanguageModel? get userL2 => _profile.userSettings.targetLanguage != null
      ? PLanguageStore.byLangCode(_profile.userSettings.targetLanguage!)
      : null;

  bool get publicProfile => _profile.userSettings.publicProfile ?? true;

  LanguageLevelTypeEnum get cefrLevel => _profile.userSettings.cefrLevel;

  Country? get country =>
      CountryService().findByName(_profile.userSettings.country);

  @override
  Widget build(BuildContext context) {
    return SettingsLearningView(this);
  }
}
