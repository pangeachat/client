import 'package:fluffychat/pangea/common/utils/base_response.dart';

class RepoCacheItem<TResponse extends BaseResponse> {
  final DateTime timestamp;
  final TResponse response;

  const RepoCacheItem({required this.timestamp, required this.response});

  bool isExpired(Duration cacheDuration) =>
      timestamp.isBefore(DateTime.now().subtract(cacheDuration));

  Map<String, dynamic> toJson() => {
    "timestamp": timestamp.millisecondsSinceEpoch,
    "response": response.toJson(),
  };

  factory RepoCacheItem.fromJson(
    Map<String, dynamic> json, {
    required TResponse Function(Map<String, dynamic>) responseFromJson,
  }) {
    return RepoCacheItem(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json["timestamp"]),
      response: responseFromJson(json["response"]),
    );
  }
}

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
