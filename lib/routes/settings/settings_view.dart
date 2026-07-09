import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/routes/settings/support_chat_list_tile.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

// #Pangea
// Pangea#

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // #Pangea
    // final showChatBackupBanner = controller.showChatBackupBanner;
    // Pangea#
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;
    // #Pangea
    // final accountManageUrl = Matrix.of(context)
    //     .client
    //     .wellKnown
    //     ?.additionalProperties
    //     .tryGetMap<String, Object?>('org.matrix.msc2965.authentication')
    //     ?.tryGet<String>('account');
    // Pangea#
    return Row(
      children: [
        // #Pangea
        // if (FluffyThemes.isColumnMode(context)) ...[
        //   SpacesNavigationRail(
        //     activeSpaceId: null,
        //     onGoToChats: () => context.go('/rooms'),
        //     onGoToSpaceId: (spaceId) => context.go('/rooms?spaceId=$spaceId'),
        //   ),
        //   Container(color: Theme.of(context).dividerColor, width: 1),
        // ],
        // Pangea#
        Expanded(
          child: Scaffold(
            // #Pangea
            // appBar: FluffyThemes.isColumnMode(context)
            //     ? null
            //     : AppBar(
            //         title: Text(L10n.of(context).settings),
            //         leading: Center(
            //           child: BackButton(onPressed: () => context.go('/rooms')),
            //         ),
            //       ),
            // Pangea#
            body: ListTileTheme(
              iconColor: theme.colorScheme.onSurface,
              // #Pangea
              child: SafeArea(
                // Pangea#
                child: ListView(
                  key: const Key('SettingsListViewContent'),
                  children: [
                    // world_v2: the Avatar surface merges profile + settings;
                    // the profile editor is the single-segment `profile` page.
                    // It is not a nested `profile/edit` leaf — `profile` and
                    // `profile/edit` render the same editor, so the extra
                    // segment only made the back arrow pop to an identical-
                    // looking page first, needing a second click (#7147).
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(L10n.of(context).editProfile),
                      tileColor: activeRoute.startsWith('/profile')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'profile',
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.language_outlined),
                      title: Text(L10n.of(context).learningSettings),
                      tileColor: activeRoute.startsWith('/settings/learning')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'learning',
                        ),
                      ),
                    ),
                    // Pangea#
                    ListTile(
                      leading: const Icon(Icons.format_paint_outlined),
                      title: Text(L10n.of(context).changeTheme),
                      tileColor: activeRoute.startsWith('/settings/style')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'style',
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text(L10n.of(context).notifications),
                      tileColor:
                          activeRoute.startsWith('/settings/notifications')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'notifications',
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.devices_outlined),
                      title: Text(L10n.of(context).devices),
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'devices',
                        ),
                      ),
                      tileColor: activeRoute.startsWith('/settings/devices')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                    ),
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(L10n.of(context).chat),
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'chat',
                        ),
                      ),
                      tileColor: activeRoute.startsWith('/settings/chat')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                    ),
                    // #Pangea
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(L10n.of(context).subscriptionManagement),
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'subscription',
                        ),
                      ),
                      tileColor:
                          activeRoute.startsWith('/settings/subscription')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                    ),
                    // Pangea#
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(L10n.of(context).security),
                      onTap: () => context.go(
                        WorkspaceNav.openSettings(
                          GoRouterState.of(context).uri,
                          page: 'security',
                        ),
                      ),
                      tileColor: activeRoute.startsWith('/settings/security')
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                    ),
                    Divider(color: theme.dividerColor),
                    // #Pangea
                    SupportChatListTile(),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: Text(L10n.of(context).termsAndConditions),
                      onTap: () => launchUrlString(AppConfig.termsOfServiceUrl),
                      trailing: const Icon(Icons.open_in_new_outlined),
                    ),
                    if (MatrixState
                        .pangeaController
                        .userController
                        .showDeveloperOptions)
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            return ListTile(
                              leading: const Icon(Icons.info_outline),
                              trailing: const Icon(Icons.copy_outlined),
                              onTap: () async {
                                if (snapshot.data == null) return;
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        "${snapshot.data!.version}+${snapshot.data!.buildNumber}",
                                  ),
                                );
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBarAnnounced(
                                  SnackBar(
                                    content: Text(
                                      L10n.of(context).copiedToClipboard,
                                    ),
                                  ),
                                );
                              },
                              title: Text(
                                snapshot.data != null
                                    ? L10n.of(context).versionText(
                                        snapshot.data!.version,
                                        snapshot.data!.buildNumber,
                                      )
                                    : L10n.of(context).versionNotFound,
                              ),
                            );
                          } else if (snapshot.hasError) {
                            return ListTile(
                              leading: const Icon(Icons.error_outline),
                              title: Text(L10n.of(context).versionFetchError),
                            );
                          } else {
                            return ListTile(
                              leading: const CircularProgressIndicator(),
                              title: Text(L10n.of(context).fetchingVersion),
                            );
                          }
                        },
                      ),
                    // Conditional ListTile based on the environment (staging or not)
                    if (Environment.isStagingEnvironment &&
                        MatrixState
                            .pangeaController
                            .userController
                            .showDeveloperOptions)
                      ListTile(
                        leading: const Icon(Icons.bug_report_outlined),
                        title: Text(L10n.of(context).connectedToStaging),
                      ),
                    // ListTile(
                    //   leading: const Icon(Icons.dns_outlined),
                    //   title: Text(
                    //     L10n.of(context).aboutHomeserver(
                    //       Matrix.of(context).client.userID?.domain ??
                    //           'homeserver',
                    //     ),
                    //   ),
                    //   onTap: () => context.go('/settings/homeserver'),
                    //   tileColor:
                    //       activeRoute.startsWith('/settings/homeserver')
                    //       ? theme.colorScheme.surfaceContainerHigh
                    //       : null,
                    // ),
                    // ListTile(
                    //   leading: const Icon(Icons.privacy_tip_outlined),
                    //   title: Text(L10n.of(context).privacy),
                    //   onTap: () => launchUrl(AppConfig.privacyUrl),
                    // ),
                    // ListTile(
                    //   leading: const Icon(Icons.info_outline_rounded),
                    //   title: Text(L10n.of(context).about),
                    //   onTap: () => PlatformInfos.showDialog(context),
                    // ),
                    // Pangea#
                    Divider(color: theme.dividerColor),
                    ListTile(
                      leading: const Icon(Icons.logout_outlined),
                      title: Text(L10n.of(context).logout),
                      onTap: controller.logoutAction,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
