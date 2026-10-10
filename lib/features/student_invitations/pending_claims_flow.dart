import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';

enum ClaimNoticeKind {
  claimed,
  pendingApproval,
  denied,
  notLive,
  alreadyClaimed,
  canvasLinked,
  ticketExpired,
  ticketWrongAccount,
  canvasAlreadyLinked,
  failed,
}

class ClaimNotice {
  final ClaimNoticeKind kind;

  /// The course the outcome is about, when the module named it; the shell
  /// shows that room's name.
  final String? roomId;

  const ClaimNotice(this.kind, {this.roomId});
}

/// The signed-in half of the student side (SPEC §4 Student, amendment
/// 2026-10-10 §1): open the seat invitation the visitor arrived with, and
/// return a ferried Canvas ticket. No student confirmation: the module
/// claims on a verified address, a teacher's grant, or the exact Canvas
/// identity.
///
/// A ferried invitation or ticket is TAKEN (cleared) before it is sent, so
/// it is returned at most once whatever happens next. A Canvas ticket is
/// single-use on the server anyway; a lost invitation is claimed at the
/// next sign-in when the account has the invited address, and the link
/// still works.
///
/// Side effects are injected, so this is unit-tested end to end against a
/// fake module.
class PendingClaimsFlow {
  final StudentInvitationApi api;
  final String accessToken;
  final void Function(ClaimNotice notice) notify;
  final Future<void> Function(Uri url) openUrl;

  /// Reports a failure that is not one of the module's expected refusals.
  /// Callers must never pass ids, tickets or bodies along with it.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const PendingClaimsFlow({
    required this.api,
    required this.accessToken,
    required this.notify,
    required this.openUrl,
    this.onError,
  });

  /// Before the session's first choreo call: send what can claim (a stored
  /// invitation, a learner Canvas ticket), so the claim exists before
  /// choreo's HTTP gate could auto-claim a trial. An instructor ticket opens
  /// admin-dash, so it waits for the shell.
  Future<void> consumeClaims() async {
    if (_hasLearnerTicket) await consumeLtiTicket();
    if (SpaceCodeRepo.pendingInvitation != null) await consumeInvitation();
  }

  /// Whether [consumeClaims] has anything to send.
  static bool get hasPendingClaim =>
      _hasLearnerTicket || SpaceCodeRepo.pendingInvitation != null;

  static bool get _hasLearnerTicket {
    final ticket = SpaceCodeRepo.pendingLtiTicket;
    return ticket != null && !ticket.instructor;
  }

  /// The invitation a class link carried (`?inv=`), if one is waiting.
  Future<void> consumeInvitation() async {
    final pending = SpaceCodeRepo.pendingInvitation;
    if (pending == null) return;
    await SpaceCodeRepo.clearPendingInvitation();
    try {
      final opened = await api.open(
        accessToken: accessToken,
        invitationId: pending.invitationId,
      );
      notify(
        ClaimNotice(switch (opened.outcome) {
          OpenOutcome.claimed => ClaimNoticeKind.claimed,
          OpenOutcome.pending => ClaimNoticeKind.pendingApproval,
          OpenOutcome.denied => ClaimNoticeKind.denied,
        }, roomId: opened.roomId),
      );
    } on StudentInvitationApiException catch (e, s) {
      if (e.statusCode == 404) {
        notify(const ClaimNotice(ClaimNoticeKind.notLive));
      } else if (e.errcode ==
          StudentInvitationApiException.alreadyClaimedInCourse) {
        notify(const ClaimNotice(ClaimNoticeKind.alreadyClaimed));
      } else {
        onError?.call(e, s);
        notify(const ClaimNotice(ClaimNoticeKind.failed));
      }
    } catch (e, s) {
      onError?.call(e, s);
      notify(const ClaimNotice(ClaimNoticeKind.failed));
    }
  }

  /// The Canvas ticket ferried from `/lti/link` across sign-in (C5 L1).
  Future<void> consumeLtiTicket() async {
    final pending = SpaceCodeRepo.pendingLtiTicket;
    if (pending == null) return;
    await SpaceCodeRepo.clearPendingLtiTicket();
    try {
      final outcome = await api.ltiLink(
        accessToken: accessToken,
        ticket: pending.ticket,
      );
      if (!pending.instructor) {
        notify(const ClaimNotice(ClaimNoticeKind.canvasLinked));
        return;
      }
      final url = outcome.connectUrl;
      if (url == null || !(url.isScheme('https') || url.isScheme('http'))) {
        throw const StudentInvitationApiException(200, 'M_BAD_JSON');
      }
      await openUrl(url);
    } catch (e, s) {
      reportLinkFailure(e, s);
    }
  }

  /// The notice for a failed L1 call, reporting only the unexpected ones.
  void reportLinkFailure(Object e, StackTrace s) {
    final kind = linkFailureKind(e);
    if (kind == ClaimNoticeKind.failed) onError?.call(e, s);
    notify(ClaimNotice(kind));
  }

  static ClaimNoticeKind linkFailureKind(Object e) => switch (e) {
    StudentInvitationApiException(statusCode: 410) =>
      ClaimNoticeKind.ticketExpired,
    StudentInvitationApiException(
      errcode: StudentInvitationApiException.ticketWrongAccount,
    ) =>
      ClaimNoticeKind.ticketWrongAccount,
    StudentInvitationApiException(
      errcode: StudentInvitationApiException.ltiAlreadyLinked,
    ) =>
      ClaimNoticeKind.canvasAlreadyLinked,
    _ => ClaimNoticeKind.failed,
  };
}
