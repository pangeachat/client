import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/analytics_language_order.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

/// The switcher every language chip opens (profile.instructions.md,
/// "Switching from context", point 7): one list of every target language —
/// the same dropdown learning settings uses — with the languages the
/// learner already has analytics in sorted to the top. Picking one switches
/// immediately and closes the sheet.
class LanguageSwitcherSheet extends StatefulWidget {
  /// The language the chip that opened this sheet was showing — pinned
  /// first, above the analytics group, since it's the language the learner
  /// almost certainly opened the sheet to switch to.
  final LanguageModel? targetedLanguage;

  const LanguageSwitcherSheet({this.targetedLanguage, super.key});

  static Future<void> show(
    BuildContext context, {
    LanguageModel? targetedLanguage,
  }) => showAdaptiveBottomSheet(
    context: context,
    builder: (context) =>
        LanguageSwitcherSheet(targetedLanguage: targetedLanguage),
  );

  @override
  State<LanguageSwitcherSheet> createState() => _LanguageSwitcherSheetState();
}

class _LanguageSwitcherSheetState extends State<LanguageSwitcherSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _query = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _query.value = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _selectLanguage(LanguageModel language) async {
    final userController = MatrixState.pangeaController.userController;
    final navigator = Navigator.of(context, rootNavigator: false);

    final result = await showFutureLoadingDialog(
      context: context,
      future: () => userController.updateTargetLanguage(language),
    );
    if (result.isError || !mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final userController = MatrixState.pangeaController.userController;
    final languages = MatrixState.pangeaController.pLanguageStore.targetOptions;
    final currentLanguage = userController.userL2;
    final baseLanguage = userController.userL1;

    final targeted = widget.targetedLanguage;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.whatAreYouLearning),
        leading: CloseButton(
          onPressed: Navigator.of(context, rootNavigator: false).pop,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: PangeaSearchBar(
              controller: _searchController,
              labelText: l10n.searchLanguagesHint,
            ),
          ),
          Expanded(
            // Subscribed during build and read inside the builder, so a level
            // corrected while the sheet is open updates here rather than
            // waiting for an unrelated rebuild (#8582).
            child: StreamBuilder(
              stream: userController.publicProfileStream.stream,
              builder: (context, _) => ValueListenableBuilder(
                valueListenable: _query,
                builder: (context, query, _) {
                  final analytics = userController.publicProfile?.analytics;
                  final order = AnalyticsLanguageOrder.of(languages, analytics);

                  // The targeted language leads the top group, ahead of the
                  // analytics languages it's drawn from or otherwise joins —
                  // see [targetedLanguage].
                  final topGroup = [
                    if (targeted != null && languages.contains(targeted))
                      targeted,
                    ...order.analyticsLanguages.where(
                      (lang) => lang != targeted,
                    ),
                  ];
                  final remainingGroup = order.remainingLanguages
                      .where((lang) => lang != targeted)
                      .toList();
                  final fullOrder = [...topGroup, ...remainingGroup];
                  final dividerIndex =
                      topGroup.isNotEmpty && remainingGroup.isNotEmpty
                      ? topGroup.length
                      : -1;

                  final showDivider = query.isEmpty && dividerIndex != -1;
                  final displayLanguages = query.isEmpty
                      ? fullOrder
                      : fullOrder
                            .where(
                              (lang) =>
                                  LanguageModel.search(lang, query, context),
                            )
                            .toList();

                  return ListView(
                    children: [
                      for (var i = 0; i < displayLanguages.length; i++) ...[
                        if (showDivider && i == dividerIndex)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Divider(height: 1),
                          ),
                        _LanguageSwitcherRow(
                          language: displayLanguages[i],
                          analytics: analytics?.displayEntryFor(
                            displayLanguages[i],
                          ),
                          isCurrent: UserController.isCurrentTargetLanguage(
                            displayLanguages[i],
                            currentLanguage?.langCode,
                          ),
                          isBaseLanguage: UserController.isBaseLanguage(
                            displayLanguages[i],
                            baseLanguage?.langCode,
                          ),
                          onSelect: () => _selectLanguage(displayLanguages[i]),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the switcher: [LanguageDropDownEntry] (flag/avatar, name,
/// level) plus a trailing checkmark for the current language, or the base-
/// language reason it can't be picked.
class _LanguageSwitcherRow extends StatelessWidget {
  final LanguageModel language;
  final LanguageAnalyticsProfileEntry? analytics;
  final bool isCurrent;
  final bool isBaseLanguage;
  final VoidCallback onSelect;

  const _LanguageSwitcherRow({
    required this.language,
    required this.analytics,
    required this.isCurrent,
    required this.isBaseLanguage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectable = !isCurrent && !isBaseLanguage;

    return Material(
      color: isCurrent
          ? theme.colorScheme.primary.withAlpha(20)
          : Colors.transparent,
      child: InkWell(
        onTap: selectable ? onSelect : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: LanguageDropDownEntry(
                  languageModel: language,
                  isL2List: true,
                  enabled: !isBaseLanguage,
                  analytics: analytics,
                ),
              ),
              if (isCurrent)
                Icon(Icons.check, color: theme.colorScheme.primary)
              else if (isBaseLanguage)
                Text(
                  L10n.of(context).languageSwitcherBaseLanguageLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
