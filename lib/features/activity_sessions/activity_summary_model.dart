import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';

class ActivitySummaryModel {
  final ActivitySummaryResponseModel? summary;
  final DateTime? requestedAt;
  final DateTime? errorAt;
  final ActivitySummaryAnalyticsModel? analytics;

  ActivitySummaryModel({
    this.summary,
    this.requestedAt,
    this.errorAt,
    this.analytics,
  });

  Map<String, dynamic> toJson() {
    return {
      "summary": summary?.toJson(),
      "requested_at": requestedAt?.toIso8601String(),
      "error_at": errorAt?.toIso8601String(),
      "analytics": analytics?.toJson(),
    };
  }

  factory ActivitySummaryModel.fromJson(Map<String, dynamic> json) {
    return ActivitySummaryModel(
      summary: json['summary'] != null
          ? ActivitySummaryResponseModel.fromJson(json['summary'])
          : null,
      requestedAt: json['requested_at'] != null
          ? DateTime.parse(json['requested_at'])
          : null,
      errorAt: json['error_at'] != null
          ? DateTime.parse(json['error_at'])
          : null,
      analytics: json['analytics'] != null
          ? ActivitySummaryAnalyticsModel.fromJson(json['analytics'])
          : null,
    );
  }

  /// How long a pending request may run before the UI treats it as failed.
  /// Generation regularly takes 10-15s on the happy path and up to ~45s when
  /// the choreographer retries a rejected LLM output (max_tries=3), so a 30s
  /// cutoff showed "failed" for requests that were still succeeding (#7660).
  static const Duration requestTimeout = Duration(seconds: 120);

  bool get _hasTimeout =>
      summary == null &&
      requestedAt != null &&
      requestedAt!.isBefore(DateTime.now().subtract(requestTimeout));

  bool get hasError => errorAt != null || _hasTimeout;

  bool get isLoading => summary == null && requestedAt != null && !hasError;
}
