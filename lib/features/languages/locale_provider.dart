import 'package:flutter/material.dart';

import 'package:intl/intl.dart' as intl;

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;

  Locale? get locale => _locale;

  void setLocale(String? value) {
    if (value == null || value.isEmpty) {
      _locale = null;
      notifyListeners();
      return;
    }

    // Language codes come from the CMS as BCP-47 with '-' (e.g. `es-MX`,
    // `zh-TW`). The app UI is translated by language (and, for Chinese, by
    // script) — not by region — so resolve to the language and drop the
    // region, which Flutter then matches against the base translation. The
    // previous code split on '_' only, so a hyphenated code became a malformed
    // `Locale('es-MX')` that matched nothing and fell back to English.
    final parts = value.replaceAll('_', '-').split('-');
    final lang = parts.first.toLowerCase();
    if (!intl.DateFormat.localeExists(lang)) {
      _locale = null;
      notifyListeners();
      return;
    }

    final suffix = parts.length > 1 ? parts[1].toLowerCase() : null;
    // Traditional Chinese ships as its own translation (`intl_zh_Hant`); map
    // its script/region codes to it. Simplified and every other variant use
    // the base language.
    if (lang == 'zh' &&
        suffix != null &&
        const {'hant', 'tw', 'hk', 'mo'}.contains(suffix)) {
      _locale = const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      );
    } else {
      _locale = Locale(lang);
    }
    notifyListeners();
  }
}
