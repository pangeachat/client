import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';

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

    if (currentRouteSegments.isNotEmpty &&
        currentRouteSegments[0] == 'courses' &&
        currentRoute.pathParameters.containsKey('spaceid')) {
      final spaceId = fullRoomId(currentRoute.pathParameters['spaceid']!);
      if (goalRoomID == null) {
        context.go('${PRoutes.course(spaceId)}$queryString', extra: extra);
        return;
      }

      if (spaceId == goalRoomID) {
        if (goalSubroute.isEmpty) {
          context.go('${PRoutes.course(spaceId)}$queryString', extra: extra);
          return;
        }
        context.go(
          '${PRoutes.course(spaceId)}/${goalSubroute.join('/')}$queryString',
          extra: extra,
        );
        return;
      }

      if (goalSubroute.isEmpty) {
        context.go(
          '${PRoutes.course(spaceId)}/$goalRoomID$queryString',
          extra: extra,
        );
        return;
      }

      context.go(
        '${PRoutes.course(spaceId)}/$goalRoomID/${goalSubroute.join('/')}$queryString',
        extra: extra,
      );
      return;
    }

    if (goalRoomID == null) {
      context.go('${PRoutes.world}$queryString', extra: extra);
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
