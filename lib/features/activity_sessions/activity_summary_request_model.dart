import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

/// A viewer's request to have one of the bot's cards translated into their
/// L1. The bot makes the cards itself; the client only ever asks for a
/// translation (org doc activity-summary.instructions.md, "Language and
/// translation").
class ActivitySummaryRequestModel {
  final ActivityPlanModel activity;

  /// Choreo's id for the stored row behind the card, from its slot. Each card
  /// has its own row. The client cannot rebuild the bot's request, so it
  /// names the row to translate instead.
  final String sourceRequestHash;

  /// The language to translate into.
  final String viewerL1;
  final bool? mock;

  ActivitySummaryRequestModel({
    required this.activity,
    required this.sourceRequestHash,
    required this.viewerL1,
    this.mock,
  });

  Map<String, dynamic> toJson() {
    return {
      'activity': activity.toJson(),
      'source_request_hash': sourceRequestHash,
      'viewer_l1': viewerL1,
      if (mock != null) ModelKey.mock: mock,
    };
  }
}
