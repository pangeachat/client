import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_constants.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/language_repo.dart';

class PrefKey {
  static const lastFetched = 'p_lang_lastfetched';
  static const languagesKey = 'p_lang_flag';
}

class PLanguageStore {
  PLanguageStore() {
    initialize();
  }

  static List<LanguageModel> _langList = [];

  List<LanguageModel> get targetOptions =>
      _langList.where((element) => element.l2).toList();

  /// L1 (native language) options. Shows one entry per language plus genuinely
  /// distinct writing systems (Traditional Chinese, Jawi Malay, Shahmukhi
  /// Punjabi). Regional variants that write the same way as their base language
  /// — English (US/UK), Spanish (Mexico), Cantonese (HK), etc. — are dropped:
  /// they don't belong in native-language selection and the app UI is
  /// translated by language + script, not by region.
  List<LanguageModel> get baseOptions {
    final baseScript = <String, String>{};
    for (final lang in _langList) {
      if (lang.langCode == lang.langCodeShort) {
        baseScript[lang.langCodeShort] = _scriptClass(lang.script);
      }
    }

    return _langList.where((lang) {
      if (lang.langCode == lang.langCodeShort) return true; // base language
      final base = baseScript[lang.langCodeShort];
      if (base == null) return true; // no base row — don't drop the language
      return _scriptClass(lang.script) != base; // keep only a distinct script
    }).toList();
  }

  // Collapse near-identical scripts so a variant isn't kept for a trivial
  // difference (generic Han `Hani` vs Simplified `Hans`; Arabic `Arab` vs
  // Nastaliq `Aran`).
  static String _scriptClass(String s) {
    if (s == 'Hans' || s == 'Hani') return 'Hans';
    if (s == 'Arab' || s == 'Aran') return 'Arab';
    return s;
  }

  /// Whether text in language [a] reads as text in language [b]: the same base
  /// language in the same script, by the rule [baseOptions] uses. `en` matches
  /// `en-US` and `zh` matches `zh-CN`, but `zh` does not match `zh-TW`.
  static bool sameWrittenLanguage(String a, String b) {
    if (a == b) return true;
    if (a.split('-').first != b.split('-').first) return false;
    return _scriptClass(byLangCode(a)?.script ?? '') ==
        _scriptClass(byLangCode(b)?.script ?? '');
  }

  List<LanguageModel> get unlocalizedTargetOptions {
    final unlocalized = _langList
        .where(
          (element) =>
              element.l2 &&
              (element.langCode == element.langCodeShort ||
                  !element.displayName.contains("(")),
        )
        .toList();
    final normalized = <LanguageModel>[];
    final seenNames = <String>{};
    for (final lang in unlocalized) {
      final name = lang.displayName;
      if (!seenNames.contains(name)) {
        seenNames.add(name);
        normalized.add(lang);
      }
    }
    return normalized;
  }

  /// The fetch in flight, if any. Concurrent callers join it instead of
  /// starting their own, and a second [initialize] does not reload the cache
  /// over the list the fetch is about to deliver.
  static Future<void>? _refreshing;

  /// Loads the cached language list. With no usable cache, as on a first
  /// launch, this waits for the CMS list. Otherwise it returns at once and a
  /// stale cache refreshes in the background, so startup never waits on the
  /// daily refresh (#9238). [forceRefresh] always waits for the fetch.
  static Future<void> initialize({bool forceRefresh = false}) async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    _setList(await _getCachedLanguages());
    final hasUsableCache = _langList.any((lang) => lang.l2);
    if (forceRefresh || !hasUsableCache) {
      return _refresh(keepCacheOnFailure: hasUsableCache);
    }
    if (await _shouldFetch) unawaited(_refresh(keepCacheOnFailure: true));
  }

  /// A failed fetch falls back to [LanguageConstants.languageList] only when
  /// there is no usable cache to keep (language-list.instructions.md).
  static Future<void> _refresh({required bool keepCacheOnFailure}) =>
      _refreshing ??= _fetchAndCache(
        keepCacheOnFailure,
      ).whenComplete(() => _refreshing = null);

  static Future<void> _fetchAndCache(bool keepCacheOnFailure) async {
    final result = await LanguageRepo.get();
    // LanguageRepo has reported the failure; the cached list stays, and the
    // next launch tries again.
    if (result.isError && keepCacheOnFailure) return;

    _setList(
      result.isValue
          ? result.asValue!.value
          : LanguageConstants.languageList
                .map((e) => LanguageModel.fromJson(e))
                .toList(),
    );

    await _MyShared.saveJson(PrefKey.languagesKey, {
      PrefKey.languagesKey: _langList.map((e) => e.toJson()).toList(),
    });

    await _MyShared.saveString(
      PrefKey.lastFetched,
      DateTime.now().toIso8601String(),
    );
  }

  static void _setList(List<LanguageModel> languages) {
    _langList =
        languages
            .where((lang) => lang.langCode != LanguageKeys.unknownLanguage)
            .toSet()
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  static Future<bool> get _shouldFetch async {
    final String? dateString = await _MyShared.readString(PrefKey.lastFetched);
    if (dateString == null) {
      return true;
    }

    final DateTime? lastFetchedDate = DateTime.tryParse(dateString);
    if (lastFetchedDate == null) {
      return true;
    }

    final DateTime targetDate = DateTime(2026, 1, 15);
    if (lastFetchedDate.isBefore(targetDate)) {
      return true;
    }

    final int lastFetched = lastFetchedDate.millisecondsSinceEpoch;
    final int now = DateTime.now().millisecondsSinceEpoch;
    const int fetchIntervalInMilliseconds = 86534601;
    return (now - lastFetched) >= fetchIntervalInMilliseconds;
  }

  static Future<List<LanguageModel>> _getCachedLanguages() async {
    final Map<dynamic, dynamic>? languagesMap = await _MyShared.readJson(
      PrefKey.languagesKey,
    );

    if (languagesMap == null) return [];
    try {
      return (languagesMap[PrefKey.languagesKey] as List)
          .map((e) => LanguageModel.fromJson(e))
          .toList();
    } catch (err) {
      return [];
    }
  }

  static LanguageModel? byLangCode(String langCode) =>
      _langList.firstWhereOrNull((element) => element.langCode == langCode);

  static bool hasDisplayNameVariant(String displayName) => _langList.any(
    (lang) => lang.isLocalized && lang.displayName.contains(displayName),
  );
}

class _MyShared {
  static Future<void> saveString(String key, String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(key, value);
  }

  static Future<String?>? readString(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? source = prefs.getString(key);
    return source;
  }

  static Future<void> saveJson(String key, Map value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(key, json.encode(value));
  }

  static Future<Map?>? readJson(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? source = prefs.getString(key);

      if (source == null) {
        return null;
      }
      final decodedJson = json.decoder.convert(source);
      //var decodedJson = json.decode(source);
      return decodedJson;
    } catch (err) {
      return null;
    }
  }
}
