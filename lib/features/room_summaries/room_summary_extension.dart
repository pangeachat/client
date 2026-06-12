import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/api.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_summary_model.dart';
import 'package:fluffychat/features/bot/utils/bot_name.dart';
import 'package:fluffychat/features/course_plans/courses/course_plan_event.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension RoomSummaryExtension on Api {
  Future<RoomSummariesResponse> getRoomSummaries(List<String> roomIds) async {
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
    return RoomSummariesResponse.fromJson(json);
  }
}

extension RoomSummaryRequest on Client {
  Future<Map<String, RoomSummaryResponse>> loadRoomSummaries(
    List<String> roomIds,
  ) async {
    final batches = _batchRoomIdRequests(roomIds);
    final responses = await Future.wait(
      batches.map((b) => getRoomSummaries(b)),
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

  factory RoomSummariesResponse.fromJson(Map<String, dynamic> json) {
    final summaries = <String, RoomSummaryResponse>{};
    json["rooms"].forEach((key, value) {
      if (value.isNotEmpty) {
        summaries[key] = RoomSummaryResponse.fromJson(value);
      }
    });
    return RoomSummariesResponse(summaries: summaries);
  }
}

class RoomSummaryResponse {
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

  bool get isStarted {
    if (isFinished) return true;
    final activityPlan = this.activityPlan;
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

  bool isActivityInstance(String activityId) =>
      activityPlan?.activityId == activityId;

  bool get isActivityOpenToJoin {
    if (activityPlan?.activityId == null) return false;

    // if room has no members, attempting to join will cause error, so we consider it not open
    if (membershipSummary.isEmpty) return false;
    return !isStarted;
  }

  bool isCompleteByUserId(String userID) =>
      activityRoles?.roles.values.any(
        (v) => v.userId == userID && v.isArchived,
      ) ==
      true;

  factory RoomSummaryResponse.fromJson(Map<String, dynamic> json) {
    final planEntry =
        json[PangeaEventTypes.activityPlan]?["default"]?["content"];
    ActivityPlanModel? plan;
    if (planEntry != null && planEntry is Map<String, dynamic>) {
      plan = ActivityPlanModel.fromJson(planEntry);
    }

    final rolesEntry =
        json[PangeaEventTypes.activityRole]?["default"]?["content"];
    ActivityRolesModel? roles;
    if (rolesEntry != null && rolesEntry is Map<String, dynamic>) {
      roles = ActivityRolesModel.fromJson(rolesEntry);
    }

    final summaryEntry =
        json[PangeaEventTypes.activitySummary]?["default"]?["content"];
    ActivitySummaryModel? summary;
    if (summaryEntry != null && summaryEntry is Map<String, dynamic>) {
      summary = ActivitySummaryModel.fromJson(summaryEntry);
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
