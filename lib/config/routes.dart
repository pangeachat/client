import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/course_plans/new_course_page.dart';
import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/p_vguard.dart';
import 'package:fluffychat/pangea/spaces/space_constants.dart';
import 'package:fluffychat/routes/analytics/activities/activity_archive.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/analytics_details_popup.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_page.dart';
import 'package:fluffychat/routes/analytics/level/level_analytics_details_content.dart';
import 'package:fluffychat/routes/archive/archive.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/chat_details/emotes/settings_emotes.dart';
import 'package:fluffychat/routes/chat_list/chat_list.dart';
import 'package:fluffychat/routes/courses/add_course_hub_view.dart';
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
import 'package:fluffychat/routes/profile/user_home_page.dart';
import 'package:fluffychat/routes/registration/create_pangea_account_page.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/routes/settings/settings_chat/settings_chat.dart';
import 'package:fluffychat/routes/settings/settings_device/device_settings.dart';
import 'package:fluffychat/routes/settings/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/routes/settings/settings_learning/settings_learning.dart';
import 'package:fluffychat/routes/settings/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_password/settings_password.dart';
import 'package:fluffychat/routes/settings/settings_security/settings_security.dart';
import 'package:fluffychat/routes/settings/settings_style/settings_style.dart';
import 'package:fluffychat/routes/settings/settings_subscription/settings_subscription.dart';
import 'package:fluffychat/routes/world/activity_detail_panel.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/config_viewer.dart';
import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/layouts/workspace_shell.dart';
import 'package:fluffychat/widgets/log_view.dart';

