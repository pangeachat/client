// Flutter imports:

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/languages/analytics_language_order.dart';
import 'package:fluffychat/features/languages/l2_support_enum.dart';
import 'package:fluffychat/features/languages/language_display_name_postfix_widget.dart';
import 'package:fluffychat/features/languages/language_flag_chip.dart';
import 'package:fluffychat/features/languages/language_flag_or_fallback.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/pangea_search_bar.dart';

class PLanguageDropdown extends StatefulWidget {
  final List<LanguageModel> languages;
  final LanguageModel? initialLanguage;
  final Function(LanguageModel) onChange;
  final bool isL2List;
  final String? decorationText;
  final String? error;
  final Color? backgroundColor;
  final bool hasError;
  final bool enabled;

  const PLanguageDropdown({
    super.key,
    required this.languages,
    required this.onChange,
    required this.initialLanguage,
    this.decorationText,
    this.isL2List = false,
    this.error,
    this.backgroundColor,
    this.hasError = false,
    this.enabled = true,
  });

  @override
  PLanguageDropdownState createState() => PLanguageDropdownState();
}

class PLanguageDropdownState extends State<PLanguageDropdown> {
  final TextEditingController _searchController = TextEditingController();

  // dropdown_button2 sizes every item to this height by default
  // (kMinInteractiveDimension) unless customHeights is supplied; an analytics
  // row's extra level line needs its own, taller slot.
  static const double _itemHeight = 48.0;
  static const double _analyticsItemHeight = 64.0;
  static const double _dividerItemHeight = 17.0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<LanguageModel> sortedLanguages = widget.languages;
    final String systemLang = Localizations.localeOf(context).languageCode;

    // if there is no initial language, the system language should be the first in the list
    // otherwise, display in alphabetical order
    final List<String> languagePriority = widget.initialLanguage == null
        ? [systemLang]
        : [];

    int sortLanguages(LanguageModel a, LanguageModel b) {
      final String aLang = a.langCode;
      final String bLang = b.langCode;
      if (aLang == bLang) return 0;

      final bool aIsPriority = languagePriority.contains(a.langCode);
      final bool bIsPriority = languagePriority.contains(b.langCode);
      if (!aIsPriority && !bIsPriority) {
        return a
            .getDisplayName(L10n.of(context))
            .compareTo(b.getDisplayName(L10n.of(context)));
      }

      if (aIsPriority && bIsPriority) {
        final int aPriority = languagePriority.indexOf(a.langCode);
        final int bPriority = languagePriority.indexOf(b.langCode);
        return aPriority - bPriority;
      }

      return aIsPriority ? -1 : 1;
    }

    sortedLanguages.sort((a, b) => sortLanguages(a, b));

    // Languages the learner already has analytics in sort to the top of the
    // L2 list, so the two or three they actually move between are reachable
    // without scrolling or searching — profile.instructions.md, "Switching
    // from context". Left null for the base-language list.
    final Map<LanguageModel, LanguageAnalyticsProfileEntry>?
    analyticsByLanguage = widget.isL2List
        ? MatrixState
              .pangeaController
              .userController
              .publicProfile
              ?.analytics
              .languageAnalytics
        : null;

    final order = AnalyticsLanguageOrder.of(
      sortedLanguages,
      analyticsByLanguage,
    );
    final List<LanguageModel> displayOrder = order.displayOrder;
    final int dividerIndex = order.dividerIndex;

