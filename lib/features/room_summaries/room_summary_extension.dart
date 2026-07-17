import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_session_constants.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension RoomSummaryExtension on Api {
  Future<RoomSummariesResponse> getRoomSummaries(
    List<String> roomIds, {
    required String? l1Code,
  }) async {
    final requestUri = Uri(
      path: '/_synapse/client/unstable/org.pangea/room_preview',
      queryParameters: {'rooms': roomIds.join(",")},
    );
    final request = Request('GET', baseUri!.resolveUri(requestUri));
    request.headers['content-type'] = 'application/json';
    request.headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    final responseString = utf8.decode(responseBody);
    if (response.statusCode != 200) {
      throw Exception(
        'HTTP error response: statusCode=${response.statusCode}, body=$responseString',
      );
    }
    final json = jsonDecode(responseString);
    return RoomSummariesResponse.fromJson(json, l1Code: l1Code);
  }
}

extension RoomSummaryRequest on Client {
  Future<Map<String, RoomSummaryResponse>> loadRoomSummaries(
    List<String> roomIds, {
    required String? l1Code,
  }) async {
    final batches = _batchRoomIdRequests(roomIds);
    final responses = await Future.wait(
      batches.map((b) => getRoomSummaries(b, l1Code: l1Code)),
    );
    return {for (final r in responses) ...r.summaries};
  }

  List<List<String>> _batchRoomIdRequests(List<String> roomIds) {
    const int batchSize = 50;
    return [
      for (var i = 0; i < roomIds.length; i += batchSize)
        roomIds.sublist(i, (i + batchSize).clamp(0, roomIds.length)),
    ];
  }
}

class RoomSummariesResponse {
  Map<String, RoomSummaryResponse> summaries;

  RoomSummariesResponse({required this.summaries});

  factory RoomSummariesResponse.fromJson(
    Map<String, dynamic> json, {
    required String? l1Code,
  }) {
    final summaries = <String, RoomSummaryResponse>{};
    json["rooms"].forEach((key, value) {
      if (value.isNotEmpty) {
        summaries[key] = RoomSummaryResponse.fromJson(value, l1Code: l1Code);
      }
    });
    return RoomSummariesResponse(summaries: summaries);
  }
}

class RoomSummaryResponse {
  /// The session's activity id — read from the `pangea.activity_plan` ref even
  /// when it is a thin `{activity_id, version_id}` reference. So it survives for
  /// v3 rooms, whose plan body is not embedded and leaves [activityPlan] null;
  /// coursemate-session discovery on the world map keys off it.
  final String? activityId;
  final ActivityPlanModel? activityPlan;
  final ActivityRolesModel? activityRoles;
  final ActivitySummaryModel? activitySummary;
  final CoursePlanEvent? coursePlan;

  final JoinRules? joinRule;
  final Map<String, int>? powerLevels;
  final Map<String, String> membershipSummary;
  final String? displayName;
  final String? avatarUrl;

  RoomSummaryResponse({
    required this.membershipSummary,
    this.activityId,
    this.activityPlan,
    this.activityRoles,
    this.activitySummary,
    this.coursePlan,
    this.joinRule,
    this.powerLevels,
    this.displayName,
    this.avatarUrl,
  });

  List<String> get adminUserIDs {
    if (powerLevels == null) return [];
    return powerLevels!.entries
        .where((entry) => entry.value >= 100)
        .map((entry) => entry.key)
        .toList();
  }

  Membership? getMembershipForUserId(String userId) {
    final membershipString = membershipSummary[userId];
    if (membershipString == null) return null;
    return Membership.values.firstWhere(
      (m) => m.name == membershipString,
      orElse: () => Membership.join,
    );
  }

  Map<String, ActivityRoleModel> get joinedUsersWithRoles {
    if (activityRoles == null) return {};
    return Map.fromEntries(
      activityRoles!.roles.entries.where(
        (role) => getMembershipForUserId(role.value.userId) == Membership.join,
      ),
    );
  }

  int get joinedMemberCount => membershipSummary.values
      .where((membership) => membership == Membership.join.name)
      .length;

  /// Resolves a thin activity ref to its hydrated plan. Defaults to the
  /// [ActivityPlanRepo] lookup (kicking off hydration on first read — the same
  /// pattern as `Room.activityPlan`); replaceable in tests, where the repo's
  /// storage/app context doesn't exist.
  @visibleForTesting
  static ActivityPlanModel? Function(String activityId) referencePlanResolver =
      defaultReferencePlanResolver;

  static ActivityPlanModel? defaultReferencePlanResolver(String activityId) {
    ActivityPlanRepo.instance.ensure(activityId);
    return ActivityPlanRepo.instance.cachedPlan(activityId);
  }

  /// The plan for seat math: the embedded plan when present, else the hydrated
  /// reference plan. Null while hydration is pending, in which case seats are
  /// unknown and the joinable gate stays permissive.
  ActivityPlanModel? get resolvedActivityPlan {
    if (activityPlan != null) return activityPlan;
    final id = activityId;
    if (id == null) return null;
    return referencePlanResolver(id);
  }

