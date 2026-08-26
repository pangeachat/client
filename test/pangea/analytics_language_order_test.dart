import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/languages/analytics_language_order.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/analytics_profile_model.dart';

/// #8495 — the pure ordering rule behind profile.instructions.md, "Switching
/// from context": languages the learner already has analytics in sort to the
/// top, alphabetically below the rule. Shared by PLanguageDropdown and the
/// language switcher sheet — see p_language_dropdown_test.dart and
/// language_switcher_sheet_test.dart for the widget-level behavior this
/// enables.
void main() {
  LanguageModel lang(String code) =>
      LanguageModel(langCode: code, displayName: code);

  final french = lang('fr');
  final spanish = lang('es');
  final italian = lang('it');
  final languages = [french, spanish, italian];

  test('with no analytics map, every language is "remaining", in order', () {
    final order = AnalyticsLanguageOrder.of(languages, null);

    expect(order.analyticsLanguages, isEmpty);
    expect(order.remainingLanguages, languages);
    expect(order.displayOrder, languages);
    expect(order.dividerIndex, -1);
  });

  test('with an empty analytics map, every language is "remaining"', () {
    final order = AnalyticsLanguageOrder.of(languages, {});

    expect(order.analyticsLanguages, isEmpty);
    expect(order.remainingLanguages, languages);
    expect(order.dividerIndex, -1);
  });

  test('analytics languages lead, in their input order, ahead of the rest', () {
    final order = AnalyticsLanguageOrder.of(languages, {
      'es': LanguageAnalyticsProfileEntry(4, 0),
      'fr': LanguageAnalyticsProfileEntry(7, 0),
    });

    expect(order.analyticsLanguages, [french, spanish]);
    expect(order.remainingLanguages, [italian]);
    expect(order.displayOrder, [french, spanish, italian]);
    expect(order.dividerIndex, 2);
  });

  test('every language having analytics leaves nothing to divide', () {
    final order = AnalyticsLanguageOrder.of(languages, {
      for (final l in languages)
        l.langCodeShort: LanguageAnalyticsProfileEntry(1, 0),
    });

    expect(order.remainingLanguages, isEmpty);
    expect(order.displayOrder, languages);
    expect(order.dividerIndex, -1);
  });

  test('an analytics entry for a language outside the list is ignored', () {
    final order = AnalyticsLanguageOrder.of(
      [french, italian],
      {
        'es': LanguageAnalyticsProfileEntry(4, 0),
        'fr': LanguageAnalyticsProfileEntry(7, 0),
      },
    );

    expect(order.analyticsLanguages, [french]);
    expect(order.remainingLanguages, [italian]);
    expect(order.dividerIndex, 1);
  });

  test(
    'every regional variant of an analytics language joins the top group',
    () {
      final canadianFrench = lang('fr-CA');
      final order = AnalyticsLanguageOrder.of(
        [french, canadianFrench, italian],
        {'fr': LanguageAnalyticsProfileEntry(13, 0)},
      );

      // One language, one set of analytics: fr and fr-CA share the entry, so
      // they lead together and both show level 13 (#8582).
      expect(order.analyticsLanguages, [french, canadianFrench]);
      expect(order.remainingLanguages, [italian]);
    },
  );
}
