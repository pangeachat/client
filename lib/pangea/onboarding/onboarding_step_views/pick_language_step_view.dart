import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/languages/language_display_name_prefix_widget.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/language_service.dart';
import 'package:fluffychat/pangea/languages/locale_provider.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_mismatch_popup.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickLanguageStepView extends StatefulWidget {
  final PickLanguageOnboardingStep step;
  final VoidCallback updateEnableNext;
  final Object? error;

  @override
  const PickLanguageStepView({
    super.key,
    required this.step,
    required this.updateEnableNext,
    required this.error,
  });

  @override
  PickLanguageStepViewState createState() => PickLanguageStepViewState();
}

class PickLanguageStepViewState extends State<PickLanguageStepView> {
  late final PickLanguageOnboardingStep _step;

  final TextEditingController _searchController = TextEditingController();

  final ValueNotifier<LanguageModel?> _selectedTargetLanguage = ValueNotifier(
    null,
  );
  final ValueNotifier<LanguageModel?> _selectedBaseLanguage = ValueNotifier(
    null,
  );

  @override
  void initState() {
    super.initState();
    _step = widget.step;

    final userL1 = MatrixState.pangeaController.userController.userL1;
    final userL2 = MatrixState.pangeaController.userController.userL2;
    final systemLanguage = LanguageService.systemLanguage;
    final defaultLanguage = PLanguageStore.byLangCode(
      LanguageKeys.defaultLanguage,
    );

    final targetLanguage = _step.state.targetLanguage ?? userL2;
    final baseLanguage =
        _step.state.baseLanguage ?? userL1 ?? systemLanguage ?? defaultLanguage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setBaseLanguage(baseLanguage);
      _setTargetLanguage(targetLanguage);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _selectedBaseLanguage.dispose();
    _selectedTargetLanguage.dispose();
    super.dispose();
  }

  final _languages = MatrixState.pangeaController.pLanguageStore.targetOptions;

  bool get _hasIdenticalLanguages {
    final base = _selectedBaseLanguage.value;
    final target = _selectedTargetLanguage.value;
    if (base == null || target == null) return false;
    return base.langCodeShort == target.langCodeShort;
  }

  void _setBaseLanguage(LanguageModel? lang) {
    if (_step.state.baseLanguage == lang &&
        _selectedBaseLanguage.value == lang) {
      return;
    }

    _step.selectBaseLanguage(lang);
    _selectedBaseLanguage.value = lang;
    widget.updateEnableNext();

    if (lang != null) {
      _setAppLanguage(lang);
    }
  }

  void _setTargetLanguage(LanguageModel? lang) {
    if (_step.state.targetLanguage == lang &&
        _selectedTargetLanguage.value == lang) {
      return;
    }

    _step.selectTargetLanguage(lang);
    _selectedTargetLanguage.value = lang;
    widget.updateEnableNext();
  }

  void _setAppLanguage(LanguageModel language) {
    try {
      Provider.of<LocaleProvider>(
        context,
        listen: false,
      ).setLocale(language.langCode);
    } catch (e, s) {
      Logs().e('Error setting app language', e);
      ErrorHandler.logError(e: e, s: s, data: {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    TextStyle textStyle = DefaultTextStyle.of(context).style;
    textStyle = textStyle.merge(
      isColumnMode ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium,
    );

    final type = _step.state.userType;
    final title = switch (type) {
      UserType.teacher => L10n.of(context).pickLanguageTeacherStepTitle,
      UserType.student => L10n.of(context).onboardingLanguagesTitle,
      null => L10n.of(context).pickLanguageTeacherStepTitle,
    };

    return Column(
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12.0),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(50)),
          ),
        ),
        SizedBox(height: 12.0),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: _searchController,
            builder: (context, val, _) {
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 60.0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: ValueListenableBuilder(
                        valueListenable: _selectedTargetLanguage,
                        builder: (context, selected, _) => Wrap(
                          spacing: 8.0,
                          runSpacing: 16.0,
                          alignment: WrapAlignment.center,
                          children: _languages
                              .where(
                                (l) =>
                                    LanguageModel.search(l, val.text, context),
                              )
                              .map(
                                (l) => ShimmerBackground(
                                  enabled: selected == null,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(16.0),
                                  ),
                                  child: FilterChip(
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    selected: selected == l,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(16.0),
                                      ),
                                    ),
                                    backgroundColor: selected == l
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.surfaceContainer,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    label: LanguageDisplayNamePrefixWidget(
                                      l,
                                      style: textStyle,
                                      iconSize: isColumnMode ? 16.0 : 12.0,
                                    ),
                                    onSelected: (selected) {
                                      _setTargetLanguage(selected ? l : null);
                                    },
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([
            _selectedBaseLanguage,
            _selectedTargetLanguage,
          ]),
          builder: (context, _) => AnimatedSize(
            duration: FluffyThemes.animationDuration,
            child: _hasIdenticalLanguages
                ? Padding(
                    padding: EdgeInsets.only(top: 12.0),
                    child: PLanguageDropdown(
                      languages: _languages,
                      onChange: _setBaseLanguage,
                      initialLanguage: _selectedBaseLanguage.value,
                      decorationText: L10n.of(context).alreadySpeak,
                      error: widget.error is IdenticalLanguageException
                          ? L10n.of(context).noIdenticalLanguages
                          : null,
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      ],
    );
  }
}
