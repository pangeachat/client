import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';

/// Loads [codes] into the language store, so onboarding can resolve a
/// course's and the device's language without fetching the list.
Future<void> seedLanguageStore([
  List<String> codes = const ['en', 'de', 'es', 'fr'],
]) async {
  SharedPreferences.setMockInitialValues({
    PrefKey.lastFetched: DateTime.now().toIso8601String(),
    PrefKey.languagesKey: jsonEncode({
      PrefKey.languagesKey: [
        for (final code in codes)
          {'language_code': code, 'language_name': code, 'l2_support': 'full'},
      ],
    }),
  });
  await PLanguageStore.initialize();
}
