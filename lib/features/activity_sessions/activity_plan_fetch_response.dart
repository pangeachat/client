import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/quests/repo/activity_v2_mapper.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';

/// Response of `GET /choreo/v2/activity/{id}` — the localized plan body plus
/// fetch metadata (`{ plan, version_id, l1, used_fallback }`).
///
/// Stores the **raw** choreo `plan` body, not the mapped model: the raw body
/// round-trips losslessly through [toJson]/[fromJson] for disk persistence and
/// keeps stable `upload_id`s (CDN urls are resolved at display, never cached).
/// [plan] maps it to an [ActivityPlanModel] on demand (cheap).
class ActivityPlanFetchResponse extends BaseResponse {
  final Map<String, dynamic> rawPlan;
  final String? l1;
  final String? versionId;
  final bool usedFallback;

  ActivityPlanFetchResponse({
    required this.rawPlan,
    this.l1,
    this.versionId,
    this.usedFallback = false,
  });

  /// The plan body mapped into the client model (media `upload_id`s unresolved).
  ActivityPlanModel get plan => activityPlanFromV2({
    'res': {'plan': rawPlan},
    'req': {'user_l1': l1},
    'version_id': versionId,
  });

  factory ActivityPlanFetchResponse.fromJson(Map<String, dynamic> json) {
    final rawPlan = (json['plan'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ActivityPlanFetchResponse(
      rawPlan: rawPlan,
      l1: json['l1'] as String?,
      versionId: json['version_id'] as String?,
      usedFallback: json['used_fallback'] == true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'plan': rawPlan,
    'l1': l1,
    'version_id': versionId,
    'used_fallback': usedFallback,
  };
}
