import 'package:fluffychat/pangea/common/utils/base_request.dart';

/// Request for a single localized activity plan from the choreographer
/// (`GET /choreo/v2/activity/{activity_id}?l1=&version=`).
///
/// Keyed by `(activity_id, l1, version)`: the plan body is localized per viewer
/// L1, so two L1-different viewers must not collide on cache; and a session
/// pins a `version` (an opaque content-signature), so the pinned read must not
/// collide with the latest read. `version` is sent only when pinning; omit it
/// to read the latest. See activities.instructions.md.
class ActivityPlanFetchRequest extends BaseRequest {
  final String activityId;
  final String l1;
  final String? version;

  ActivityPlanFetchRequest({
    required this.activityId,
    required this.l1,
    this.version,
  });

  @override
  String get storageKey => '${activityId}_${l1}_${version ?? ''}';

  @override
  Map<String, dynamic> toJson() => {
    'activity_id': activityId,
    'l1': l1,
    if (version != null) 'version': version,
  };
}
