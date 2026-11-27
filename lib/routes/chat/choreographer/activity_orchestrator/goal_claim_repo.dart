import 'package:async/async.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A learner's claim, made as they end an activity, that they finished the
/// goals the orchestrator did not mark (pangeachat/client#9881).
///
/// The claim is a record for the team and changes nothing in the activity:
/// no diamond fills and no XP is given, so it cannot be used to earn anything.
/// Distinct from [GoalReportRepo], the staging-only report on one star.
class GoalClaimRepo {
  /// [roleId] is the key the orchestrator awards under (a discussion's seat
  /// key); [goalIds] are each goal's award slug or row id, whichever the
  /// header holds — the server matches either.
  static Future<Result<void>> submit({
    required String roomId,
    required String roleId,
    required List<String> goalIds,
  }) async {
    final requests = Requests(
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );
    try {
      await requests.post(
        url: PApiUrls.orchestratorGoalClaim,
        body: {"room_id": roomId, "role_id": roleId, "goal_ids": goalIds},
      );
      return Result.value(null);
    } on PangeaHttpException catch (e, s) {
      // silent-ok: a 404 means the orchestrator never ran in this room, so
      // there is no conversation to vouch for and nothing the learner could
      // act on (a claim made before sending anything). Recorded as a
      // breadcrumb, not an error.
      if (e.statusCode == 404) {
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: "Goal claim had no orchestrator turn to attach to",
            data: {"roomId": roomId},
          ),
        );
        return Result.value(null);
      }
      return _reportFailure(e, s, roomId, roleId, goalIds);
    } catch (e, s) {
      return _reportFailure(e, s, roomId, roleId, goalIds);
    }
  }

  static Result<void> _reportFailure(
    Object e,
    StackTrace s,
    String roomId,
    String roleId,
    List<String> goalIds,
  ) {
    // The repo reports once; the caller only decides what to show.
    ErrorHandler.logError(
      e: e,
      s: s,
      data: {
        "roomId": roomId,
        "roleId": roleId,
        "goalIds": goalIds,
        "status": e is PangeaHttpException ? e.statusCode : null,
      },
    );
    return Result.error(e, s);
  }
}
