import 'package:fluffychat/features/activity_sessions/activity_summary_analytics_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_response_model.dart';

/// One `pangea.activity_summary` summary slot: the bot's `canonical` slot, or a
/// per-L1 / `default` slot an older client wrote.
class ActivitySummaryModel {
  final ActivitySummaryResponseModel? summary;
  final DateTime? requestedAt;
  final DateTime? errorAt;

  /// Only on slots older clients wrote. The bot's slot carries none; the
  /// room's analytics live in their own slot.
  final ActivitySummaryAnalyticsModel? analytics;

  /// The language [summary] is written in. Set by the bot only.
  final String? langCode;

  /// Server timestamp (ms) of the loading marker that started the bot's call
  /// behind this summary or error. A learner request no newer than this has
  /// been handled.
  final int? callStartedTs;

  ActivitySummaryModel({
    this.summary,
    this.requestedAt,
    this.errorAt,
    this.analytics,
    this.langCode,
    this.callStartedTs,
  });

  Map<String, dynamic> toJson() {
    return {
      "summary": summary?.toJson(),
      "requested_at": requestedAt?.toIso8601String(),
      "error_at": errorAt?.toIso8601String(),
      "analytics": analytics?.toJson(),
      "lang_code": langCode,
      "call_started_ts": callStartedTs,
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
      langCode: json['lang_code'] as String?,
      callStartedTs: json['call_started_ts'] as int?,
    );
  }

  /// How long a pending request may run before the UI treats it as failed.
  /// Generation regularly takes 10-15s on the happy path and up to ~45s when
  /// the choreographer retries a rejected LLM output (max_tries=3), so a 30s
  /// cutoff showed "failed" for requests that were still succeeding (#7660).
  /// The bot rewrites its loading marker before its one retry, so each marker
  /// covers one attempt.
  static const Duration requestTimeout = Duration(seconds: 120);

  /// When the loading marker stops counting as loading.
  DateTime? get loadingDeadline => errorAt == null && requestedAt != null
      ? requestedAt!.add(requestTimeout)
      : null;

  bool get _hasTimeout =>
      loadingDeadline != null && loadingDeadline!.isBefore(DateTime.now());

  bool get hasError => errorAt != null || _hasTimeout;

  /// A call is running. The bot keeps the previous summary in the slot while
  /// it regenerates, so [summary] can be set while loading.
  bool get isLoading => requestedAt != null && !hasError;
}
