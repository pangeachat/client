import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

class NavigationUtil {
  static void goToSpaceRoute(
    String? goalRoomID,
    List<String> goalSubroute,
    BuildContext context, {
    Object? extra,
    Map<String, String>? queryParams,
  }) {
    final currentRoute = GoRouterState.of(context);
    final currentRouteSegments = currentRoute.uri.pathSegments;
    String queryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      queryString =
          '?${queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    if (currentRouteSegments.length > 1 &&
        currentRouteSegments[0] == 'rooms' &&
        currentRouteSegments[1] == 'spaces' &&
        currentRoute.pathParameters.containsKey('spaceid')) {
      final spaceId = currentRoute.pathParameters['spaceid']!;
      if (goalRoomID == null) {
        context.go('/rooms/spaces/$spaceId$queryString', extra: extra);
        return;
      }

      if (spaceId == goalRoomID) {
        if (goalSubroute.isEmpty) {
          context.go('/rooms/spaces/$spaceId$queryString', extra: extra);
          return;
        }
        context.go(
          '/rooms/spaces/$spaceId/${goalSubroute.join('/')}$queryString',
          extra: extra,
        );
        return;
      }

      if (goalSubroute.isEmpty) {
        context.go(
          '/rooms/spaces/$spaceId/$goalRoomID$queryString',
          extra: extra,
        );
        return;
      }

      context.go(
        '/rooms/spaces/$spaceId/$goalRoomID/${goalSubroute.join('/')}$queryString',
        extra: extra,
      );
      return;
    }

    if (goalRoomID == null) {
      context.go('/rooms$queryString', extra: extra);
      return;
    }

    if (goalSubroute.isEmpty) {
      context.go('/rooms/$goalRoomID$queryString', extra: extra);
      return;
    }

    context.go(
      '/rooms/$goalRoomID/${goalSubroute.join('/')}$queryString',
      extra: extra,
    );
  }
}
