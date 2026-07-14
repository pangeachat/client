import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PersistentRepoCache<TResponse extends BaseResponse>
    implements RepoCache<TResponse> {
  final GetStorage _storage;
  final String boxName;

  PersistentRepoCache(this.boxName) : _storage = GetStorage(boxName);

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
    final entry = _storage.read(key);
    if (entry == null) return null;

    try {
      final value = RepoCacheItem<TResponse>.fromJson(
        entry,
        responseFromJson: responseFromJson,
      );

      if (value.isExpired(cacheDuration)) {
        _storage.remove(key);
        return null;
      }

      return value.response;
    } catch (_) {
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
