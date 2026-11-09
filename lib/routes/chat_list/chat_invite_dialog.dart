import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/features/join_codes/knocked_rooms_extension.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/room_summaries/room_summary_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/named_timeout.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/invite_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

enum InviteAction { accept, decline, block }

/// The accept / decline / block prompt for an invite to a chat, shared by the
/// chat list, a course's chat list and a tapped notification. A course invite
/// has its own prompt, [RoomInviteDialog].
class ChatInviteDialog {
  /// How long the prompt waits to learn whether a session is over before it
  /// asks as usual.
  static const _sessionReadBound = Duration(seconds: 10);

  /// The invites whose session is being read. No dialog is up yet to catch a
  /// second tap, which would stack a second prompt.
  static final Set<String> _reading = {};

  /// Resolves the invite to [room] and returns whether the user is now in it,
  /// so the caller can open it. An invite the user knocked for is joined
  /// without asking (joining-courses.instructions.md, KnockTracker).
  static Future<bool> show(BuildContext context, Room room) async {
    if (room.hasKnocked) return join(context, room);

    if (!_reading.add(room.id)) return false;
    final String? closedNotice;
    try {
      closedNotice = await _closedSessionNotice(context, room);
    } finally {
      _reading.remove(room.id);
    }
    if (!context.mounted) return false;

    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final inviteEvent = room.getState(
      EventTypes.RoomMember,
      room.client.userID!,
    );
    final action = await showInviteDialog<InviteAction>(
      context,
      title: room.getLocalizedDisplayname(matrixLocals),
      message:
          closedNotice ??
          (inviteEvent == null
              ? l10n.inviteForMe
              : inviteEvent.content.tryGet<String>('reason') ??
                    l10n.youInvitedBy(
                      room
                          .unsafeGetUserFromMemoryOrFallback(
                            inviteEvent.senderId,
                          )
                          .calcDisplayname(i18n: matrixLocals),
                    )),
      actions: closedNotice != null
          ? [
              InviteDialogAction(
                label: l10n.dismiss,
                value: InviteAction.decline,
              ),
              // Going in stays possible, for someone invited on purpose to
              // see the session.
              InviteDialogAction(
                label: l10n.openChat,
                value: InviteAction.accept,
                quiet: true,
              ),
            ]
          : [
              InviteDialogAction(
                label: l10n.accept,
                value: InviteAction.accept,
              ),
              InviteDialogAction(
                label: l10n.decline,
                value: InviteAction.decline,
                destructive: true,
              ),
              InviteDialogAction(
                label: l10n.block,
                value: InviteAction.block,
                destructive: true,
              ),
            ],
    );
    if (!context.mounted) return false;

    switch (action) {
      case null:
        return false;
      case InviteAction.accept:
        return join(context, room);
      case InviteAction.decline:
        await showFutureLoadingDialog(context: context, future: room.leave);
        return false;
      case InviteAction.block:
        // Read the URI from the router: a notification tap prompts from the
        // root navigator's context, which has no GoRouterState above it.
        final router = GoRouter.of(context);
        final userId = inviteEvent?.senderId;
        router.go(
          WorkspaceNav.openSettings(
            router.routeInformationProvider.value.uri,
            page: userId == null
                ? 'security/ignorelist'
                : 'security/ignorelist/$userId',
          ),
        );
        return false;
    }
  }

  /// What to say instead of asking when [room] is a session the learner can
  /// no longer play (joining-courses.instructions.md, "An invite to a session
  /// that is over"), or null to ask as usual: for any other invite, and when
  /// the session can't be read, because the invite still works.
  static Future<String?> _closedSessionNotice(
    BuildContext context,
    Room room,
  ) async {
    if (!room.isActivitySession) return null;
    final l10n = L10n.of(context);
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        try {
          final summary = await _readSession(
            room,
          ).timeoutNamed(_sessionReadBound, 'room_preview: activity invite');
          if (summary == null) {
            throw Exception('room_preview returned no invited session');
          }
          if (summary.isFinished) return l10n.sessionFinished;
          return summary.isStarted ? l10n.sessionFull : null;
        } catch (e, s) {
          ErrorHandler.logError(e: e, s: s, data: {'roomId': room.id});
          return null;
        }
      },
    );
    return result.result;
  }

  /// The session as it is now. An invite's local state is a snapshot from
  /// when it was sent, with no roles, so only the preview can say. Counting
  /// seats also needs the plan, which a preview only references.
  static Future<RoomSummaryResponse?> _readSession(Room room) async {
    final summaries = await room.client.loadRoomSummaries([
      room.id,
    ], l1Code: null);
    final summary = summaries[room.id];
    final activityId = summary?.activityId;
    if (activityId != null && summary?.resolvedActivityPlan == null) {
      await ActivityPlanRepo.instance.getPlan(activityId);
    }
    return summary;
  }

  /// Accepts the invite to [room] and returns whether the user is now in it.
  static Future<bool> join(BuildContext context, Room room) async {
    final knocked = room.hasKnocked;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final waitForRoom = room.client.waitForRoomInSync(room.id, join: true);
        if (knocked) {
          // joinKnockedRoom reports its own failure and returns null; there is
          // then no join for the sync to bring back.
          if (await room.joinKnockedRoom() == null) return false;
        } else {
          await room.join();
        }
        await waitForRoom;
        return true;
      },
      exceptionContext: ExceptionContext.joinRoom,
    );
    return result.result == true;
  }
}
