import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';

/// The immersion toggle — "show the app in the language I'm learning".
///
/// This one tile keeps its copy in the learner's base language even while
/// immersion is on and the rest of the app is in the target language, so a
/// learner who can't read the target language yet can still find the switch
/// that got them there and turn it back off (#8353).
class AppLanguageSettingsTile extends StatefulWidget {
  final LearningSettingsViewModel viewModel;

  const AppLanguageSettingsTile({super.key, required this.viewModel});

  @override
  State<AppLanguageSettingsTile> createState() =>
      _AppLanguageSettingsTileState();
}

class _AppLanguageSettingsTileState extends State<AppLanguageSettingsTile> {
  /// Null while the base language's translation loads (its library is
  /// deferred, so on web it's a fetch) and whenever there's no translation to
  /// load — both fall back to the copy the rest of the app is in.
  L10n? _baseLanguageL10n;
  String? _requestedLangCode;

  @override
  void initState() {
    super.initState();
    _loadBaseLanguageL10n();
  }

  @override
  void didUpdateWidget(covariant AppLanguageSettingsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The base language dropdown sits on this same page, so the language this
    // tile has to speak can change under it.
    _loadBaseLanguageL10n();
  }

  Future<void> _loadBaseLanguageL10n() async {
    final langCode = widget.viewModel.selectedSourceLanguage?.langCode;
    if (langCode == _requestedLangCode) return;
    _requestedLangCode = langCode;

    final locale = LocaleProvider.localeFromLangCode(langCode);
    final l10n = locale != null && L10n.delegate.isSupported(locale)
        ? await lookupL10n(locale)
        : null;

    // The learner can pick another base language while this load is in flight.
    if (!mounted || langCode != _requestedLangCode) return;
    setState(() => _baseLanguageL10n = l10n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _baseLanguageL10n ?? L10n.of(context);
    final isOn = widget.viewModel.appLanguageIsTarget;
    return SwitchListTile.adaptive(
      value: isOn,
      title: Text(l10n.appInTargetLanguageTitle),
      subtitle: Text(
        // Once immersion is on, this tile is the odd one out on the page —
        // say why, rather than leaving it looking untranslated.
        isOn
            ? '${l10n.appInTargetLanguageDesc} '
                  '${l10n.appInTargetLanguageStaysInBaseLanguage}'
            : l10n.appInTargetLanguageDesc,
      ),
      activeThumbColor: AppConfig.activeToggleColor,
      onChanged: widget.viewModel.setAppLanguageIsTarget,
    );
  }
}
