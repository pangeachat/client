import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/utils/p_language_store.dart';
import 'package:fluffychat/pangea/login/utils/lang_code_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LanguageSelectionPage extends StatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  State<LanguageSelectionPage> createState() => LanguageSelectionPageState();
}

class LanguageSelectionPageState extends State<LanguageSelectionPage> {
  final languages = MatrixState.pangeaController.pLanguageStore.targetOptions;
  List<LanguageModel> languageMap =
      MatrixState.pangeaController.pLanguageStore.targetOptions;

  LanguageModel? _selectedLanguage;
  LanguageModel? _baseLanguage;

  @override
  void initState() {
    super.initState();
    _baseLanguage =
        MatrixState.pangeaController.languageController.systemLanguage;

    _setFromCache();
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

  Future<void> _submit() async {
    if (_selectedLanguage == null) return;

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
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).languages),
      ),
      body: SafeArea(
        child: Center(
          child: Stack(
            children: [
              //test
              Container(
                padding: const EdgeInsets.only(top: 10.0, right: 30, left: 30),
                constraints: const BoxConstraints(
                  maxWidth: 450,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  onChanged: (textValue) {
                    setState(() {
                      languageMap = languages.where((lang) {
                        textValue = textValue.toLowerCase();
                        return lang.displayName
                            .toLowerCase()
                            .contains(textValue.toLowerCase());
                      }).toList();
                    });
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(30.0),
                constraints: const BoxConstraints(
                  maxWidth: 450,
                ),
                child: Column(
                  spacing: 20,
                  children: [
                    const SizedBox(height: 50.0),
                    Expanded(
                      child: Stack(
                        children: [
                          SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 16.0,
                                right: 16.0,
                                bottom: 40.0,
                              ),
                              child: Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                alignment: WrapAlignment.center,
                                children: languageMap
                                    .map(
                                      (l) => FilterChip(
                                        selected: _selectedLanguage == l,
                                        backgroundColor: _selectedLanguage == l
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.surface,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                          vertical: 4.0,
                                        ),
                                        label: Text(
                                          l.getDisplayName(context) ??
                                              l.displayName,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                        onSelected: (selected) {
                                          _setSelectedLanguage(
                                            selected ? l : null,
                                          );
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
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
                    Text(
                      L10n.of(context).chooseLanguage,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _selectedLanguage != null ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(L10n.of(context).letsGo),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
