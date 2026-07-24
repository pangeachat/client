import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/routes/home/login/login.dart';
import 'package:fluffychat/routes/home/login_or_signup_view.dart';
import 'package:fluffychat/routes/home/signup/signup.dart';
import 'package:fluffychat/routes/invite_user/user_invite_link_page.dart';
import 'package:fluffychat/routes/onboarding/onboarding_page.dart';
import 'package:fluffychat/routes/registration/create_pangea_account_page.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';
import 'package:fluffychat/widgets/log_view.dart';

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => PAuthGaurd.homeRedirect(context, state);

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => PAuthGaurd.roomsRedirect(context, state);

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LoginOrSignupView()),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const Login()),
          redirect: loggedInRedirect,
          // #Pangea
          routes: [
            GoRoute(
              path: 'email',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                const Login(withEmail: true),
              ),
            ),
          ],
          // Pangea#
        ),
        // #Pangea
        GoRoute(
          path: 'signup',
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const SignupPage()),
          routes: [
            GoRoute(
              path: 'email',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                const SignupPage(withEmail: true),
              ),
            ),
          ],
        ),
        // Pangea#
      ],
    ),
    GoRoute(
      path: '/logs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const LogViewer()),
    ),
    GoRoute(
      path: '/configs',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const ConfigViewer()),
    ),
    // #Pangea
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const Onboarding()),
      redirect: PAuthGaurd.onboardingRedirect,
    ),
    GoRoute(
      path: '/registration',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const CreatePangeaAccountPage()),
      redirect: PAuthGaurd.onboardingRedirect,
    ),
    // world_v2: the inbound course join link is the bare short code
    // `app.pangea.chat/<code>` (served by the SPA on web and delivered as a
    // path by native app links); it is NOT a render route. `LegacyRedirects`
    // folds `/<code>` into the `left=addcourse:private/<code>` token before
    // anything renders, so the join-with-code page performs the join. Logged
    // out, the code is cached across the login bounce (PAuthGaurd.roomsRedirect).
    GoRoute(
      path: '/invite_user/:userID',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        UserInviteLink(userID: state.pathParameters['userID']!),
      ),
    ),
    // Pangea#
    ShellRoute(
      // Never use a transition on the shell route. Changing the PageBuilder
      // here based on a MediaQuery causes the child to briefly be rendered
      // twice with the same GlobalKey, blowing up the rendering.
      pageBuilder: (context, state, child) => noTransitionPageBuilder(
        context,
        state,
        WorkspaceShell(state: state, sideView: child),
      ),
      routes: [
        // #Pangea
        // World home (world_v2): the app opens onto the map, in both column and narrow mode.
        GoRoute(
          path: '/',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const EmptyPage()),
        ),
      ],
    ),
  ];

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    name: analyticsPageName(state),
    restorationId: state.pageKey.value,
    child: child,
  );

  static String analyticsPageName(GoRouterState state) {
    final fullPath = state.fullPath;
    if (fullPath != null && fullPath.isNotEmpty) {
      return fullPath;
    }

    final routePath = state.path;
    if (routePath != null && routePath.isNotEmpty) {
      return routePath;
    }

    if (state.uri.path.isNotEmpty) {
      return state.uri.path;
    }

    return '/';
  }

  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => noTransitionPageBuilder(context, state, child);
}
