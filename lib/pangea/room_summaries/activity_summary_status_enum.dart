import 'package:fluffychat/l10n/l10n.dart';

enum ActivitySummaryStatus {
  notStarted,
  inProgress,
  completed;

  String label(L10n l10n, int count) {
    switch (this) {
      case ActivitySummaryStatus.notStarted:
        return l10n.notStartedActivitiesTitle(count);
      case ActivitySummaryStatus.inProgress:
        return l10n.inProgressActivitiesTitle(count);
      case ActivitySummaryStatus.completed:
        return l10n.completedActivitiesTitle(count);
    }
  }

  bool canJoin(bool isCourseAdmin) {
    switch (this) {
      case ActivitySummaryStatus.notStarted:
        return true;
      case ActivitySummaryStatus.inProgress:
      case ActivitySummaryStatus.completed:
        return isCourseAdmin;
    }
  }
}
