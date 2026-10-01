import 'package:async/async.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Which part of an orchestrator turn a reviewer objected to.
enum OrchestratorFeedbackPart {
  suggestion,
  goalCompletion;

  String get wireValue => switch (this) {
    OrchestratorFeedbackPart.suggestion => "suggestion",
    OrchestratorFeedbackPart.goalCompletion => "goal_completion",
  };
}

/// Internal reviewer feedback on orchestrator content (staging only).
///
/// Sends only a pointer to the turn. The choreographer already stores the
/// request that call used and regenerates from that copy, so there is no
/// orchestrator request to assemble here — one rebuilt now would carry
/// history as it stands now, and its output would not be comparable to the
/// output being objected to.
///
/// Nothing is written to the room: the learner's displayed suggestion is
/// untouched and no orchestrator output is sent or replaced.
class OrchestratorFeedbackRepo {
  static Future<Result<void>> submit({
    required String roomId,
    required String basedOnEventId,
    required OrchestratorFeedbackPart part,
    required String targetRoleId,
    String? targetGoalId,
    required String comment,
  }) async {
    final requests = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    try {
      await requests.post(
        url: PApiUrls.orchestratorFeedback,
        body: {
          "room_id": roomId,
          "based_on_event_id": basedOnEventId,
          "part": part.wireValue,
          // The award or bucket under review. The server refuses a target the
          // stored turn does not hold, which is how "you flagged the wrong
          // turn" surfaces to the reviewer instead of being recorded.
          "target": {"role_id": targetRoleId, "goal_id": ?targetGoalId},
          // Trimmed here as well as server-side: the server rejects a blank
          // comment with a 422 and a reviewer should never reach that.
          "comment": comment.trim(),
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
          "basedOnEventId": basedOnEventId,
          "part": part.wireValue,
          "targetRoleId": targetRoleId,
          "targetGoalId": targetGoalId,
          "status": e is PangeaHttpException ? e.statusCode : null,
          // The comment is deliberately absent: it is reviewer prose about
          // learner content and does not belong in Sentry.
        },
      );
      return Result.error(e, s);
    }
  }
}
