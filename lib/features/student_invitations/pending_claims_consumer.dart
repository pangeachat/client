import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

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
    ClaimNoticeKind.canvasLinked => l10n.canvasLinked,
    ClaimNoticeKind.ticketExpired => l10n.canvasTicketExpired,
    ClaimNoticeKind.ticketWrongAccount => l10n.canvasTicketWrongAccount,
    ClaimNoticeKind.canvasAlreadyLinked => l10n.canvasAlreadyLinked,
    ClaimNoticeKind.failed => l10n.seatInviteFailed,
  };
}

/// The flow for the signed-in [client], with the app's snackbar, browser
/// hand-off and error reporting.
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

/// The choreo preflight (ChoreoGate.preflight): before the session's first
/// choreo call, open the stored invitation and return a learner Canvas
/// ticket, so the claim lands before choreo's HTTP gate could auto-claim a
/// trial on that call. Outcomes are shown once the shell is up
/// ([PendingClaimsConsumer]).
///
/// Choreo calls wait for each claim call's answer or failure, never a
/// cut-off: a claim call is bounded only by the API's own request timeout
/// (30 s), so sign-in cannot hang on a silent module. If the module gives no
/// answer at all, the failure is reported and the calls proceed; the claim
/// may or may not have landed (the entry is not resent, keeping it at most
/// once).
///
/// Single-flight: every choreo call made meanwhile awaits the same run;
/// none finds the ferry already taken and goes ahead while it is in flight.
Future<void> openPendingClaims({
  required StudentInvitationApi api,
  required String accessToken,
}) => _claimsBeforeChoreo ??= _openPending(
  api,
  accessToken,
).whenComplete(() => _claimsBeforeChoreo = null);

Future<void>? _claimsBeforeChoreo;

Future<void> _openPending(StudentInvitationApi api, String accessToken) async {
  try {
    await PendingClaimsFlow(
      api: api,
      accessToken: accessToken,
      notify: PendingClaimsConsumer._deferred.add,
      openUrl: (_) async {},
      onError: _logError,
    ).consumeClaims();
  } catch (e, s) {
    _logError(e, s);
  }
}

/// The preflight for the signed-in [client]. Joins a run in flight first;
/// otherwise resolves at once when nothing is waiting or no one is signed
/// in, so ordinary choreo calls pay nothing.
Future<void> openPendingClaimsBeforeChoreo(Client client) {
  final inFlight = _claimsBeforeChoreo;
  if (inFlight != null) return inFlight;
  if (!PendingClaimsFlow.hasPendingClaim) return Future.value();
  final homeserver = client.homeserver;
  final token = client.accessToken;
  if (!client.isLogged() || homeserver == null || token == null) {
    return Future.value();
  }
  return openPendingClaims(
    api: StudentInvitationApi(
      httpClient: client.httpClient,
      homeserver: homeserver,
    ),
    accessToken: token,
  );
}

void _logError(Object e, StackTrace s) => ErrorHandler.logError(
  e: e,
  s: s,
  data: const {'feature': 'student_invitations'},
);

/// Headless shell resident (like DmInviteFerryConsumer) for the student side
/// after sign-in: runs (or joins) [openPendingClaims], shows what it did,
/// then returns an instructor's Canvas ticket, which opens admin-dash.
/// Mounted by the workspace shell, so it runs exactly when signed in with the
/// map up. Waits while a coded join is in progress on screen, and tries
/// again on every workspace navigation. Renders nothing.
class PendingClaimsConsumer extends StatefulWidget {
  final Uri uri;
  const PendingClaimsConsumer({super.key, required this.uri});

  /// Outcomes of [openPendingClaims], shown once the shell is up.
  static final List<ClaimNotice> _deferred = [];

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
    if (!mounted || _running) return;
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
      final flow = pendingClaimsFlowFor(context, client);
      // The same single-flight run choreo calls wait on: it opens a stored
      // invitation and returns a learner ticket if no choreo call has yet.
      await openPendingClaimsBeforeChoreo(client);
      final deferred = [...PendingClaimsConsumer._deferred];
      PendingClaimsConsumer._deferred.clear();
      deferred.forEach(flow.notify);
      // What is left is an instructor's ticket: it opens admin-dash.
      await flow.consumeLtiTicket();
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
