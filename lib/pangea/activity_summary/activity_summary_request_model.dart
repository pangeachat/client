// Add this import for the participant summary model

import 'package:fluffychat/pangea/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_roles_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class ActivitySummaryResultsMessage {
  final String userId;
  final String sent;
  final String? written;
  final List<String> tool;
  final DateTime time;

  ActivitySummaryResultsMessage({
    required this.userId,
    required this.sent,
    this.written,
    required this.tool,
    required this.time,
  });

  factory ActivitySummaryResultsMessage.fromJson(Map<String, dynamic> json) {
    return ActivitySummaryResultsMessage(
      userId: json[ModelKey.userId] as String,
      sent: json['sent'] as String,
      written: json['written'] as String?,
      tool: (json['tool'] as List).map((e) => e as String).toList(),
      time: DateTime.parse(json['time'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ModelKey.userId: userId,
      'sent': sent,
      if (written != null) 'written': written,
      'tool': tool,
      'time': time.toIso8601String(),
    };
  }
}

class ContentFeedbackModel {
  final String feedback;
  final ActivitySummaryResponseModel content;

  ContentFeedbackModel({required this.feedback, required this.content});

  factory ContentFeedbackModel.fromJson(Map<String, dynamic> json) {
    return ContentFeedbackModel(
      feedback: json['feedback'] as String,
      content: ActivitySummaryResponseModel.fromJson(json['content']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'feedback': feedback, 'content': content.toJson()};
  }
}

class ActivitySummaryRequestModel {
  final ActivityPlanModel activity;
  final ActivityRolesModel? roleState;
  final List<ActivitySummaryResultsMessage> activityResults;
  final List<ContentFeedbackModel> contentFeedback;

  /// Calling viewer's L1 from their profile. Drives the language of the
  /// group `summary`; serves as fallback for participants missing from
  /// `participantsL1`. See pangeachat/.github
  /// .github/instructions/activity-summary.instructions.md.
  final String? viewerL1;

  /// Per-participant L1s — one entry per non-bot participant. Each
  /// participant's `feedback` field is written in their own L1 regardless
  /// of the viewer.
  final List<ParticipantL1>? participantsL1;

  ActivitySummaryRequestModel({
    required this.activity,
    required this.activityResults,
    required this.contentFeedback,
    this.roleState,
    this.viewerL1,
    this.participantsL1,
  });

  Map<String, dynamic> toJson() {
    return {
      'activity': activity.toJson(),
      'activity_results': activityResults.map((e) => e.toJson()).toList(),
      'content_feedback': contentFeedback.map((e) => e.toJson()).toList(),
      'role_state': roleState?.toJson() ?? {},
      if (viewerL1 != null) 'viewer_l1': viewerL1,
      if (participantsL1 != null)
        'participants_l1': participantsL1!.map((p) => p.toJson()).toList(),
    };
  }
}

/// Per-participant L1 mapping. Sent in `participants_l1` so the
/// choreographer can localize each participant's `feedback` to that
/// participant's L1, independent of the requesting viewer.
class ParticipantL1 {
  final String userId;
  final String l1;

  ParticipantL1({required this.userId, required this.l1});

  Map<String, dynamic> toJson() => {ModelKey.userId: userId, 'l1': l1};
}
