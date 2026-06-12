import 'package:flutter/material.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/languages/language_display_name_prefix_widget.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/language_service.dart';
import 'package:fluffychat/pangea/languages/locale_provider.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/language_mismatch_popup.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickLanguageStepView extends StatefulWidget {
  final PickLanguageOnboardingStep step;
  final bool loading;
  final Object? error;
  final bool hasNextStep;
  final VoidCallback forward;

  @override
  const PickLanguageStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.error,
    required this.hasNextStep,
    required this.forward,
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
    final TextStyle textStyle = theme.textTheme.bodyLarge!;

    final type = _step.state.userType;
    final title = switch (type) {
      UserType.teacher => L10n.of(context).pickLanguageTeacherStepTitle,
      UserType.student => L10n.of(context).onboardingLanguagesTitle,
      null => L10n.of(context).pickLanguageTeacherStepTitle,
    };

    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Column(
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
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
                            sliver: ValueListenableBuilder(
                              valueListenable: _selectedTargetLanguage,
                              builder: (context, selected, _) {
                                final filtered = _languages
                                    .where(
                                      (l) => LanguageModel.search(
                                        l,
                                        val.text,
                                        context,
                                      ),
                                    )
                                    .toList();
                                final flagSize = 56.0;
                                return SliverGrid(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final l = filtered[index];
                                    final isSelected = selected == l;
                                    final hasSelection = selected != null;
                                    return Opacity(
                                      opacity: hasSelection && !isSelected
                                          ? 0.5
                                          : 1.0,
                                      child: SizedBox.expand(
                                        child: Material(
                                          color: isSelected
                                              ? AppConfig.goldLight.withAlpha(
                                                  100,
                                                )
                                              : theme
                                                    .colorScheme
                                                    .surfaceContainer,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16.0,
                                            ),
                                            side: isSelected
                                                ? BorderSide(
                                                    color: AppConfig.yellowDark
                                                        .withAlpha(100),
                                                    width: 4.0,
                                                  )
                                                : BorderSide(
                                                    color: theme
                                                        .colorScheme
                                                        .surfaceContainerHigh,
                                                    width: 2.0,
                                                  ),
                                          ),
                                          child: InkWell(
                                            onTap: () => _setTargetLanguage(
                                              isSelected ? null : l,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16.0,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12.0,
                                                    horizontal: 8.0,
                                                  ),
                                              child:
                                                  LanguageDisplayNamePrefixWidget(
                                                    l,
                                                    style: textStyle,
                                                    iconSize: flagSize,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }, childCount: filtered.length),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 180.0,
                                        mainAxisSpacing: 12.0,
                                        crossAxisSpacing: 12.0,
                                        childAspectRatio: 1.1,
                                      ),
                                );
                              },
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
            ),
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([
            _selectedBaseLanguage,
            _selectedTargetLanguage,
          ]),
          builder: (context, _) => ElevatedButton(
            onPressed: _step.enableGoForward ? widget.forward : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              minimumSize: const Size.fromHeight(48),
            ),
            child: SizedBox(
              height: 24,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: widget.loading
                      ? SizedBox(
                          key: const ValueKey('loading'),
                          width: double.infinity,
                          child: const LinearProgressIndicator(),
                        )
                      : Text(
                          widget.hasNextStep
                              ? _step.nextStepText(L10n.of(context))
                              : _step.lastStepText(L10n.of(context)),
                          key: const ValueKey('text'),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
