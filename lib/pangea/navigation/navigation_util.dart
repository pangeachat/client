import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

class NavigationUtil {
  static void goToSpaceRoute(
    String route,
    BuildContext context, {
    Object? extra,
  }) {
    final currentRoute = GoRouterState.of(context);
    final currentRouteSegments = currentRoute.uri.pathSegments;

    if (currentRouteSegments.length > 1 &&
        currentRouteSegments[0] == 'rooms' &&
        currentRouteSegments[1] == 'spaces') {
      final spaceId = currentRoute.pathParameters['spaceid'];
      final subroute = route.split('/rooms/');
      String goalRoute = "/rooms/spaces/$spaceId/";
      if (subroute.length > 1) {
        goalRoute += subroute[1];
      }
      if (goalRoute != currentRoute.uri.path) {
        context.go(goalRoute, extra: extra);
        return;
      }
    }

    context.go(route, extra: extra);
  }
}
