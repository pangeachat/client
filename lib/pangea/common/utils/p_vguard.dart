import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/join_codes/space_code_controller.dart';
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
    return !hasSetL2 ? '/registration' : null;
  }

  /// Bounce a logged-out user to /home. The bounce drops the destination URL,
  /// so an inbound join link's code (the `addcourse:private/<code>` token —
  /// LegacyRedirects, #7524) is cached across it first: a new user's
  /// onboarding joins with it and clears it at completion, and the post-login
  /// redirect re-enters the join token flow for an existing one (see
  /// matrix.dart's login-state listener). The cache is time-stamped and
  /// expires (SpaceCodeRepo.cacheTTL) so a visitor who never logs in can't
  /// leave a code that surprise-joins a much later login.
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
