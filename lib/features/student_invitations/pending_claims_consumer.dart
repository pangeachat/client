import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/student_invitations/managed_consent.dart';
import 'package:fluffychat/features/student_invitations/pending_claims_flow.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The text a [ClaimNotice] shows.
String claimNoticeText(L10n l10n, ClaimNotice notice) {
  final course = notice.courseName ?? l10n.seatInviteYourCourse;
  return switch (notice.kind) {
    ClaimNoticeKind.claimed => l10n.seatInviteClaimed(course),
    ClaimNoticeKind.pendingApproval => l10n.seatInvitePendingApproval,
    ClaimNoticeKind.denied => l10n.seatInviteDenied,
    ClaimNoticeKind.notLive => l10n.seatInviteNotLive,
    ClaimNoticeKind.alreadyClaimed => l10n.seatInviteAlreadyClaimed(course),
    ClaimNoticeKind.canvasLinked => l10n.canvasLinked,
    ClaimNoticeKind.ticketExpired => l10n.canvasTicketExpired,
    ClaimNoticeKind.ticketWrongAccount => l10n.canvasTicketWrongAccount,
    ClaimNoticeKind.canvasAlreadyLinked => l10n.canvasAlreadyLinked,
    ClaimNoticeKind.failed => l10n.seatInviteFailed,
  };
}

/// The flow for the signed-in [client], with the app's dialog, snackbar,
/// browser hand-off and error reporting.
PendingClaimsFlow pendingClaimsFlowFor(BuildContext context, Client client) {
  final api = StudentInvitationApi(
    httpClient: client.httpClient,
    homeserver: client.homeserver!,
  );
  final messenger = ScaffoldMessenger.of(context);
  final l10n = L10n.of(context);
  return PendingClaimsFlow(
    api: api,
    accessToken: client.accessToken!,
    askConsent: (request) async => context.mounted
        ? ManagedConsentDialog.show(context, request, api: api)
        : null,
    notify: (notice) => messenger.showSnackBarAnnounced(
      SnackBar(content: Text(claimNoticeText(l10n, notice))),
    ),
    // admin-dash's canvas-connect page, in this window (C5.3 L1).
    openUrl: (url) async {
      await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
    },
    // Ids, tickets and bodies stay out: the error carries status + errcode.
    onError: _logError,
  );
}

/// Before the first subscription status read after sign-in or registration
/// (SubscriptionController's initialize): return what the student already
/// ticked, so the claim lands before choreo could auto-claim a trial. No
/// screens exist yet; anything needing one waits for [PendingClaimsConsumer],
/// which also shows the outcome. Bounded so a slow module never holds the
/// app's start; nothing is ever sent without the tick.
Future<void> confirmTickedClaimsBeforeStatus(Client client) async {
  final homeserver = client.homeserver;
  final token = client.accessToken;
  if (!client.isLogged() || homeserver == null || token == null) return;
  try {
    await PendingClaimsFlow(
      api: StudentInvitationApi(
        httpClient: client.httpClient,
        homeserver: homeserver,
      ),
      accessToken: token,
      notify: PendingClaimsConsumer._deferred.add,
      openUrl: (_) async {},
      onError: _logError,
    ).consumeTicked().timeout(const Duration(seconds: 10));
  } catch (e, s) {
    _logError(e, s);
  }
}

void _logError(Object e, StackTrace s) => ErrorHandler.logError(
  e: e,
  s: s,
  data: const {'feature': 'student_invitations'},
);

/// Headless shell resident (like DmInviteFerryConsumer) for the student side
/// after sign-in: shows what [confirmTickedClaimsBeforeStatus] did, returns a
/// ferried Canvas ticket, confirms a ferried seat
/// invitation, then offers invitations waiting for the account's verified
/// addresses (once per account per app session). Mounted by the workspace
/// shell, so it runs exactly when signed in with the map up. Waits while a
/// coded join is in progress on screen, and tries again on every workspace
/// navigation. Renders nothing.
class PendingClaimsConsumer extends StatefulWidget {
  final Uri uri;
  const PendingClaimsConsumer({super.key, required this.uri});

  /// Outcomes of [confirmTickedClaimsBeforeStatus], shown once the shell is up.
  static final List<ClaimNotice> _deferred = [];

  @override
  State<PendingClaimsConsumer> createState() => _PendingClaimsConsumerState();
}

class _PendingClaimsConsumerState extends State<PendingClaimsConsumer> {
  static bool _running = false;
  static final Set<String> _promptedFor = {};
  static final Set<String> _dismissed = {};

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
    if (!mounted || _running) return;
    // The auto-submitting class-code join is on screen: let it land first.
    if (joinCodeFor(widget.uri) != null) return;
    final client = Matrix.of(context).client;
    final userId = client.userID;
    if (!client.isLogged() ||
        userId == null ||
        client.homeserver == null ||
        client.accessToken == null) {
      return;
    }
    _running = true;
    try {
      final flow = pendingClaimsFlowFor(context, client);
      final deferred = [...PendingClaimsConsumer._deferred];
      PendingClaimsConsumer._deferred.clear();
      deferred.forEach(flow.notify);
      await flow.consumeLtiTicket();
      await flow.consumeInvitation();
      if (_promptedFor.add(userId)) await flow.promptPending(_dismissed);
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
