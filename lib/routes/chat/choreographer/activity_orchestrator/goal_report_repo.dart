import 'package:async/async.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Which way a reported goal star is wrong.
enum GoalReportDirection {
  /// A filled star the reporter says was not earned.
  overAward,

  /// An empty star the reporter says they earned. Carries the message they
  /// nominate as evidence.
  underAward;

  String get wireValue => switch (this) {
    GoalReportDirection.overAward => "over_award",
    GoalReportDirection.underAward => "under_award",
  };
}

/// A report that a goal star was wrongly given or wrongly withheld (staging
/// only, for the team).
///
/// Nothing is regenerated and no star changes: the complaint becomes a record
/// of its own, so the reported turn keeps exactly what production served. The
/// star the reporter tapped stays as it is, and the goal header does not
/// re-render on a successful report.
///
/// Distinct from [OrchestratorFeedbackRepo], which flags a *turn* and
/// regenerates it.
class GoalReportRepo {
  /// The server's own cap on the comment. Enforced in the field as well so an
  /// over-long comment is never typed into a 422.
  static const int maxCommentLength = 2000;

  /// [goalId] is the goal's award slug or its row id — the server matches
  /// either, so whichever the star header holds is what gets sent.
  ///
  /// [evidenceEventId] and [evidenceOriginTs] are required for
  /// [GoalReportDirection.underAward] and must be absent otherwise: the turn
  /// for an over-award is found from the award itself. The timestamp travels
  /// with the event id because the nominated message often triggered no
  /// orchestrator call of its own (a bot message, the opener, a call that
  /// failed), and the server resolves to the nearest turn after it.
  static Future<Result<void>> submit({
    required String roomId,
    required String roleId,
    required String goalId,
    required GoalReportDirection direction,
    required String comment,
    String? evidenceEventId,
    int? evidenceOriginTs,
  }) async {
    final requests = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    final isUnderAward = direction == GoalReportDirection.underAward;
    try {
      await requests.post(
        url: PApiUrls.orchestratorGoalReport,
        body: {
          "room_id": roomId,
          "role_id": roleId,
          "goal_id": goalId,
          "direction": direction.wireValue,
          // Trimmed here as well as server-side: the server rejects a blank
          // comment with a 422 and a reporter should never reach that.
          "comment": comment.trim(),
          if (isUnderAward) "evidence_event_id": evidenceEventId,
          if (isUnderAward) "evidence_origin_ts": evidenceOriginTs,
        },
      );
      return Result.value(null);
    } catch (e, s) {
      // The repo reports once; the caller only decides what to show.
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          "roomId": roomId,
          "roleId": roleId,
          "goalId": goalId,
          "direction": direction.wireValue,
          "evidenceEventId": evidenceEventId,
          "status": e is PangeaHttpException ? e.statusCode : null,
          // The comment is deliberately absent: it is reporter prose about
          // learner content and does not belong in Sentry.
        },
      );
      return Result.error(e, s);
    }
  }
}
