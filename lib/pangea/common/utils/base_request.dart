abstract class BaseRequest {
  String get storageKey;
  Map<String, dynamic> toJson();

  /// What a failed request reports to Sentry alongside the error: the body,
  /// unless it carries something a report must never hold (a promo code,
  /// #9281), in which case the request narrows it.
  Map<String, dynamic> toReportData() => toJson();
}