    final bool hasError = widget.error != null || widget.hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          child: DropdownButtonFormField2<LanguageModel>(
            customButton:
                widget.initialLanguage != null &&
                    sortedLanguages.contains(widget.initialLanguage)
                ? LanguageDropDownEntry(
                    languageModel: widget.initialLanguage!,
                    isL2List: widget.isL2List,
                    isDropdown: true,
                    enabled: widget.enabled,
                    analytics: analyticsByLanguage?[widget.initialLanguage],
                  )
                : null,
            menuItemStyleData: MenuItemStyleData(
              padding: EdgeInsets.zero,
              customHeights: [
                for (var i = 0; i < displayOrder.length; i++) ...[
                  if (i == dividerIndex) _dividerItemHeight,
                  analyticsByLanguage?[displayOrder[i]] != null
                      ? _analyticsItemHeight
                      : _itemHeight,
                ],
              ],
            ),
            decoration: InputDecoration(
              labelText: widget.decorationText,
              enabledBorder: hasError
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  : null,
              focusedBorder: hasError
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            isExpanded: true,
            dropdownStyleData: DropdownStyleData(
              maxHeight: kIsWeb ? 500 : null,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color:
                    widget.backgroundColor ??
                    Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
            items: [
              for (var i = 0; i < displayOrder.length; i++) ...[
                // Separates the analytics languages above from the rest of
                // the list; dropped once a search is typed, since
                // LanguageModel.search only matches a null item against an
                // empty query — so a filtered result list never carries a
                // stray rule.
                if (i == dividerIndex)
                  DropdownMenuItem(
                    enabled: false,
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Divider(height: _dividerItemHeight),
                      ),
                    ),
                  ),
                DropdownMenuItem(
                  value: displayOrder[i],
                  child: Container(
                    color: widget.initialLanguage == displayOrder[i]
                        ? Theme.of(context).colorScheme.primary.withAlpha(20)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: LanguageDropDownEntry(
                      languageModel: displayOrder[i],
                      isL2List: widget.isL2List,
                      analytics: analyticsByLanguage?[displayOrder[i]],
                    ),
                  ),
                ),
              ],
            ],
            onChanged: widget.enabled
                ? (value) => widget.onChange(value!)
                : null,
            value: widget.initialLanguage,
            dropdownSearchData: DropdownSearchData(
              searchController: _searchController,
              searchInnerWidgetHeight: 50,
              searchInnerWidget: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: PangeaSearchBar(
                  labelText: L10n.of(context).searchLanguagesHint,
                  autofocus: true,
                  controller: _searchController,
                ),
              ),
              searchMatchFn: (item, searchValue) =>
                  LanguageModel.search(item.value, searchValue, context),
            ),
            onMenuStateChange: (isOpen) {
              if (!isOpen) _searchController.clear();
            },
            enableFeedback: widget.enabled,
          ),
        ),
        AnimatedSize(
          duration: FluffyThemes.animationDuration,
          child: widget.error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Semantics(
                    container: true,
                    child: Text(
                      widget.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class LanguageDropDownEntry extends StatelessWidget {
  final LanguageModel languageModel;
  final bool isL2List;
  final bool isDropdown;
  final bool enabled;

  /// This language's entry in the learner's analytics. Non-null adds a level
  /// caption below the name (profile.instructions.md, "Switching from
  /// context") and, when [languageModel] also has a usable flag, promotes
  /// the leading icon from [Avatar]'s hashed-letter circle to
  /// [LanguageFlagChip]. A language with analytics but no usable flag (a
  /// variant-disambiguated base language, one lacking a flag asset, or one
  /// whose flag couldn't be fetched — see [LanguageFlagOrFallback]) keeps
  /// the circle rather than falling to [LanguageFlagChip]'s own two-letter
  /// code badge, which reads as squished at this row's size next to a full
  /// circle.
  final LanguageAnalyticsProfileEntry? analytics;

  const LanguageDropDownEntry({
    super.key,
    required this.languageModel,
    required this.isL2List,
    this.isDropdown = false,
    this.enabled = true,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    final analytics = this.analytics;
    final avatar = Avatar(name: languageModel.langCode, size: 30);
    return Row(
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: ExcludeSemantics(
            child: analytics != null
                ? LanguageFlagOrFallback(
                    language: languageModel,
                    flag: LanguageFlagChip(
                      language: languageModel,
                      langCode: languageModel.langCode,
                      width: 30,
                      height: 22,
                      radius: 4,
                      borderWidth: 1,
                      alwaysShowCode: false,
                    ),
                    fallback: avatar,
                  )
                : avatar,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: LanguageDisplayNamePostfixWidget(
                      languageModel,
                      style: TextStyle(
                        color: enabled
                            ? Theme.of(context).textTheme.bodyLarge!.color
                            : Theme.of(context).disabledColor,
                        fontSize: 14,
                      ),
                      iconSize: 14,
                      spacing: 6.0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isL2List && languageModel.l2Support != L2SupportEnum.full)
                    languageModel.l2Support.toBadge(context),
                ],
              ),
              if (analytics != null)
                Text(
                  L10n.of(context).languageDropdownLevel(analytics.level),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (isDropdown)
          Icon(
            Icons.arrow_drop_down,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      ],
    );
  }
}
