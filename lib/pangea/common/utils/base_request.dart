abstract class BaseRequest {
  String get storageKey;
  Map<String, dynamic> toJson();
}
