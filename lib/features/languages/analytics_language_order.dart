import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';

/// Languages the learner already has analytics in, sorted to the top of a
/// target-language list — see profile.instructions.md, "Switching from
/// context": the two or three languages a learner actually moves between
/// should be reachable without scrolling or searching. Shared by
/// [PLanguageDropdown] and the language switcher sheet, so the two controls
/// order languages identically wherever they're opened.
class AnalyticsLanguageOrder {
  /// [languages] with an entry in [analyticsByLanguage], in [languages]'
  /// existing order.
  final List<LanguageModel> analyticsLanguages;

  /// The rest of [languages], in their existing order.
  final List<LanguageModel> remainingLanguages;

  /// [analyticsLanguages] followed by [remainingLanguages].
  final List<LanguageModel> displayOrder;

  /// Index into [displayOrder] a divider belongs at, or -1 when there's
  /// nothing to divide — no analytics languages, or every option has one.
  final int dividerIndex;

  AnalyticsLanguageOrder._(this.analyticsLanguages, this.remainingLanguages)
    : displayOrder = [...analyticsLanguages, ...remainingLanguages],
      dividerIndex =
          analyticsLanguages.isNotEmpty && remainingLanguages.isNotEmpty
          ? analyticsLanguages.length
          : -1;

  /// [analyticsByLanguage] is keyed by short language code and is null for a
  /// list this rule doesn't apply to (the base-language list), which produces
  /// [analyticsLanguages] empty. Every regional variant of a language the
  /// learner has analytics in joins the top group, since they share one set of
  /// analytics.
  factory AnalyticsLanguageOrder.of(
    List<LanguageModel> languages,
    Map<String, LanguageAnalyticsProfileEntry>? analyticsByLanguage,
  ) {
    final analyticsLanguages = analyticsByLanguage == null
        ? <LanguageModel>[]
        : languages
              .where(
                (lang) => analyticsByLanguage.containsKey(lang.langCodeShort),
              )
              .toList();
    final remainingLanguages = analyticsLanguages.isEmpty
        ? languages
        : languages
              .where((lang) => !analyticsLanguages.contains(lang))
              .toList();
    return AnalyticsLanguageOrder._(analyticsLanguages, remainingLanguages);
  }
}
