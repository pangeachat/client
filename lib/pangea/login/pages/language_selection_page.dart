import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/language_service.dart';
import 'package:fluffychat/pangea/languages/p_language_store.dart';
import 'package:fluffychat/pangea/learning_settings/p_language_dropdown.dart';
import 'package:fluffychat/pangea/login/utils/lang_code_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

class IdenticalLanguageException implements Exception {}

class LanguageSelectionPage extends StatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  State<LanguageSelectionPage> createState() => LanguageSelectionPageState();
}

class LanguageSelectionPageState extends State<LanguageSelectionPage> {
  Object? _error;

  LanguageModel? _selectedLanguage;
  LanguageModel? _baseLanguage;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _baseLanguage = LanguageService.systemLanguage;
    _setFromCache();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // The user may set their target language initally, then return to this page
  // to change it again. Try and get the cached values if present.
  void _setFromCache() {
    LangCodeRepo.get().then((langSettings) {
      if (langSettings == null) return;
      final cachedTargetLang =
          PLanguageStore.byLangCode(langSettings.targetLangCode);
      final cachedBaseLang = langSettings.baseLangCode != null
          ? PLanguageStore.byLangCode(langSettings.baseLangCode!)
          : null;

      if (cachedTargetLang == _selectedLanguage &&
          cachedBaseLang == _baseLanguage) {
        return;
      }

      setState(() {
        _selectedLanguage = cachedTargetLang ?? _selectedLanguage;
        _baseLanguage = cachedBaseLang ?? _baseLanguage;
      });
    });
  }

  void _setSelectedLanguage(LanguageModel? l) {
    setState(() => _selectedLanguage = l);
  }

  void _setBaseLanguage(LanguageModel? l) {
    setState(() => _baseLanguage = l);
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_selectedLanguage == null) return;
    if (_selectedLanguage?.langCodeShort == _baseLanguage?.langCodeShort) {
      setState(() => _error = IdenticalLanguageException());
      return;
    }

    await LangCodeRepo.set(
      LanguageSettings(
        targetLangCode: _selectedLanguage!.langCode,
        baseLangCode: _baseLanguage?.langCode,
      ),
    );
    context.go(
      GoRouterState.of(context).fullPath?.contains('home') == true
          ? '/home/language/signup'
          : '/registration/create',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languages = MatrixState.pangeaController.pLanguageStore.targetOptions;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return Scaffold(
      appBar: AppBar(
        title: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 450,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BackButton(
                onPressed: Navigator.of(context).pop,
              ),
              Text(L10n.of(context).onboardingLanguagesTitle),
              const SizedBox(
                width: 40.0,
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20.0),
            constraints: const BoxConstraints(
              maxWidth: 450,
            ),
            child: Column(
              spacing: 24.0,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    hintText: L10n.of(context).searchLanguagesHint,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: ValueListenableBuilder(
                          valueListenable: _searchController,
                          builder: (context, val, __) {
                            return SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 16.0,
                                  right: 16.0,
                                  bottom: 60.0,
                                ),
                                child: Wrap(
                                  spacing: isColumnMode ? 16.0 : 8.0,
                                  runSpacing: isColumnMode ? 16.0 : 8.0,
                                  alignment: WrapAlignment.center,
                                  children: languages
                                      .where(
                                        (l) => l
                                            .getDisplayName(context)
                                            .toLowerCase()
                                            .contains(
                                              _searchController.text
                                                  .toLowerCase(),
                                            ),
                                      )
                                      .map(
                                        (l) => ShimmerBackground(
                                          enabled: _selectedLanguage == null,
                                          borderRadius: const BorderRadius.all(
                                            Radius.circular(16.0),
                                          ),
                                          child: FilterChip(
                                            selected: _selectedLanguage == l,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(16.0),
                                              ),
                                            ),
                                            backgroundColor:
                                                _selectedLanguage == l
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.surface,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8.0,
                                              vertical: 4.0,
                                            ),
                                            label: Text(
                                              l.getDisplayName(context),
                                              style: isColumnMode
                                                  ? theme.textTheme.bodyLarge
                                                  : theme.textTheme.bodyMedium,
                                            ),
                                            onSelected: (selected) {
                                              _setSelectedLanguage(
                                                selected ? l : null,
                                              );
                                            },
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: IgnorePointer(
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  theme.colorScheme.surface,
                                  theme.colorScheme.surface.withAlpha(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: FluffyThemes.animationDuration,
                  child: _selectedLanguage != null &&
                          _selectedLanguage?.langCodeShort ==
                              _baseLanguage?.langCodeShort
                      ? PLanguageDropdown(
                          languages: languages,
                          onChange: _setBaseLanguage,
                          initialLanguage: _baseLanguage,
                          decorationText: L10n.of(context).myBaseLanguage,
                          error: _error is IdenticalLanguageException
                              ? L10n.of(context).noIdenticalLanguages
                              : null,
                        )
                      : const SizedBox(),
                ),
                ShimmerBackground(
                  enabled: _selectedLanguage != null,
                  borderRadius: BorderRadius.circular(24.0),
                  child: ElevatedButton(
                    onPressed: _selectedLanguage != null ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(L10n.of(context).letsGo),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
