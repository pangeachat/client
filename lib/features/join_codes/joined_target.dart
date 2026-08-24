import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_room_types.dart';

/// Where a code join lands (joining-courses.instructions.md): a course plan
/// page ([course] — the joined space, or a coded chat's joined parent
/// course), the activity page with a session bound ([activitySession]), or
/// the joined room itself ([room] — a standalone coded chat, and the
/// safe fallback when the room can't be classified).
class JoinedTarget {
  final String roomId;
  final bool isSpace;
  final String? activityId;

  const JoinedTarget.course(this.roomId) : isSpace = true, activityId = null;

  const JoinedTarget.room(this.roomId) : isSpace = false, activityId = null;

  const JoinedTarget.activitySession(this.roomId, String this.activityId)
    : isSpace = false;

  /// The unsynced twin of [JoinedTargetRoomExtension.joinedTarget], over raw
  /// state events: a space opens as a course; an activity session lands on
  /// the activity page; a coded chat under a joined course (per
  /// [isJoinedSpace], which reads LOCAL rooms — the joiner's own courses have
  /// been in their store since before this fresh page load) lands on that
  /// course; anything else opens as a room. Pure — unit-tested
  /// (joined_target_test.dart).
  factory JoinedTarget.fromRoomState(
    String roomId,
    List<MatrixEvent> state,
    bool Function(String roomId) isJoinedSpace,
  ) {
    final roomType = state
        .firstWhereOrNull((e) => e.type == EventTypes.RoomCreate)
        ?.content
        .tryGet<String>('type');
    if (roomType == RoomCreationTypes.mSpace) {
      return JoinedTarget.course(roomId);
    }

    final activityId = _activityIdFromState(roomType, state);
    if (activityId != null) {
      return JoinedTarget.activitySession(roomId, activityId);
    }

    final parentCourseId = state
        .where(
          (e) =>
              e.type == EventTypes.SpaceParent &&
              e.content.tryGetList<String>('via')?.isNotEmpty == true,
        )
        .map((e) => e.stateKey)
        .whereType<String>()
        .firstWhereOrNull(isJoinedSpace);
    if (parentCourseId != null) {
      return JoinedTarget.course(parentCourseId);
    }
    return JoinedTarget.room(roomId);
  }

  /// [ActivityRoomExtension.isActivitySession] + [ActivityRoomExtension.activityId]
  /// without a local [Room]: the v3 room-type suffix
  /// (`p.activity.session:<activity_id>`) is authoritative; a legacy room
  /// embeds the full plan in `pangea.activity_plan` state (`bookmark_id`
  /// marks the deprecated model, excluded like the synced path). A v3
  /// reference plan WITHOUT the room type would need CMS hydration to be
  /// recognized; that shape isn't minted (the type is set at session
  /// creation), and an unhydrated plan resolves as a plain room locally too.
  static String? _activityIdFromState(
    String? roomType,
    List<MatrixEvent> state,
  ) {
    final planContent = state
        .firstWhereOrNull((e) => e.type == PangeaEventTypes.activityPlan)
        ?.content;
    ActivityPlanModel? embeddedPlan;
    if (planContent != null &&
        planContent[ActivitySessionConstants.activityPlanRequest] != null) {
      try {
        embeddedPlan = ActivityPlanModel.fromJson(planContent);
      } catch (_) {
        embeddedPlan = null;
      }
    }

    if (roomType?.startsWith(PangeaRoomTypes.activitySession) == true) {
      if (embeddedPlan?.isDeprecatedModel == true) return null;
      return roomType!.split(':').last;
    }
    if (embeddedPlan == null || embeddedPlan.isDeprecatedModel) return null;
    return embeddedPlan.activityId;
  }

  @override
  bool operator ==(Object other) =>
      other is JoinedTarget &&
      other.roomId == roomId &&
      other.isSpace == isSpace &&
      other.activityId == activityId;

  @override
  int get hashCode => Object.hash(roomId, isSpace, activityId);
}

extension JoinedTargetRoomExtension on Room {
  /// Where a code join of this locally-synced room lands.
  ///
  /// An activity-session code is an invite INTO that session: land on the
  /// activity page with the session room bound (join/resume), never the
  /// parent course. Routing a shared-course invitee to the course hid the
  /// activity entirely, and a no-shared-course invitee dragged an unjoinable
  /// course panel open beside it (#8047).
  ///
  /// A code can attach to a CHAT within a course (announcements,
  /// introductions). A join still lands on the course plan page, not inside
  /// that chat: resolve to the room's joined parent course when one exists.
  /// Only without any joined parent (a standalone coded chat) does the join
  /// open the room itself.
  JoinedTarget get joinedTarget {
    if (isSpace) return JoinedTarget.course(id);
    final sessionActivityId = activityId;
    if (isActivitySession && sessionActivityId != null) {
      return JoinedTarget.activitySession(id, sessionActivityId);
    }
    final parentCourse = spaceParents
        .map((p) => p.roomId == null ? null : client.getRoomById(p.roomId!))
        .whereType<Room>()
        .firstWhereOrNull(
          (parent) => parent.isSpace && parent.membership == Membership.join,
        );
    if (parentCourse != null) return JoinedTarget.course(parentCourse.id);
    return JoinedTarget.room(id);
  }
}

extension JoinedTargetClientExtension on Client {
  /// Resolve the landing for a joined room sync has not yet surfaced, from
  /// the room's state over HTTP — the join succeeded, so the state endpoints
  /// work even mid-initial-sync.
  Future<JoinedTarget> resolveUnsyncedJoinedTarget(String roomId) async {
    try {
      final state = await getRoomState(roomId);
      return JoinedTarget.fromRoomState(roomId, state, (id) {
        final parent = getRoomById(id);
        return parent != null &&
            parent.isSpace &&
            parent.membership == Membership.join;
      });
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"roomId": roomId});
      // Land on the room AS A ROOM: a wrong room-open shows a chat view the
      // user can leave, while a wrong course-open spins forever (#8047).
      return JoinedTarget.room(roomId);
    }
  }
}
