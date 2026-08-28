import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/dm_invite/dm_invite_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
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
  /// consumption half ([consumeCachedJoinCode]).
  static FutureOr<String?> roomsRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
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
    return consumeCachedJoinCode(state.uri);
  }

  /// The DM invite link's redirect (`/invite_user/:userID`, #8436) — the one
  /// inbound contract that resolves through its own route, and that route
  /// never renders: the invited user is cached in the login-bounce ferry
  /// (SpaceCodeRepo.dmInviteUserId) on EVERY landing, logged in or out, and
  /// the user is sent on through [roomsRedirect] — the login bounce, the
  /// registration hop, or a pending higher-precedence join/activity — landing
  /// otherwise on the world map with the chat list open. The DM itself is
  /// opened from inside the shell (DmInviteFerryConsumer), which the signal
  /// wakes when the shell is already up (an in-session tap); a shell that
  /// mounts later — after login or onboarding — reads the ferry on mount. So a
  /// slow first sync is spent looking at the app, never at a blank landing.
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
  /// caching half): a logged-in landing with a fresh cached join code enters
  /// the join flow that code was cached for. This guard is where consumption
  /// lives because it is the one place every login transport passes through —
  /// an in-session password login navigates back here, while a web SSO login
  /// returns via a full page reload and a restored session boots straight to
  /// `/`, so a login-state listener cannot be relied on for them (the bug this
  /// fixes). Not that it never fires for a restored session — measurement says
  /// it does, on roughly one cold start in ten, whenever the restore finishes
  /// after the app has mounted. It simply cannot be depended on, which is why
  /// consumption lives here and why that listener no longer navigates from a
  /// location the user chose ([loggedInLanding]). The guard never clears the cache — only the join page's
  /// auto-submit does, at the moment it actually fires
  /// (CourseCodePage._autoSubmit). Anything earlier proved lossy: boot-time
  /// navigations (post-login listeners go() to the world route) preempted
  /// first the redirect, then the landed page before its post-frame submit —
  /// each time stranding a cleared cache with no join. Left uncleared, every
  /// logged-in landing simply retries until a submit fires; a visitor who
  /// never gets there is covered by the TTL. New users (L2 unset) never
  /// reach here — their onboarding joins with the cached code and clears it
  /// at completion.
  static Future<String?> consumeCachedJoinCode(Uri current) async {
    final joinCode = SpaceCodeRepo.spaceCode;
    if (joinCode != null) {
      // Already on the coded URL: stay put and let its page submit.
      if (joinCodeFor(current) == joinCode) return null;
      return PRoutes.joinWithCode(joinCode);
    }

    // The same ferry carries a shared activity link (`/<uuid>`, #7821): a
    // pending join outranks it, mirroring the caching side. Consumption is
    // anchored where the activity panel actually opens
    // (LeftPanelActivityDetailsSubpage).
    // The ferry's third payload, a DM invite (`/invite_user/<id>`, #8436),
    // needs no redirect from here: its consumer lives in the shell itself
    // (DmInviteFerryConsumer) and defers behind the two above, so it opens on
    // whatever workspace location the user lands on once nothing outranks it.
    final activityId = SpaceCodeRepo.activityId;
    if (activityId == null) return null;
    if (activityInfoFor(current)?.activityId == activityId) return null;
    return '${PRoutes.world}?left=${ActivityPanelToken(ActivityTokenParam(activityId: activityId)).encode()}';
  }

  /// Bounce a logged-out user to /home. The bounce drops the destination URL,
  /// so an inbound join link's code (the `addcourse:private/<code>` token —
  /// LegacyRedirects, #7524) is cached across it first: a new user's
  /// onboarding joins with it and clears it at completion, and an existing
  /// user's next logged-in landing re-enters the join flow
  /// ([consumeCachedJoinCode]). The cache is time-stamped and expires
  /// (SpaceCodeRepo.cacheTTL) so a visitor who never logs in can't leave a
  /// code that surprise-joins a much later login. The activity link rides the
  /// same ferry (below); the DM invite link too, cached by its own route's
  /// redirect ([dmInviteRedirect]) before it delegates here.
  static Future<String> _loginBounce(GoRouterState state) async {
    final joinCode = joinCodeFor(state.uri);
    if (joinCode != null) {
      await SpaceCodeController.cacheRoomCodeToJoin(joinCode);
    }
    // A shared activity link (`/<uuid>`, folded to its `activity` token by
    // LegacyRedirects) rides the same ferry: cached here, re-entered by
    // [consumeCachedJoinCode] on the post-login landing (#7821).
    final activityId = activityInfoFor(state.uri)?.activityId;
    if (activityId != null) {
      await SpaceCodeRepo.setActivityId(activityId);
    }
    return '/home';
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
  /// So: move them only from a place a logged-in user cannot stay. Everywhere
  /// else the location on screen is the one they asked for, and the router's
  /// own guards ([roomsRedirect]) already vet it.
  ///
  /// [current] is the location the app is on; [isL2Set] whether the account
  /// has chosen a language to learn — until it has, registration outranks
  /// everything, exactly as [roomsRedirect] enforces on every landing.
  static String? loggedInLanding({
    required Uri current,
    required bool isL2Set,
  }) {
    if (!isL2Set) return '/registration';
    return isAuthLocation(current) ? PRoutes.world : null;
  }

  /// Whether [uri] is one of the logged-out entry screens — the `/home` family
  /// (sign in, sign up, and the email variants of each). The only place a
  /// freshly logged-in session has to be moved away from.
  static bool isAuthLocation(Uri uri) =>
      uri.path == _home || uri.path.startsWith('$_home/');

  static const String _home = '/home';

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
