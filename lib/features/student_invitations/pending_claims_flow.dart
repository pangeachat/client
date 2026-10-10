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

  /// Null where no screen can be shown (before the shell, see
  /// [consumeTicked]): a confirmation that needs a (new) tick is then put back
  /// in the ferry unticked, for the shell to ask.
  final ConsentPrompt? askConsent;
  final void Function(ClaimNotice notice) notify;
  final Future<void> Function(Uri url) openUrl;

  /// Reports a failure that is not one of the module's expected refusals.
  /// Callers must never pass ids, tickets or bodies along with it.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const PendingClaimsFlow({
    required this.api,
    required this.accessToken,
    this.askConsent,
    required this.notify,
    required this.openUrl,
    this.onError,
  });

  /// Right after sign-in or registration, before the session's first choreo
  /// call: return what the student already ticked, so the claim exists
  /// before choreo's HTTP gate could auto-claim a trial
  /// (SPEC: a student with a waiting seat never burns their trial). Only
  /// ticked entries go; anything else waits for the shell's screens.
  Future<void> consumeTicked() async {
    if (_hasTickedTicket) await consumeLtiTicket();
    if (_hasTickedInvitation) await consumeInvitation();
  }

  /// Whether [consumeTicked] has anything to send.
  static bool get hasTickedEntry => _hasTickedTicket || _hasTickedInvitation;

  static bool get _hasTickedTicket {
    final ticket = SpaceCodeRepo.pendingLtiTicket;
    return ticket != null &&
        !ticket.instructor &&
        ticket.ackedDisclosureVersion != null;
  }

  static bool get _hasTickedInvitation =>
      SpaceCodeRepo.pendingInvitation?.ackedDisclosureVersion != null;

  /// The tick for [request]: the screen's answer, or, with no screen, null
  /// after [reFerry] put the entry back unticked.
  Future<int?> _ask(
    ConsentRequest request,
    Future<void> Function() reFerry,
  ) async {
    final prompt = askConsent;
    if (prompt != null) return prompt(request);
    await reFerry();
    return null;
  }

  /// The invitation a class link carried (`?inv=`), if one is waiting.
  Future<void> consumeInvitation() async {
    final pending = SpaceCodeRepo.pendingInvitation;
    if (pending == null) return;
    await SpaceCodeRepo.clearPendingInvitation();

    // The hint only names the course for a screen. Without one (the choreo
    // preflight) it stays off the path, so the confirm is the one module call
    // choreo waits on; an unknown invitation answers the confirm with 404.
    InvitationHint? hint;
    if (askConsent != null) {
      hint = await _hint(pending.invitationId);
      if (hint == null) return;
    }
    await _confirm(
      pending.invitationId,
      ConsentRequest(
        courseName: hint?.courseName,
        maskedEmailHint: hint?.maskedEmailHint,
      ),
      pending.ackedDisclosureVersion,
      () => SpaceCodeRepo.setPendingInvitation(pending.withAck(null)),
    );
  }

  /// The hint for a screen, or null after reporting an invitation the module
  /// no longer knows. Any other failure yields an empty hint: the confirm
  /// decides.
  Future<InvitationHint?> _hint(String invitationId) async {
    try {
      return await api.hint(invitationId);
    } on StudentInvitationApiException catch (e, s) {
      if (e.statusCode == 404) {
        notify(const ClaimNotice(ClaimNoticeKind.notLive));
        return null;
      }
      onError?.call(e, s);
    } catch (e, s) {
      onError?.call(e, s);
    }
    return const InvitationHint();
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
      final prompt = askConsent;
      if (prompt == null) return;
      final request = ConsentRequest(courseName: row.courseName);
      final version = await prompt(request);
      if (version == null) continue;
      await _confirm(row.invitationId, request, version, () async {});
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
    Future<void> reFerry() =>
        SpaceCodeRepo.setPendingLtiTicket(pending.withAck(null));
    var version =
        pending.ackedDisclosureVersion ?? await _ask(request, reFerry);
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
          version = await _ask(request, reFerry);
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
    Future<void> Function() reFerry,
  ) async {
    var version = ackedVersion ?? await _ask(request, reFerry);
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
          version = await _ask(request, reFerry);
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
