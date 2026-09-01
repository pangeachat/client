import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_display_name_prefix_widget.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/languages/locale_provider.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

// This step's page is capped wider than the rest of onboarding (840, for the
// language grid), so its bottom controls take the standard step's inner width —
// the shared cap less the page shell's 16px side padding — to come out the same
// size as every other step's CTA.
const double _controlMaxWidth = OnboardingStep.defaultContentMaxWidth - 32.0;

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

    _selectedBaseLanguage.addListener(_onBaseLanguageChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setBaseLanguage(baseLanguage);
      _setTargetLanguage(targetLanguage);
    });
  }

  @override
  void dispose() {
    _selectedBaseLanguage.removeListener(_onBaseLanguageChanged);
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

    final l10n = L10n.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      lang != null
          ? l10n.selectedBaseLanguage(lang.getDisplayName(l10n))
          : l10n.resetBaseLanguage,
      Directionality.of(context),
    );
  }

  void _setTargetLanguage(LanguageModel? lang) {
    if (_step.state.targetLanguage == lang &&
        _selectedTargetLanguage.value == lang) {
      return;
    }

    _step.selectTargetLanguage(lang);
    _selectedTargetLanguage.value = lang;

    final l10n = L10n.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      lang != null
          ? l10n.selectedTargetLanguage(lang.getDisplayName(l10n))
          : l10n.resetTargetLanguage,
      Directionality.of(context),
    );
  }

  void _onBaseLanguageChanged() {
    final lang = _selectedBaseLanguage.value;
    if (lang != null) {
      Future.delayed(Duration(milliseconds: 500), () => _setAppLanguage(lang));
    }
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
                Semantics(
                  container: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 12.0),
                PangeaSearchBar(
                  labelText: L10n.of(context).searchLanguagesHint,
                  controller: _searchController,
                ),
                SizedBox(height: 12.0),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _searchController,
                    builder: (context, val, _) {
                      final filtered = _languages
                          .where(
                            (l) => LanguageModel.search(l, val.text, context),
                          )
                          .toList();
                      return Semantics(
                        label: _searchController.text.isNotEmpty
                            ? L10n.of(
                                context,
                              ).searchedResultsLabel(_searchController.text)
                            : L10n.of(context).languageListLabel,
                        container: true,
                        child: CustomScrollView(
                          semanticChildCount: filtered.length,
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.only(
                                left: 16.0,
                                right: 16.0,
                              ),
                              sliver: ValueListenableBuilder(
                                valueListenable: _selectedTargetLanguage,
                                builder: (context, selected, _) {
                                  final flagSize = 56.0;
                                  return SliverGrid(
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final l = filtered[index];
                                      final isSelected = selected == l;
                                      final hasSelection = selected != null;
                                      return Semantics(
                                        button: true,
                                        selected: isSelected,
                                        child: Opacity(
                                          opacity: hasSelection && !isSelected
                                              ? 0.5
                                              : 1.0,
                                          child: SizedBox.expand(
                                            child: Material(
                                              color: isSelected
                                                  ? AppConfig.goldLight
                                                        .withAlpha(100)
                                                  : theme
                                                        .colorScheme
                                                        .surfaceContainer,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
                                                side: isSelected
                                                    ? BorderSide(
                                                        color: AppConfig
                                                            .yellowDark
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
                                                borderRadius:
                                                    BorderRadius.circular(16.0),
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
                                        ),
                                      );
                                    }, childCount: filtered.length),
                                    gridDelegate:
                                        const SliverGridDelegateWithMaxCrossAxisExtent(
                                          // Bigger tiles than the old 180 so
                                          // cells stay legible as the grid
                                          // densens.
                                          maxCrossAxisExtent: 220.0,
                                          mainAxisSpacing: 12.0,
                                          crossAxisSpacing: 12.0,
                                          mainAxisExtent: 150.0,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
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
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _controlMaxWidth,
                              ),
                              child: Padding(
                                padding: EdgeInsets.only(top: 12.0),
                                child: PLanguageDropdown(
                                  languages: _languages,
                                  onChange: _setBaseLanguage,
                                  initialLanguage: _selectedBaseLanguage.value,
                                  decorationText: L10n.of(context).alreadySpeak,
                                  error:
                                      widget.error is IdenticalLanguageException
                                      ? L10n.of(context).noIdenticalLanguages
                                      : null,
                                ),
                              ),
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
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _controlMaxWidth),
              child: OnboardingForwardButton(
                onPressed: _step.enableGoForward ? widget.forward : null,
                loading: widget.loading,
                label: widget.hasNextStep
                    ? _step.nextStepText(L10n.of(context))
                    : _step.lastStepText(L10n.of(context)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
