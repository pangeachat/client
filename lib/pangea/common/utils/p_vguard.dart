import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../controllers/pangea_controller.dart';

class PAuthGaurd {
  static bool isPublicLeaving = false;
  static PangeaController? pController;

  /// Redirect for /home routes
  static FutureOr<String?> homeRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    if (pController == null) {
      return Matrix.of(context).client.isLogged() ? PRoutes.world : null;
    }

    final isLogged = Matrix.of(
      context,
    ).widget.clients.any((client) => client.isLogged());
    if (!isLogged) return null;

    // If user hasn't set their L2,
    // and their URL doesn’t include ‘course,’ redirect
    final bool hasSetL2 = await pController!.userController.isUserL2Set;
    return !hasSetL2 ? '/registration' : PRoutes.world;
  }

  /// The logged-in-only guard on the world root `/`. Logged out, it is the
  /// caching half of the login-bounce ferry ([_loginBounce]); logged in, the
  /// consumption half ([consumeCachedDestination]).
  static FutureOr<String?> roomsRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final withoutInvitation = await stashInvitation(state.uri);
    if (withoutInvitation != null) return withoutInvitation;
    if (pController == null) {
      if (Matrix.of(context).client.isLogged()) return null;
      return _loginBounce(state);
    }

    final isLogged = Matrix.of(
      context,
    ).widget.clients.any((client) => client.isLogged());
    if (!isLogged) {
      return _loginBounce(state);
    }

    // If user hasn't set their L2,
    // and their URL doesn’t include ‘course,’ redirect
    final bool hasSetL2 = await pController!.userController.isUserL2Set;
    if (!hasSetL2) return '/registration';
    return consumeCachedDestination(state.uri);
  }

  /// A seat invitation link's id (`inv=`, kept by the `/<code>` fold) moves
  /// into its own ferry entry (SpaceCodeRepo.pendingInvitation) on EVERY
  /// landing, logged in or out, and leaves the URL: the coded join page
  /// history-replaces its URL and then navigates to the course, which would
  /// drop it, and the bounce must not carry it in the destination twice.
  /// Returns the location without `inv` (the redirect re-runs on it), or null
  /// when [uri] has none. A different invitation replaces a stored one; a
  /// malformed id is dropped. It is opened once after sign-in, before any
  /// choreo call (ChoreoGate, PendingClaimsConsumer).
  static Future<String?> stashInvitation(Uri uri) async {
    final location = PRoutes.locationWithoutInvitation(uri);
    if (location == null) return null;
    final id = PRoutes.invitationIdIn(uri);
    if (id != null) {
      await SpaceCodeRepo.setPendingInvitation(PendingInvitation(id));
    }
    return location;
  }

  /// The DM invite link's redirect (`/invite_user/:userID`, #8436) — the one
  /// inbound contract that resolves through its own route, and that route
  /// never renders: the invited user is cached in its own ferry entry
  /// (SpaceCodeRepo.dmInviteUserId) on EVERY landing, logged in or out, and
  /// the user is sent on through [roomsRedirect] — the login bounce, the
  /// registration hop, or a pending destination — landing otherwise on the
  /// world map with the chat list open. The DM itself is opened from inside
  /// the shell (DmInviteFerryConsumer), which the signal wakes when the shell
  /// is already up (an in-session tap); a shell that mounts later — after
  /// login or onboarding — reads the entry on mount. So a slow first sync is
  /// spent looking at the app, never at a blank landing.
  static Future<String> dmInviteRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final userId = dmInviteUserIdFor(state.uri);
    if (userId != null) {
      await SpaceCodeRepo.setDmInviteUserId(userId);
      DmInviteController.signalPending();
    }
    return await roomsRedirect(context, state) ?? PRoutes.chatsList;
  }

  /// The consumption half of the login-bounce ferry ([_loginBounce] is the
  /// caching half): a logged-in landing is sent on to the destination the
  /// visitor was bounced from, and the entry is cleared in the same step
  /// (routing.instructions.md § A signed-out visitor's destination).
  ///
  /// Consumption lives in this guard because it is the one place every login
  /// transport passes through — an in-session password or SSO login
  /// navigates here, a restored session boots straight to `/`, and a new
  /// account's onboarding ends here — so a login-state listener cannot be
  /// relied on (the bug #7819 fixed).
  ///
  /// Clearing on redirect is safe now that no boot-time navigation competes
  /// with the landing: the login listener leaves a non-entry location alone
  /// ([loggedInLanding]), and its unconditional jump to the world map is what
  /// made the join code's earlier retry-until-consumed contract necessary.
  /// It is also required: the shell may rewrite the landing URL (a width
  /// fold), and an entry kept until "arrival" would redirect back forever. A
  /// landing already on the destination — a logged-in user opening the very
  /// link a stale entry holds — just clears it. The DM invite link keeps its
  /// own entry, consumed from inside the shell (DmInviteFerryConsumer).
  static Future<String?> consumeCachedDestination(Uri current) async {
    final destination = SpaceCodeRepo.destination;
    if (destination == null) return null;
    await SpaceCodeRepo.clearDestination();
    return destination == current.toString() ? null : destination;
  }

  /// Bounce a logged-out user to /home. The bounce drops the URL, so the
  /// workspace location the visitor opened is cached across it first
  /// ([bounceDestinationFor]) and re-entered on the next logged-in landing
  /// ([consumeCachedDestination]); a brand-new user's onboarding reads a join
  /// code out of it and clears it at completion. The cache is time-stamped
  /// and expires (SpaceCodeRepo.cacheTTL) so a visitor who never logs in
  /// can't leave a destination that carries a much later login somewhere it
  /// never asked to go. The DM invite link is cached by its own route's
  /// redirect ([dmInviteRedirect]) before it delegates here, and is not a
  /// destination.
  static Future<String> _loginBounce(GoRouterState state) async {
    final destination = bounceDestinationFor(state.uri);
    if (destination != null) {
      await SpaceCodeRepo.setDestination(destination);
    }
    return '/home';
  }

  /// The location the bounce keeps for [uri], or null when there is nothing
  /// to keep: only a workspace location — the world root with a query — is a
  /// destination (SpaceCodeRepo.isValidDestination). The bare root is the
  /// default landing, and caching it would let a plain app open, or the
  /// native SSO callback's `/`, overwrite a real destination; the DM invite
  /// route keeps its own entry. Pure — unit-tested
  /// (login_bounce_destination_test.dart).
  static String? bounceDestinationFor(Uri uri) {
    final location = uri.toString();
    return SpaceCodeRepo.isValidDestination(location) ? location : null;
  }

  /// Where a client that has just announced [LoginState.loggedIn] belongs, or
  /// null to LEAVE THE URL ALONE.
  ///
  /// The listener that calls this (matrix.dart) exists for a login the user
  /// just performed: the sign-in screen cannot navigate away from itself, so
  /// something has to move them into the app. But the SDK announces the same
  /// state when it merely RESTORES a session at startup, and that announcement
  /// arrives whenever the restore happens to finish — which on a cold start is
  /// after the app has mounted and already resolved the URL the user opened.
  /// Sending them to the world map then DESTROYS that URL.
  ///
  /// It is a race, so it looked like anything but one. Measured on the local
  /// stack, one cold load in ten lost `?left=chats,room:...`: the router
  /// accepted the deep link, and 164ms later the restored session pushed `/`
  /// over the top of it. The slower the restore — a big local database, a
  /// device catching up after a call — the likelier the loss, which is why
  /// "the link stopped working after a call" was a fair description of a bug
  /// that has nothing to do with calls.
  ///
  /// So: move them only from a place a finished account cannot stay — an ENTRY
  /// location ([isEntryLocation]). Everywhere else the location on screen is
  /// the one they asked for, and the router's own guards ([roomsRedirect])
  /// already vet it.
  ///
  /// [current] is the location the app is on; [isL2Set] whether the account
  /// has chosen a language to learn — until it has, registration outranks
  /// everything, exactly as [roomsRedirect] enforces on every landing.
  static String? loggedInLanding({
    required Uri current,
    required bool isL2Set,
  }) {
    if (!isL2Set) return '/registration';
    return isEntryLocation(current) ? PRoutes.world : null;
  }

  /// Whether [uri] is a route that exists only to get an account STARTED: the
  /// `/home` family (sign in, sign up, and the email variant of each), the
  /// onboarding and registration hops, and the Canvas login-token sign-in.
  ///
  /// None of these is somewhere an account that has finished starting can
  /// stay, and none is a place a person deep-links to, so moving off them costs
  /// nothing. The `/home` screens cannot navigate away from themselves once a
  /// login succeeds — that is the whole reason the listener exists. Onboarding
  /// and registration are here because a completed account reloading on one of
  /// them was carried to the map before this function existed, and their own
  /// route guard does not do it: [onboardingRedirect] admits any logged-in
  /// user, L2 set or not.
  ///
  /// A prefix test on whole segments, so `/homework` is not `/home`.
  static bool isEntryLocation(Uri uri) => _entryRoots.any(
    (root) => uri.path == root || uri.path.startsWith('$root/'),
  );

  static const List<String> _entryRoots = [
    '/home',
    '/onboarding',
    '/registration',
    // The Canvas login-token sign-in (C5): nothing to stay on once signed in.
    PRoutes.ltiToken,
  ];

  /// Redirect for onboarding routes
  static FutureOr<String?> onboardingRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    if (pController == null) {
      return Matrix.of(context).client.isLogged() ? null : '/home';
    }

    final isLogged = Matrix.of(
      context,
    ).widget.clients.any((client) => client.isLogged());
    if (!isLogged) {
      return '/home';
    }

    return null;
  }
}
