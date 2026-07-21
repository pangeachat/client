import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
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

  /// Redirect for /rooms routes
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

  /// The consumption half of the login-bounce ferry ([_loginBounce] is the
  /// caching half): a logged-in landing with a fresh cached join code enters
  /// the join flow that code was cached for. This guard is where consumption
  /// lives because it is the one place every login transport passes through —
  /// an in-session password login navigates back here, while a web SSO login
  /// returns via a full page reload and a restored session boots straight to
  /// `/`, so a login-state listener never fires for them (the bug this
  /// fixes). The guard never clears the cache — only the join page's
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
    if (joinCode == null) return null;
    // Already on the coded URL: stay put and let its page submit.
    if (joinCodeFor(current) == joinCode) return null;
    return PRoutes.joinWithCode(joinCode);
  }

  /// Bounce a logged-out user to /home. The bounce drops the destination URL,
  /// so an inbound join link's code (the `addcourse:private/<code>` token —
  /// LegacyRedirects, #7524) is cached across it first: a new user's
  /// onboarding joins with it and clears it at completion, and an existing
  /// user's next logged-in landing re-enters the join flow
  /// ([consumeCachedJoinCode]). The cache is time-stamped and expires
  /// (SpaceCodeRepo.cacheTTL) so a visitor who never logs in can't leave a
  /// code that surprise-joins a much later login.
  static Future<String> _loginBounce(GoRouterState state) async {
    final joinCode = joinCodeFor(state.uri);
    if (joinCode != null) {
      await SpaceCodeController.cacheRoomCodeToJoin(joinCode);
    }
    return '/home';
  }

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
