import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/student_invitations/lti_entry.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_consumer.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// `/lti/link` — where a Canvas launch lands (C5.2), the ticket already
/// ferried and out of the address bar (LtiEntry.linkRedirect).
///
/// Learner: the Canvas link step (SPEC §4 Student 5; no checkbox, amendment
/// 2026-10-10). Signed in, the ticket goes back with that account's token.
/// Signed out, Continue tries it once without a token: a ticket bound to an
/// already-linked account answers with a login token and signs them in; any
/// other ticket answers 401, unconsumed, and the student goes to the normal
/// sign-up/sign-in with the ticket ferried; it goes back after sign-in
/// (the choreo preflight or PendingClaimsConsumer).
///
/// Instructor: sign in, then the ticket goes back and admin-dash's connect
/// page opens.
class LtiLinkPage extends StatefulWidget {
  final StudentInvitationApi? api;

  const LtiLinkPage({super.key, this.api});

  static const Key continueKey = ValueKey('ltiLinkContinue');

  @override
  State<LtiLinkPage> createState() => _LtiLinkPageState();
}

class _LtiLinkPageState extends State<LtiLinkPage> {
  late final StudentInvitationApi _api =
      widget.api ??
      StudentInvitationApi(
        httpClient: http.Client(),
        homeserver: Uri.parse(AppConfig.defaultHomeserver),
      );

  final PendingLtiTicket? _pending = SpaceCodeRepo.pendingLtiTicket;
  bool _busy = false;
  ClaimNotice? _notice;

  bool get _canContinue {
    final pending = _pending;
    if (pending == null || _busy) return false;
    // A refused ticket is spent; only an unexpected failure may be retried.
    final notice = _notice;
    if (notice != null && notice.kind != ClaimNoticeKind.failed) return false;
    return true;
  }

  Future<void> _continue() async {
    final pending = _pending!;
    final matrix = Matrix.of(context);
    final client = matrix.client;
    final signedIn = client.isLogged() && client.accessToken != null;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (pending.instructor) {
        if (!signedIn) {
          context.go('/home');
          return;
        }
        await pendingClaimsFlowFor(context, client).consumeLtiTicket();
        return;
      }

      if (signedIn) {
        // The ticket is still ferried (or a choreo call's preflight already
        // returned it): this account links and claims.
        await pendingClaimsFlowFor(context, client).consumeLtiTicket();
        if (mounted) context.go(PRoutes.world);
        return;
      }

      await SpaceCodeRepo.clearPendingLtiTicket();
      final LtiLinkOutcome outcome;
      try {
        outcome = await _api.ltiLink(accessToken: null, ticket: pending.ticket);
      } on StudentInvitationApiException catch (e) {
        if (e.statusCode == 401) {
          // Not linked yet: sign up or sign in first, then the (unconsumed)
          // ticket goes back after sign-in.
          await SpaceCodeRepo.setPendingLtiTicket(pending);
          if (mounted) context.go('/home');
          return;
        }
        rethrow;
      }
      final token = outcome.loginToken;
      if (token == null) {
        throw const StudentInvitationApiException(200, 'M_BAD_JSON');
      }
      LtiEntry.holdLoginToken(token);
      if (mounted) context.go(PRoutes.ltiToken);
    } on StudentInvitationApiException catch (e, s) {
      final kind = PendingClaimsFlow.linkFailureKind(e);
      _show(kind == ClaimNoticeKind.failed ? _failed(e, s) : kind);
    } catch (e, s) {
      _show(_failed(e, s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ClaimNoticeKind _failed(Object e, StackTrace s) {
    ErrorHandler.logError(
      e: e,
      s: s,
      data: const {'feature': 'student_invitations', 'step': 'lti_link'},
    );
    return ClaimNoticeKind.failed;
  }

  void _show(ClaimNoticeKind kind) {
    if (mounted) setState(() => _notice = ClaimNotice(kind));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final pending = _pending;
    final notice = _notice;
    final instructor = pending?.instructor ?? false;

    final List<Widget> children;
    if (pending == null) {
      children = [
        Text(l10n.canvasTicketExpired, textAlign: TextAlign.center),
        ElevatedButton(
          onPressed: () => context.go(PRoutes.world),
          child: Text(l10n.continueText),
        ),
      ];
    } else {
      children = [
        if (instructor)
          Text(l10n.canvasConnectExplanation)
        else ...[
          Text(
            l10n.seatInviteTitle(
              pending.courseName ?? l10n.seatInviteYourCourse,
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(l10n.canvasLinkExplanation, style: theme.textTheme.bodySmall),
        ],
        if (notice != null)
          Text(
            claimNoticeText(l10n, notice),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ElevatedButton(
          key: LtiLinkPage.continueKey,
          onPressed: _canContinue ? _continue : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : Text(l10n.continueText),
        ),
      ];
    }

    return Semantics(
      label: l10n.pageLabel(
        instructor ? l10n.canvasConnectTitle : l10n.canvasLinkTitle,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: ExcludeSemantics(
            child: Text(
              instructor ? l10n.canvasConnectTitle : l10n.canvasLinkTitle,
            ),
          ),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16.0,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
