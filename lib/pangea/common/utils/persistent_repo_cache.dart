import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PersistentRepoCache<TResponse extends BaseResponse>
    implements RepoCache<TResponse> {
  final GetStorage _storage;
  final String boxName;

  /// Keeps an expired entry until a new one replaces it, so [getAnyAge] can
  /// still read it. Only for a box with few keys, because nothing else removes
  /// an entry that is never fetched again.
  final bool keepExpired;

  PersistentRepoCache(this.boxName, {this.keepExpired = false})
    : _storage = GetStorage(boxName);

  @override
  Future<void> init() async {
    await GetStorage.init(boxName);
    MatrixState.pangeaController.registerStorageKey(boxName);
  }

  @override
  TResponse? get(
    String key,
    Duration cacheDuration,
    TResponse Function(Map<String, dynamic>) responseFromJson,
  ) {
    final value = _read(key, responseFromJson);
    if (value == null) return null;

    if (value.isExpired(cacheDuration)) {
      if (!keepExpired) _storage.remove(key);
      return null;
    }

    return value.response;
  }

  /// The saved entry for [key] whatever its age, for a box that
  /// [keepExpired].
  TResponse? getAnyAge(
    String key,
    TResponse Function(Map<String, dynamic>) responseFromJson,
  ) => _read(key, responseFromJson)?.response;

  RepoCacheItem<TResponse>? _read(
    String key,
    TResponse Function(Map<String, dynamic>) responseFromJson,
  ) {
    final entry = _storage.read(key);
    if (entry == null) return null;

    try {
      return RepoCacheItem<TResponse>.fromJson(
        entry,
        responseFromJson: responseFromJson,
      );
    } catch (_) {
      // An entry that no longer parses is a cache miss: drop it, and the
      // caller fetches a fresh one.
      _storage.remove(key);
      return null;
    }
  }

  @override
  Future<void> set(String key, RepoCacheItem<TResponse> item) =>
      _storage.write(key, item.toJson());

  @override
  Future<void> remove(String key) => _storage.remove(key);

  @override
  Future<void> clear() => _storage.erase();
}
