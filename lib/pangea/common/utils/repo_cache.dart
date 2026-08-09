import 'package:fluffychat/pangea/common/utils/base_response.dart';
import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';

abstract class RepoCache<TResponse extends BaseResponse> {
  Future<void> init();

  TResponse? get(
    String key,
    Duration cacheDuration,
    TResponse Function(Map<String, dynamic>) responseFromJson,
  );

  Future<void> set(String key, RepoCacheItem<TResponse> item);

  Future<void> remove(String key);

  Future<void> clear();
}
