import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The text a [ClaimNotice] shows. [courseName] is the course's name when
/// the app knows the room.
String claimNoticeText(L10n l10n, ClaimNotice notice, {String? courseName}) {
  final course = courseName ?? l10n.seatInviteYourCourse;
  return switch (notice.kind) {
    ClaimNoticeKind.claimed => l10n.seatInviteClaimed(course),
    ClaimNoticeKind.pendingApproval => l10n.seatInvitePendingApproval,
    ClaimNoticeKind.denied => l10n.seatInviteDenied,
    ClaimNoticeKind.notLive => l10n.seatInviteNotLive,
    ClaimNoticeKind.alreadyClaimed => l10n.seatInviteAlreadyClaimed,
    ClaimNoticeKind.failed => l10n.seatInviteFailed,
  };
}

/// The flow for the signed-in [client], with the app's snackbar and error
/// reporting.
PendingClaimsFlow pendingClaimsFlowFor(BuildContext context, Client client) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  return PendingClaimsFlow(
    api: StudentInvitationApi(
      httpClient: client.httpClient,
      homeserver: client.homeserver!,
    ),
    accessToken: client.accessToken!,
    notify: (notice) {
      final roomId = notice.roomId;
      final room = roomId == null ? null : client.getRoomById(roomId);
      messenger.showSnackBarAnnounced(
        SnackBar(
          content: Text(
            claimNoticeText(
              l10n,
              notice,
              courseName: room?.getLocalizedDisplayname(),
            ),
          ),
        ),
      );
    },
    // Ids and bodies stay out: the error carries status + errcode.
    onError: _logError,
  );
}

void _logError(Object e, StackTrace s) => ErrorHandler.logError(
  e: e,
  s: s,
  data: const {'feature': 'student_invitations'},
);

/// Headless shell resident (like DmInviteFerryConsumer) for the student side
/// after sign-in: opens a stored seat invitation and shows what happened.
/// Mounted by the workspace shell, so it runs exactly when signed in with the
/// map up. Waits while a coded join is in progress on screen, and tries
/// again on every workspace navigation. Renders nothing.
///
/// No choreo call waits for it: the module already claims an invitation
/// whose address the account has verified when the account signs in, and
/// choreo activates a claimed seat before it considers a trial.
class PendingClaimsConsumer extends StatefulWidget {
  final Uri uri;
  const PendingClaimsConsumer({super.key, required this.uri});

  @override
  State<PendingClaimsConsumer> createState() => _PendingClaimsConsumerState();
}

class _PendingClaimsConsumerState extends State<PendingClaimsConsumer> {
  static bool _running = false;

  @override
  void initState() {
    super.initState();
    _tryConsume();
  }

  @override
  void didUpdateWidget(covariant PendingClaimsConsumer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _tryConsume();
  }

  void _tryConsume() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
  }

  Future<void> _consume() async {
    if (!mounted || _running || !PendingClaimsFlow.hasPendingClaim) return;
    // The auto-submitting class-code join is on screen: let it land first.
    if (joinCodeFor(widget.uri) != null) return;
    final client = Matrix.of(context).client;
    if (!client.isLogged() ||
        client.homeserver == null ||
        client.accessToken == null) {
      return;
    }
    _running = true;
    try {
      await pendingClaimsFlowFor(context, client).consumeInvitation();
    } catch (e, s) {
      _logError(e, s);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
