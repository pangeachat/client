import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/persistent_repo_cache.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';
import 'package:fluffychat/pangea/morphs/default_grammar_constructs_response.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_response.dart';

/// #9541 — grammar labels refresh daily, but the last ones fetched are kept
/// for when a fetch cannot happen. A cache that keeps expired entries still
/// reports them as stale to the daily refresh, and hands them out only
/// through [PersistentRepoCache.getAnyAge].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('keep_expired_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (methodCall) async => tempDir.path,
      );

  const key = 'es-en';
  const fromJson = GrammarConstructsResponse.fromJson;
  final labels = GrammarConstructsResponse.fromJson(
    defaultGrammarConstructsResponse,
  );

  Future<PersistentRepoCache<GrammarConstructsResponse>> cacheWithEntry(
    String box, {
    required bool keepExpired,
    required Duration age,
  }) async {
    await GetStorage.init(box);
    final cache = PersistentRepoCache<GrammarConstructsResponse>(
      box,
      keepExpired: keepExpired,
    );
    await cache.set(
      key,
      RepoCacheItem(timestamp: DateTime.now().subtract(age), response: labels),
    );
    return cache;
  }

  test('an expired entry is kept, but only getAnyAge returns it', () async {
    final cache = await cacheWithEntry(
      'keep_expired',
      keepExpired: true,
      age: const Duration(days: 40),
    );

    expect(cache.get(key, const Duration(days: 1), fromJson), isNull);
    // Reading it as stale did not delete it.
    expect(cache.getAnyAge(key, fromJson)?.features, isNotEmpty);
  });

  test('by default an expired entry is deleted when read', () async {
    final cache = await cacheWithEntry(
      'drop_expired',
      keepExpired: false,
      age: const Duration(days: 2),
    );

    expect(cache.get(key, const Duration(days: 1), fromJson), isNull);
    expect(cache.getAnyAge(key, fromJson), isNull);
  });

  test('a fresh entry reads the same either way', () async {
    final cache = await cacheWithEntry(
      'fresh_entry',
      keepExpired: true,
      age: Duration.zero,
    );

    expect(cache.get(key, const Duration(days: 1), fromJson), isNotNull);
    expect(cache.getAnyAge(key, fromJson), isNotNull);
  });
}
