import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:intl/date_symbol_data_local.dart';

import 'package:fluffychat/features/languages/locale_provider.dart';

void main() {
  group('LocaleProvider.setLocale', () {
    late LocaleProvider provider;
    // setLocale validates the language via intl's date-locale data, which the
    // app loads at startup; load it here too so the unit test mirrors runtime.
    setUpAll(() async => initializeDateFormatting());
    setUp(() => provider = LocaleProvider());

    test('base language resolves to itself', () {
      provider.setLocale('es');
      expect(provider.locale, const Locale('es'));
    });

    test('hyphenated regional variant resolves to the base language', () {
      provider.setLocale('es-MX');
      expect(provider.locale, const Locale('es'));
    });

    test('underscore form also resolves to the base language', () {
      provider.setLocale('en_US');
      expect(provider.locale, const Locale('en'));
    });

    test('Simplified Chinese resolves to base zh', () {
      provider.setLocale('zh-CN');
      expect(provider.locale, const Locale('zh'));
    });

    test('Traditional Chinese maps to the zh_Hant translation', () {
      const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      provider.setLocale('zh-TW');
      expect(provider.locale, hant);
      provider.setLocale('zh-HK');
      expect(provider.locale, hant);
      provider.setLocale('zh-Hant');
      expect(provider.locale, hant);
    });

    test('null / empty / unknown code clears the locale', () {
      provider.setLocale('es');
      provider.setLocale(null);
      expect(provider.locale, isNull);
      provider.setLocale('es');
      provider.setLocale('');
      expect(provider.locale, isNull);
      provider.setLocale('es');
      provider.setLocale('zzz');
      expect(provider.locale, isNull);
    });
  });
}
