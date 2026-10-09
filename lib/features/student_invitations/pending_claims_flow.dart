import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';

/// What a confirmation screen needs to name the course and the invited
/// address. The screen fetches the disclosure text itself.
class ConsentRequest {
  final String? courseName;
  final String? maskedEmailHint;

  const ConsentRequest({this.courseName, this.maskedEmailHint});
}

/// Shows the confirmation screen; resolves to the disclosure version the
/// student ticked and confirmed, or null when they did not.
typedef ConsentPrompt = Future<int?> Function(ConsentRequest request);

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
  final String? courseName;

  const ClaimNotice(this.kind, {this.courseName});
}

/// The signed-in half of the student side (SPEC §4 Student 3-5): confirm the
/// seat invitation the visitor arrived with, return a ferried Canvas ticket,
/// and offer invitations waiting for one of the account's verified addresses.
///
/// Two rules hold on every path:
/// - nothing is confirmed, and no learner ticket is returned, without a
///   disclosure version the student ticked;
/// - a ferried invitation or ticket is TAKEN (cleared) before it is sent, so
///   it is returned at most once whatever happens next. A Canvas ticket is
///   single-use on the server anyway; a lost invitation is offered again by
///   the pending prompt when the account has the invited address, and the
///   link still works.
///
/// UI and side effects are injected, so this is unit-tested end to end
/// against a fake module (pending_claims_flow_test.dart).
class PendingClaimsFlow {
  final StudentInvitationApi api;
  final String accessToken;
  final ConsentPrompt askConsent;
  final void Function(ClaimNotice notice) notify;
  final Future<void> Function(Uri url) openUrl;

  /// Reports a failure that is not one of the module's expected refusals.
  /// Callers must never pass ids, tickets or bodies along with it.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const PendingClaimsFlow({
    required this.api,
    required this.accessToken,
    required this.askConsent,
    required this.notify,
    required this.openUrl,
    this.onError,
  });

  /// The invitation a class link carried (`?inv=`), if one is waiting.
  Future<void> consumeInvitation() async {
    final pending = SpaceCodeRepo.pendingInvitation;
    if (pending == null) return;
    await SpaceCodeRepo.clearPendingInvitation();

    InvitationHint? hint;
    try {
      hint = await api.hint(pending.invitationId);
    } on StudentInvitationApiException catch (e, s) {
      if (e.statusCode == 404) {
        notify(const ClaimNotice(ClaimNoticeKind.notLive));
        return;
      }
      // The hint only names the course; the confirm below decides.
      onError?.call(e, s);
    } catch (e, s) {
      onError?.call(e, s);
    }
    await _confirm(
      pending.invitationId,
      ConsentRequest(
        courseName: hint?.courseName,
        maskedEmailHint: hint?.maskedEmailHint,
      ),
      pending.ackedDisclosureVersion,
    );
  }

  /// Invitations to one of this account's verified addresses (S2), each
  /// offered once per session: a "Not now" lands in [dismissed].
  Future<void> promptPending(Set<String> dismissed) async {
    final List<PendingInvitationSummary> rows;
    try {
      rows = await api.minePending(accessToken: accessToken);
    } catch (e, s) {
      onError?.call(e, s);
      return;
    }
    for (final row in rows) {
      if (!dismissed.add(row.invitationId)) continue;
      final request = ConsentRequest(courseName: row.courseName);
      final version = await askConsent(request);
      if (version == null) continue;
      await _confirm(row.invitationId, request, version);
    }
  }

  /// The Canvas ticket ferried from `/lti/link` across sign-in (C5 L1).
  Future<void> consumeLtiTicket() async {
    final pending = SpaceCodeRepo.pendingLtiTicket;
    if (pending == null) return;
    await SpaceCodeRepo.clearPendingLtiTicket();

    if (pending.instructor) {
      try {
        final outcome = await api.ltiLink(
          accessToken: accessToken,
          ticket: pending.ticket,
        );
        final url = outcome.connectUrl;
        if (url == null || !(url.isScheme('https') || url.isScheme('http'))) {
          throw const StudentInvitationApiException(200, 'M_BAD_JSON');
        }
        await openUrl(url);
      } catch (e, s) {
        _reportLinkFailure(e, s);
      }
      return;
    }

    final request = ConsentRequest(courseName: pending.courseName);
    var version = pending.ackedDisclosureVersion ?? await askConsent(request);
    for (var attempt = 0; version != null; attempt++) {
      try {
        await api.ltiLink(
          accessToken: accessToken,
          ticket: pending.ticket,
          disclosureVersion: version,
        );
        notify(const ClaimNotice(ClaimNoticeKind.canvasLinked));
        return;
      } on StudentInvitationApiException catch (e, s) {
        // An outdated disclosure leaves the ticket unconsumed: show the
        // current text once more and send the new tick.
        if (e.isDisclosureOutdated && attempt == 0) {
          version = await askConsent(request);
          continue;
        }
        _reportLinkFailure(e, s);
        return;
      } catch (e, s) {
        _reportLinkFailure(e, s);
        return;
      }
    }
  }

  Future<void> _confirm(
    String invitationId,
    ConsentRequest request,
    int? ackedVersion,
  ) async {
    var version = ackedVersion ?? await askConsent(request);
    for (var attempt = 0; version != null; attempt++) {
      try {
        final outcome = await api.confirm(
          accessToken: accessToken,
          invitationId: invitationId,
          disclosureVersion: version,
        );
        notify(
          ClaimNotice(switch (outcome) {
            ConfirmOutcome.claimed => ClaimNoticeKind.claimed,
            ConfirmOutcome.pendingApproval => ClaimNoticeKind.pendingApproval,
            ConfirmOutcome.denied => ClaimNoticeKind.denied,
          }, courseName: request.courseName),
        );
        return;
      } on StudentInvitationApiException catch (e, s) {
        if (e.isDisclosureOutdated && attempt == 0) {
          version = await askConsent(request);
          continue;
        }
        if (e.statusCode == 404) {
          notify(const ClaimNotice(ClaimNoticeKind.notLive));
        } else if (e.errcode ==
            StudentInvitationApiException.alreadyClaimedInCourse) {
          notify(
            ClaimNotice(
              ClaimNoticeKind.alreadyClaimed,
              courseName: request.courseName,
            ),
          );
        } else {
          onError?.call(e, s);
          notify(const ClaimNotice(ClaimNoticeKind.failed));
        }
        return;
      } catch (e, s) {
        onError?.call(e, s);
        notify(const ClaimNotice(ClaimNoticeKind.failed));
        return;
      }
    }
  }

  void _reportLinkFailure(Object e, StackTrace s) {
    final kind = switch (e) {
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
    if (kind == ClaimNoticeKind.failed) onError?.call(e, s);
    notify(ClaimNotice(kind));
  }
}
