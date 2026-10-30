import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';

enum ClaimNoticeKind {
  claimed,
  pendingApproval,
  denied,
  notLive,
  alreadyClaimed,
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
/// 2026-10-10 §1): open the seat invitation the visitor arrived with. No
/// student confirmation: the module claims on a verified address or a
/// teacher's grant.
///
/// A ferried invitation is TAKEN (cleared) before it is sent, so it is
/// opened at most once whatever happens next. A lost invitation is claimed
/// at the next sign-in when the account has the invited address, and the
/// link still works.
///
/// Side effects are injected, so this is unit-tested end to end against a
/// fake module.
class PendingClaimsFlow {
  final StudentInvitationApi api;
  final String accessToken;
  final void Function(ClaimNotice notice) notify;

  /// Reports a failure that is not one of the module's expected refusals.
  /// Callers must never pass ids or bodies along with it.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const PendingClaimsFlow({
    required this.api,
    required this.accessToken,
    required this.notify,
    this.onError,
  });

  /// Whether a stored invitation is waiting to be opened.
  static bool get hasPendingClaim => SpaceCodeRepo.pendingInvitation != null;

  /// The invitation a class link carried (`?inv=`), if one is waiting.
  /// Called before the session's first choreo call, so the claim exists
  /// before choreo's HTTP gate could auto-claim a trial.
  Future<void> consumeInvitation() async {
    final pending = SpaceCodeRepo.pendingInvitation;
    if (pending == null) return;
    // Unsettled until the module answers: onboarding must not offer the
    // trial while the open is in flight (TrialInfoProvider).
    await SpaceCodeRepo.setSeatApprovalPending(true);
    await SpaceCodeRepo.clearPendingInvitation();
    try {
      final opened = await api.open(
        accessToken: accessToken,
        invitationId: pending.invitationId,
      );
      // Kept while the teacher's approval is outstanding; any other answer
      // settles it. A failed open leaves it set: the outcome is unknown.
      await SpaceCodeRepo.setSeatApprovalPending(
        opened.outcome == OpenOutcome.pending,
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
        await SpaceCodeRepo.setSeatApprovalPending(false);
        notify(const ClaimNotice(ClaimNoticeKind.notLive));
      } else if (e.errcode ==
          StudentInvitationApiException.alreadyClaimedInCourse) {
        await SpaceCodeRepo.setSeatApprovalPending(false);
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
}