  bool get isStarted {
    if (isFinished) return true;
    // Resolve thin v3 references so a full session stops reading as joinable
    // once its plan hydrates (#7645); an unresolved plan stays permissive.
    final activityPlan = resolvedActivityPlan;
    if (activityPlan == null) return false;
    return activityPlan.roles.length - joinedUsersWithRoles.length <= 0;
  }

  bool get isFinished {
    final activityRoles = this.activityRoles;
    if (activityRoles == null) return false;
    final roles = activityRoles.roles.values.where(
      (r) => r.userId != BotName.byEnvironment,
    );

    if (roles.isEmpty) return false;
    if (!roles.any((r) => r.isFinished)) return false;

    return roles.every((r) {
      if (r.isFinished) return true;

      // if the user is in the chat (not null && membership is join),
      // then the activity is not finished for them
      final membership = getMembershipForUserId(r.userId);
      return membership == null || membership != Membership.join;
    });
  }

  bool isActivityInstance(String activityId) => this.activityId == activityId;

  bool get isActivityOpenToJoin {
    // v3 sessions carry a thin activity_plan ref, so key off [activityId] (set
    // even when the plan body is not embedded) rather than the parsed plan.
    if (activityId == null) return false;

    // if room has no members, attempting to join will cause error, so we consider it not open
    if (membershipSummary.isEmpty) return false;
    return !isStarted;
  }

  bool isCompleteByUserId(String userID) =>
      activityRoles?.roles.values.any(
        (v) => v.userId == userID && v.isArchived,
      ) ==
      true;

  factory RoomSummaryResponse.fromJson(
    Map<String, dynamic> json, {
    required String? l1Code,
  }) {
    final planEntry =
        json[PangeaEventTypes.activityPlan]?["default"]?["content"];
    ActivityPlanModel? plan;
    // v3 rooms store a thin { activity_id, version_id } reference (no `req`);
    // only an embedded plan can be parsed here. References are resolved lazily
    // by consumers, so the summary's plan stays null. See
    // activities.instructions.md.
    if (planEntry is Map<String, dynamic> &&
        planEntry[ActivitySessionConstants.activityPlanRequest] != null) {
      plan = ActivityPlanModel.fromJson(planEntry);
    }

    final rolesEntry =
        json[PangeaEventTypes.activityRole]?["default"]?["content"];
    ActivityRolesModel? roles;
    if (rolesEntry != null && rolesEntry is Map<String, dynamic>) {
      roles = ActivityRolesModel.fromJson(rolesEntry);
    }

    final summaryEntry = json[PangeaEventTypes.activitySummary];
    final legacySummaryEntry = summaryEntry?["default"]?["content"];
    final currentSummaryEntry = summaryEntry?[l1Code]?["content"];

    ActivitySummaryModel? summary;
    if (legacySummaryEntry != null &&
        legacySummaryEntry is Map<String, dynamic>) {
      summary = ActivitySummaryModel.fromJson(legacySummaryEntry);
    }

    if (summary == null &&
        currentSummaryEntry != null &&
        currentSummaryEntry is Map<String, dynamic>) {
      summary = ActivitySummaryModel.fromJson(currentSummaryEntry);
    }

    final coursePlanEntry =
        json[PangeaEventTypes.coursePlan]?["default"]?["content"];
    CoursePlanEvent? coursePlan;
    if (coursePlanEntry != null && coursePlanEntry is Map<String, dynamic>) {
      coursePlan = CoursePlanEvent.fromJson(coursePlanEntry);
    }

    final powerLevelsEntry =
        json[EventTypes.RoomPowerLevels]?['default']?['content']?['users'];
    Map<String, int>? powerLevels;
    if (powerLevelsEntry != null) {
      powerLevels = Map<String, int>.from(powerLevelsEntry);
    }

    final joinRulesString =
        json[EventTypes.RoomJoinRules]?['default']?['content']?['join_rule'];
    JoinRules? joinRule;
    if (joinRulesString != null && joinRulesString is String) {
      joinRule = JoinRules.values.singleWhereOrNull(
        (element) => element.text == joinRulesString,
      );
    }

    final displayName =
        json[EventTypes.RoomName]?['default']?['content']?['name'] as String?;

    String? avatarUrl =
        json[EventTypes.RoomAvatar]?['default']?['content']?['url'] as String?;
    if (avatarUrl != null && Uri.tryParse(avatarUrl) == null) {
      avatarUrl = null;
    }

    return RoomSummaryResponse(
      activityId: planEntry is Map<String, dynamic>
          ? planEntry[ActivitySessionConstants.activityId] as String?
          : null,
      activityPlan: plan,
      activityRoles: roles,
      activitySummary: summary,
      coursePlan: coursePlan,
      powerLevels: powerLevels,
      joinRule: joinRule,
      membershipSummary: Map<String, String>.from(
        json['membership_summary'] ?? {},
      ),
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityPlan': activityPlan?.toJson(),
      'activityRoles': activityRoles?.toJson(),
      'activitySummary': activitySummary?.toJson(),
      'coursePlan': coursePlan?.toJson(),
      'joinRule': joinRule?.text,
      'powerLevels': powerLevels,
      'membershipSummary': membershipSummary,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
    };
  }
}
