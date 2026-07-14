import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache.dart';

class MemoryRepoCache<TResponse extends BaseResponse>
    implements RepoCache<TResponse> {
  final _cache = <String, RepoCacheItem<TResponse>>{};

  @override
  Future<void> init() async {}

  @override
  TResponse? get(
    String key,
    Duration cacheDuration,
    TResponse Function(Map<String, dynamic>) responseFromJson,
  ) {
    final item = _cache[key];
    if (item == null) return null;

    if (item.isExpired(cacheDuration)) {
      _cache.remove(key);
      return null;
    }

    return item.response;
  }

  @override
  Future<void> set(String key, RepoCacheItem<TResponse> item) async {
    _cache[key] = item;
  }

  @override
  Future<void> remove(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }
}
