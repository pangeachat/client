import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/languages/language_repo.dart';

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

  List<LanguageModel> get baseOptions => _langList.toList();

  List<LanguageModel> get unlocalizedTargetOptions => _langList
      .where(
        (element) =>
            element.l2 &&
            (element.langCode == element.langCodeShort ||
                !element.displayName.contains("(")),
      )
      .toList();

  static Future<void> initialize({forceRefresh = false}) async {
    _langList = await _getCachedLanguages();
    final isOutdated = await _shouldFetch;
    final shouldFetch = forceRefresh ||
        isOutdated ||
        _langList.isEmpty ||
        _langList.every((lang) => !lang.l2);

    if (shouldFetch) {
      final result = await LanguageRepo.get();
      _langList = result.isValue
          ? result.asValue!.value
          : LanguageConstants.languageList
              .map((e) => LanguageModel.fromJson(e))
              .toList();
    }

    await _MyShared.saveJson(PrefKey.languagesKey, {
      PrefKey.languagesKey: _langList.map((e) => e.toJson()).toList(),
    });

    await _MyShared.saveString(
      PrefKey.lastFetched,
      DateTime.now().toIso8601String(),
    );

    _langList.removeWhere(
      (element) => element.langCode == LanguageKeys.unknownLanguage,
    );
    _langList = _langList.toSet().toList();
    _langList.sort((a, b) => a.displayName.compareTo(b.displayName));
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

    final DateTime targetDate = DateTime(2026, 1, 9);
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
      _langList.firstWhereOrNull(
        (element) => element.langCode == langCode,
      );
}

class _MyShared {
  static saveString(String key, String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(key, value);
  }

  static Future<String?>? readString(String key) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? source = prefs.getString(key);
    return source;
  }

  static saveJson(String key, Map value) async {
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
