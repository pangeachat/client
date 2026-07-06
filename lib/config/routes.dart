import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/archive/archive.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/courses/own/invite/course_invite_page.dart';
import 'package:fluffychat/routes/courses/own/selected_course_page.dart';
import 'package:fluffychat/routes/courses/preview/public_course_preview.dart';
import 'package:fluffychat/routes/home/login/login.dart';
import 'package:fluffychat/routes/home/login_or_signup_view.dart';
import 'package:fluffychat/routes/home/signup/signup.dart';
import 'package:fluffychat/routes/invite_user/user_invite_link_page.dart';
import 'package:fluffychat/routes/join_with_link/join_with_link_page.dart';
import 'package:fluffychat/routes/new_private_chat/new_private_chat.dart';
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
    GoRoute(
      path: '/join_with_link',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        JoinClassWithLink(
          classCode: state.uri.queryParameters[SpaceConstants.classCode],
        ),
      ),
    ),
    GoRoute(
      path: '/invite_user/:userID',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        UserInviteLink(userID: state.pathParameters['userID']!),
      ),
    ),
    GoRoute(
      path: '/join',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        JoinClassWithLink(
          classCode: state.uri.queryParameters[SpaceConstants.classCode],
        ),
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
        // World home (world_v2): the app opens onto the map, in both
        // column and narrow mode. Chats are their own section at /chats.
        GoRoute(
          path: '/',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const EmptyPage()),
        ),
        // world_v2: there is no `/chats` render route — the chat list is the
        // `left=chats` token over `/`, rendered by the shell. The retired
        // `/chats` / `/rooms` paths are dead by design — internal nav emits the
        // token, not these paths, so nothing redirects them; only the
        // `/rooms/archive` + `/rooms/newprivatechat` fork utility pages remain.
        // Pangea#
        GoRoute(
          path: '/rooms',
          redirect: loggedOutRedirect,
          // Bare `/rooms` is a retired path (dead by design — it renders empty);
          // this parent survives only to host the archive / newprivatechat fork
          // utility pages below.
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const EmptyPage()),
          routes: [
            GoRoute(
              path: 'archive',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const Archive()),
              routes: [
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPage(
                      roomId: fullRoomId(state.pathParameters['roomid']!),
                      eventId: state.uri.queryParameters['event'],
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newprivatechat',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const NewPrivateChat()),
              redirect: loggedOutRedirect,
            ),
          ],
        ),
        // #Pangea
        // world_v2 section roots — see .github/vision/world_v2.md and
        // lib/pangea/navigation/. These render only their bounded children
        // (course-wizard steps, previews); retired bare section paths are dead
        // by design and are not redirected.
        GoRoute(
          path: '/courses',
          redirect: loggedOutRedirect,
          // world_v2: the add-course hub + its own/browse/private steps are the
          // `addcourse` left token (rendered by AddCoursePanel); bare `/courses`
          // and `/courses/own` redirect to those tokens before rendering. This
          // tree survives only to host the route-driven Completer wizard
          // (own/:courseid[/invite], :spaceid/addcourse/:courseId — a Completer
          // can't ride a token URL) and the public-course preview.
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const EmptyPage()),
          routes: [
            GoRoute(
              path: 'own',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const EmptyPage()),
              routes: [
                GoRoute(
                  path: ':courseid',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      SelectedCourse(
                        state.pathParameters['courseid']!,
                        SelectedCourseMode.launch,
                      ),
                    );
                  },
                  routes: [
                    GoRoute(
                      path: 'invite',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          CourseInvitePage(
                            state.pathParameters['courseid']!,
                            courseCreationCompleter:
                                state.extra as Completer<String>?,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: 'preview/:courseroomid',
              pageBuilder: (context, state) {
                return defaultPageBuilder(
                  context,
                  state,
                  PublicCoursePreview(
                    roomID: fullRoomId(state.pathParameters['courseroomid']!),
                  ),
                );
              },
            ),
            GoRoute(
              path: ':spaceid',
              // world_v2: the course card is a token (?m=course:<id>&left=course)
              // — inbound /courses/:spaceid paths redirect to it. This route
              // survives only to host the route-driven add-a-plan Completer flow
              // below (a Completer can't ride a token URL). See routing.instructions.md.
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const EmptyPage()),
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'addcourse',
                  pageBuilder: (context, state) =>
                      defaultPageBuilder(context, state, const EmptyPage()),
                  redirect: loggedOutRedirect,
                  routes: [
                    GoRoute(
                      path: ':courseId',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        SelectedCourse(
                          state.pathParameters['courseId']!,
                          SelectedCourseMode.addToSpace,
                          spaceId: fullRoomId(state.pathParameters['spaceid']!),
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        // world_v2: there is no `/analytics` render route tree. Analytics is
        // entirely token-driven — the cluster opens `right=analytics:<tab>`, a
        // vocab/grammar item blooms a `right=vocab`/`grammar` detail, a completed
        // activity opens a `left=session` chat, and the Practice button opens a
        // `right=practice:<type>` panel (all via AnalyticsNavigationUtil /
        // WorkspaceNav). Legacy `/analytics[/...]` deep links redirect to those
        // tokens (legacy_redirects).
        // Pangea#
        // world_v2: there is no `/settings` render route tree. Profile +
        // settings are the `right=settings` master with each page opening as a
        // `right=settingspage:<page>` detail (rendered by the shell, via
        // WorkspaceNav.openSettings). The learning unsaved-changes guard lives
        // in the page; the security leaves (password/ignorelist/3pid) and
        // chat/emotes are token sub-pages. Retired `/settings[/...]` deep links
        // are dead by design — nothing redirects them.
        // Pangea#
        // world_v2: there is no `/profile` render route — the avatar surface
        // (profile + settings merged) is the `right=settings` token, and the
        // profile editor is the `settingspage:profile/edit` detail, both
        // rendered by the shell. Retired `/profile[/edit]` paths are dead by
        // design — nothing redirects them.
        // Pangea#
        // #Pangea
        // world_v2: the standalone activity link `/<uuid>` is NOT a render route.
        // It is the ONE inbound URL `LegacyRedirects` rewrites — to its
        // `left=activity:<id>` token before anything renders (#7385), so the
        // shell hosts the activity as a first-class left panel, not a canvas
        // detail. See `routing.instructions.md`.
        // Pangea#
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