// #Pangea
// import 'package:fluffychat/config/app_config.dart';
// Pangea#
// #Pangea
// import 'package:fluffychat/widgets/matrix.dart';
// Pangea#
// #Pangea
// import 'package:cached_network_image/cached_network_image.dart';
// Pangea#

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
    // #Pangea
    // ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
    //     ? '/rooms'
    //     : null;
  ) => PAuthGaurd.homeRedirect(context, state);
  // Pangea#

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
    // #Pangea
    // ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
    //     ? null
    //     : '/home';
  ) => PAuthGaurd.roomsRedirect(context, state);
  // Pangea#

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        // #Pangea
        // const HomeserverPicker(addMultiAccount: false),
        const LoginOrSignupView(),
        // Pangea#
      ),
      redirect: loggedInRedirect,
      routes: [
        GoRoute(
          path: 'login',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            // #Pangea
            // Login(client: state.extra as Client),
            const Login(),
            // Pangea#
          ),
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
        // #Pangea
        // FluffyThemes.isColumnMode(context) &&
        //         state.fullPath?.startsWith('/rooms/settings') == false
        //     ? WorkspaceShell(
        //         mainView: ChatList(
        //           activeChat: state.pathParameters['roomid'],
        //           activeSpace: state.uri.queryParameters['spaceId'],
        //           displayNavigationRail:
        //               state.path?.startsWith('/rooms/settings') != true,
        //         ),
        //         sideView: child,
        //       )
        //     : child,
        WorkspaceShell(state: state, sideView: child),
        // Pangea#
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
        // Chats section (world_v2): the chat list. In column mode the map
        // is the canvas and ChatList renders in the left column; in narrow
        // mode ChatList is the full screen.
        GoRoute(
          path: '/chats',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            canvasPage(
              context,
              state,
              ChatList(
                activeChat: state.pathParameters['roomid'],
                activeSpace: state.uri.queryParameters['spaceId'],
              ),
            ),
          ),
        ),
        // Pangea#
        GoRoute(
          path: '/rooms',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            canvasPage(
              context,
              state,
              ChatList(
                activeChat: state.pathParameters['roomid'],
                activeSpace: state.uri.queryParameters['spaceId'],
              ),
            ),
          ),
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
            // #Pangea
            // Pangea#
            // #Pangea
            // ShellRoute(
            //   pageBuilder: (context, state, child) => defaultPageBuilder(
            //     context,
            //     state,
            //     FluffyThemes.isColumnMode(context)
            //         ? WorkspaceShell(
            //             mainView: Settings(key: state.pageKey),
            //             sideView: child,
            //           )
            //         : child,
            //   ),
            //   routes: [
            // Pangea#
            // Pangea#
          ],
        ),
        // #Pangea
        // world_v2 section roots — see .github/vision/world_v2.md and
        // lib/pangea/navigation/. Legacy /rooms/... paths reach these
        // through LegacyRedirects (router-level shim).
        GoRoute(
          path: '/courses',
          redirect: loggedOutRedirect,
          // world_v2: `/courses` is the "Add new course" hub — a card that
          // floats over the full-bleed map (only the card absorbs taps), so
          // the map stays pannable around it.
          pageBuilder: (context, state) =>
              defaultPageBuilder(context, state, const AddCourseHubView()),
          routes: [
            GoRoute(
              path: 'own',
              // world_v2: the "Start my own" plan list lives in the left
              // column over the persistent map (column mode), so the course's
              // activities show on the map; narrow mode is full-screen.
              pageBuilder: (context, state) {
                return defaultPageBuilder(
                  context,
                  state,
                  canvasPage(
                    context,
                    state,
                    NewCoursePage(
                      route: 'rooms',
                      initialLanguageCode: state.uri.queryParameters['lang'],
                      showAll: state.uri.queryParameters['showAll'] == 'true',
                    ),
                  ),
                );
              },
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
        GoRoute(
          path: '/analytics',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            canvasPage(
              context,
              state,
              const ConstructAnalyticsView(
                view: ConstructTypeEnum.vocab,
                showPracticeButton: true,
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: ConstructTypeEnum.morph.string,
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                canvasPage(
                  context,
                  state,
                  const ConstructAnalyticsView(
                    view: ConstructTypeEnum.morph,
                    showPracticeButton: true,
                  ),
                ),
              ),
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'practice',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      const AnalyticsPractice(type: ConstructTypeEnum.morph),
                    );
                  },
                ),
                GoRoute(
                  path: ':construct',
                  pageBuilder: (context, state) {
                    final construct = ConstructIdentifier.fromJson(
                      jsonDecode(state.pathParameters['construct']!),
                    );

                    return defaultPageBuilder(
                      context,
                      state,
                      ConstructAnalyticsView(
                        construct: construct,
                        view: ConstructTypeEnum.morph,
                      ),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: ConstructTypeEnum.vocab.string,
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                canvasPage(
                  context,
                  state,
                  const ConstructAnalyticsView(
                    view: ConstructTypeEnum.vocab,
                    showPracticeButton: true,
                  ),
                ),
              ),
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'practice',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      const AnalyticsPractice(type: ConstructTypeEnum.vocab),
                    );
                  },
                  onExit: (context, state) async {
                    // Check if bypass flag was set before navigation
                    if (AnalyticsPractice.bypassExitConfirmation) {
                      AnalyticsPractice.bypassExitConfirmation = false;
                      return true;
                    }

                    final result = await showOkCancelAlertDialog(
                      useRootNavigator: false,
                      context: context,
                      title: L10n.of(context).areYouSure,
                      okLabel: L10n.of(context).yes,
                      cancelLabel: L10n.of(context).cancel,
                      message: L10n.of(context).exitPractice,
                    );

                    return result == OkCancelResult.ok;
                  },
                ),
                GoRoute(
                  path: ':construct',
                  pageBuilder: (context, state) {
                    final construct = ConstructIdentifier.fromJson(
                      jsonDecode(state.pathParameters['construct']!),
                    );
                    return defaultPageBuilder(
                      context,
                      state,
                      ConstructAnalyticsView(
                        construct: construct,
                        view: ConstructTypeEnum.vocab,
                      ),
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: 'activities',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                canvasPage(context, state, const ActivityArchive()),
              ),
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPage(
                      roomId: fullRoomId(state.pathParameters['roomid']!),
                      eventId: state.uri.queryParameters['event'],
                      backButton: BackButton(
                        onPressed: () {
                          AnalyticsNavigationUtil.navigateToAnalytics(
                            context: context,
                            view: ProgressIndicatorEnum.activities,
                          );
                        },
                      ),
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
            GoRoute(
              path: 'level',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                canvasPage(context, state, const LevelAnalyticsDetailsContent()),
              ),
              redirect: loggedOutRedirect,
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            canvasPage(context, state, const Settings()),
          ),
          routes: [
            GoRoute(
              path: 'notifications',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                const SettingsNotifications(),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'style',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const SettingsStyle()),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'devices',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const DevicesSettings()),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'chat',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const SettingsChat()),
              routes: [
                GoRoute(
                  path: 'emotes',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    EmotesSettings(roomId: state.pathParameters['roomid']),
                  ),
                ),
              ],
              redirect: loggedOutRedirect,
            ),
            // #Pangea
            // GoRoute(
            //   path: 'addaccount',
            //   redirect: loggedOutRedirect,
            //   pageBuilder: (context, state) => defaultPageBuilder(
            //     context,
            //     state,
            //     const HomeserverPicker(addMultiAccount: true),
            //   ),
            //   routes: [
            //     GoRoute(
            //       path: 'login',
            //       pageBuilder: (context, state) => defaultPageBuilder(
            //         context,
            //         state,
            //         Login(client: state.extra as Client),
            //       ),
            //       redirect: loggedOutRedirect,
            //     ),
            //   ],
            // ),
            // Pangea#
            GoRoute(
              path: 'homeserver',
              pageBuilder: (context, state) {
                return defaultPageBuilder(
                  context,
                  state,
                  const SettingsHomeserver(),
                );
              },
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'security',
              redirect: loggedOutRedirect,
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const SettingsSecurity()),
              routes: [
                GoRoute(
                  path: 'password',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      const SettingsPassword(),
                    );
                  },
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'ignorelist',
                  pageBuilder: (context, state) {
                    return defaultPageBuilder(
                      context,
                      state,
                      SettingsIgnoreList(
                        initialUserId: state.extra?.toString(),
                      ),
                    );
                  },
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: '3pid',
                  pageBuilder: (context, state) =>
                      defaultPageBuilder(context, state, const Settings3Pid()),
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
            // #Pangea
            GoRoute(
              path: 'learning',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                const SettingsLearning(isDialog: false),
              ),
              redirect: loggedOutRedirect,
              onExit: (context, state) =>
                  SettingsLearningController.handleExit(context),
            ),
            GoRoute(
              path: 'subscription',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                const SubscriptionManagement(),
              ),
              redirect: loggedOutRedirect,
            ),
            // Pangea#
          ],
          redirect: loggedOutRedirect,
        ),
        // Avatar surface (world_v2): profile + settings merged. /profile
        // renders the same menu as /settings (profile header + settings
        // list); the full profile editor moves to /profile/edit.
        GoRoute(
          path: '/profile',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            canvasPage(context, state, const Settings()),
          ),
          routes: [
            GoRoute(
              path: 'edit',
              redirect: loggedOutRedirect,
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, UserHomePage()),
            ),
          ],
        ),
        // Pangea#
        // #Pangea
        // First-class activity URLs: /<activityId> (UUID). Declared after
        // /rooms so literal routes always win; the inline regex prevents
        // single-segment paths like /home from matching.
        GoRoute(
          path:
              '/:activityId([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            ActivityDetailPanel(
              activityId: state.pathParameters['activityId']!,
              roomId: state.uri.queryParameters['roomid'],
              launch: state.uri.queryParameters['launch'] == 'true',
            ),
          ),
        ),
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
    // #Pangea
    // ) => FluffyThemes.isColumnMode(context)
    //     ? noTransitionPageBuilder(context, state, child)
    //     : MaterialPage(
    //         key: state.pageKey,
    //         restorationId: state.pageKey.value,
    //         child: child,
    //       );
  ) => noTransitionPageBuilder(context, state, child);
  // Pangea#

  // #Pangea
  /// A section root's content: the map hole ([EmptyPage]) when this route
  /// renders as a hole in the current mode, else its [content]. The single
  /// source for the canvas decision is [isMapHole] in route_facts.dart, shared
  /// with the shell layout, so the page builder and the layout can't drift.
  static Widget canvasPage(
    BuildContext context,
    GoRouterState state,
    Widget content,
  ) => isMapHole(state.fullPath, FluffyThemes.isColumnMode(context))
      ? const EmptyPage()
      : content;
  // Pangea#

}
