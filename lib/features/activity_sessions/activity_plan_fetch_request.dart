import 'package:fluffychat/pangea/common/utils/base_request.dart';

/// Request for a single localized activity plan from the choreographer
/// (`GET /choreo/v2/activity/{activity_id}?l1=`).
///
/// Keyed by `(activity_id, l1)`: the plan body is localized per viewer L1, so
/// two L1-different viewers of the same activity must not collide on cache.
/// `version` is not sent — the choreo `version` query param is an int Payload
/// version while the pinned `version_id` is a timestamp; version-pinned reads
/// are a choreo follow-up, so this reads the latest. See
/// activities.instructions.md.
class ActivityPlanFetchRequest extends BaseRequest {
  final String activityId;
  final String l1;

  ActivityPlanFetchRequest({required this.activityId, required this.l1});

  @override
  String get storageKey => '${activityId}_$l1';

  @override
  Map<String, dynamic> toJson() => {'activity_id': activityId, 'l1': l1};
}
