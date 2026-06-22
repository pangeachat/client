import 'package:fluffychat/features/room_summaries/activity_summary_status_enum.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';

typedef _ActivityStatuses =
    Map<ActivitySummaryStatus, Map<String, RoomSummaryResponse>>;

class ActivitySessionsStatusModel {
  late final _ActivityStatuses _sessionStatuses;

  ActivitySessionsStatusModel(Map<String, RoomSummaryResponse> roomSummaries) {
    final _ActivityStatuses statuses = {
      ActivitySummaryStatus.notStarted: {},
      ActivitySummaryStatus.inProgress: {},
      ActivitySummaryStatus.completed: {},
    };

    for (final entry in roomSummaries.entries) {
      final summary = entry.value;
      final roomId = entry.key;

      if (summary.isFinished) {
        statuses[ActivitySummaryStatus.completed]![roomId] = summary;
      } else if (summary.isStarted) {
        statuses[ActivitySummaryStatus.inProgress]![roomId] = summary;
      } else if (summary.membershipSummary.isNotEmpty) {
        statuses[ActivitySummaryStatus.notStarted]![roomId] = summary;
      }
    }

    _sessionStatuses = statuses;
  }

  Map<String, RoomSummaryResponse> getSessionsByStatus(
    ActivitySummaryStatus status,
  ) => _sessionStatuses[status] ?? {};
}
