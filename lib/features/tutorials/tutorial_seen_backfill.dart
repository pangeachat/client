import 'dart:async';

import 'package:matrix/matrix_api_lite/utils/logs.dart';

import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/world/world_map_client_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Marks the tutorials a veteran learner should never be offered as already
/// seen — once per signed-in user per session, as soon as the profile and the
/// first room sync can answer whether this account predates the tutorials.
/// Design, including which tutorials stay offerable and the accepted edges:
/// tutorials.instructions.md, "Veterans skip what they have already lived".
///
/// Evaluated once at load, so a learner who finishes their FIRST activity
/// mid-session is not a veteran and keeps their tour. Triggers gate on
/// [isResolved] and its resolution re-asks them, because on a big account the
/// map can render pins (and the welcome could fire) before the sync delivers
/// the rooms that prove the learner a veteran.
class TutorialSeenBackfill {
  TutorialSeenBackfill._();

  /// App-scoped, but the evaluation is keyed to the signed-in user: statics
  /// survive logout/login, and a previous login's completed evaluation must
  /// not answer for a new account (a veteran got greeted exactly that way).
  static final TutorialSeenBackfill instance = TutorialSeenBackfill._();

  /// What a veteran is assumed to have outgrown. NOT here, deliberately:
  /// [TutorialEnum.openSessions], the chat sequence, and
  /// [TutorialEnum.coursePlan] — the per-case surfaces.
  static const List<TutorialEnum> veteranSeenTutorials = [
    TutorialEnum.welcome,
    TutorialEnum.worldMap,
    TutorialEnum.appTour,
    TutorialEnum.activityGoals,
    TutorialEnum.activityRoles,
  ];

  Completer<void>? _resolved;

  /// The user the current evaluation belongs to. A different signed-in user is
  /// a different account history — their evaluation has not happened yet.
  String? _resolvedForUserId;

  String? get _activeUserId =>
      MatrixState.pangeaController.matrixState.client.userID;

  /// Resolved FOR THE SIGNED-IN USER. False both while the evaluation is
  /// running and when the completed one belongs to a previous login.
  bool get isResolved =>
      _resolved?.isCompleted == true && _resolvedForUserId == _activeUserId;

  /// Starts the evaluation for the signed-in user if it hasn't started, and
  /// completes when it has run — whatever it concluded. Hosts await this once
  /// per mount and re-ask their trigger; the trigger then reads the (possibly
  /// backfilled) seen flags. Hosts mount post-login, so a new account always
  /// has a caller to start its own evaluation.
  ///
  /// Never throws: a failed evaluation resolves anyway, because holding every
  /// tutorial hostage to one failed profile write is worse than a veteran
  /// seeing a greeting once.
  Future<void> ensureResolved() {
    final userId = _activeUserId;
    final existing = _resolved;
    if (existing != null && _resolvedForUserId == userId) {
      return existing.future;
    }

    final completer = Completer<void>();
    _resolved = completer;
    _resolvedForUserId = userId;
    _run(userId)
        .catchError((Object e, StackTrace s) {
          Logs().w(
            'TutorialSeenBackfill: evaluation failed — resolving without '
            'marking anything, so tutorials are not held hostage.',
            e,
          );
          ErrorHandler.logError(e: e, s: s, data: {'userId': userId});
        })
        .whenComplete(completer.complete);
    return completer.future;
  }

  Future<void> _run(String? userId) async {
    final matrixState = MatrixState.pangeaController.matrixState;
    await MatrixState.pangeaController.userController.initCompleter.future;

    // Rooms loaded + one sync processed — the point at which
    // hasAnyFinishedActivitySession can answer (the dm_invite pattern).
    final client = matrixState.client;
    await client.roomsLoading;
    if (client.prevBatch == null) await client.onSync.stream.first;

    // The account changed under the awaits (a logout mid-evaluation) — this
    // run's answer belongs to nobody; the next login's hosts start their own.
    if (client.userID != userId) return;

    if (!client.hasAnyFinishedActivitySession) return;
    await TutorialEnum.markSeen(veteranSeenTutorials);
  }
}
