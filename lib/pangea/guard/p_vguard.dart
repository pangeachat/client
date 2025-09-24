import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/widgets/matrix.dart';
import '../common/controllers/pangea_controller.dart';

class PAuthGaurd {
  static bool isPublicLeaving = false;
  static PangeaController? pController;

  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    if (pController != null) {
      if (Matrix.of(context)
          .widget
          .clients
          .any((client) => client.isLogged())) {
        final bool hasSetL2 = await pController!.userController.isUserL2Set;
        final langCode = state.pathParameters['langcode'];
        return hasSetL2
            ? null
            : langCode != null
                ? '/course/$langCode'
                : '/course';
      }
      return null;
    } else {
      debugPrint("controller is null in pguard check");
      Matrix.of(context).client.isLogged() ? '/rooms' : null;
    }
    return null;
  }

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    if (pController != null) {
      if (!Matrix.of(context)
          .widget
          .clients
          .any((client) => client.isLogged())) {
        return '/home';
      }
      final bool hasSetL2 = await pController!.userController.isUserL2Set;
      final langCode = state.pathParameters['langcode'];
      return hasSetL2 || (state.fullPath?.contains('course') ?? false)
          ? null
          : langCode != null
              ? '/course/$langCode'
              : '/course';
    } else {
      debugPrint("controller is null in pguard check");
      return Matrix.of(context).client.isLogged() ? null : '/home';
    }
  }
}
