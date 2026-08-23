import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:dynamic_color/dynamic_color.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/style_example_message.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'color_theme_picker.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    return Semantics(
      label: L10n.of(context).bodyLabel(L10n.of(context).changeTheme),
      container: true,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: MaxWidthBody(
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              // #Pangea
              LayoutBuilder(
                builder: (context, constraints) => Center(
                  child:
                      // Pangea#
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SegmentedButton<ThemeMode>(
                          // #Pangea
                          direction: constraints.maxWidth < 350
                              ? Axis.vertical
                              : Axis.horizontal,
                          style: SegmentedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          // Pangea#
                          selected: {controller.currentTheme},
                          onSelectionChanged: (selected) =>
                              controller.switchTheme(selected.single),
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text(L10n.of(context).lightTheme),
                              icon: const Icon(Icons.light_mode_outlined),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text(L10n.of(context).darkTheme),
                              icon: const Icon(Icons.dark_mode_outlined),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text(L10n.of(context).systemTheme),
                              icon: const Icon(Icons.auto_mode_outlined),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).setColorTheme,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // #Pangea
              // The swatch grid lives in its own widget so it can be exercised
              // directly in tests; see color_theme_picker.dart.
              DynamicColorBuilder(
                builder: (light, dark) => ColorThemePicker(
                  systemColor: Theme.of(context).brightness == Brightness.light
                      ? light?.primary
                      : dark?.primary,
                  currentColor: controller.currentColor,
                  onColorSelected: controller.setChatColor,
                ),
              ),
              // Pangea#
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  L10n.of(context).messagesStyle,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              StreamBuilder(
                stream: client.onSync.stream.where(
                  (syncUpdate) =>
                      syncUpdate.accountData?.any(
                        (accountData) =>
                            accountData.type ==
                            ApplicationAccountConfigExtension.accountDataKey,
                      ) ??
                      false,
                ),
                builder: (context, snapshot) {
                  final accountConfig = client.applicationAccountConfig;

                  return Column(
                    mainAxisSize: .min,
                    children: [
                      Semantics(
                        label: L10n.of(context).chatAppearanceStyleLabel,
                        container: true,
                        child: AnimatedContainer(
                          duration: FluffyThemes.animationDuration,
                          curve: FluffyThemes.animationCurve,
                          decoration: const BoxDecoration(),
                          // #Pangea
                          // clipBehavior: Clip.hardEdge,
                          // Pangea#
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (accountConfig.wallpaperUrl != null)
                                Opacity(
                                  opacity: controller.wallpaperOpacity,
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: controller.wallpaperBlur,
                                      sigmaY: controller.wallpaperBlur,
                                    ),
                                    child: MxcImage(
                                      key: ValueKey(accountConfig.wallpaperUrl),
                                      uri: accountConfig.wallpaperUrl,
                                      fit: BoxFit.cover,
                                      isThumbnail: true,
                                      width: FluffyThemes.columnWidth * 2,
                                      // #Pangea
                                      // height: 212,
                                      height: 375,
                                      // Pangea#
                                    ),
                                  ),
                                ),
                              // #Pangea
                              // Decorative style preview; its toolbar buttons are
                              // disabled demos, so keep the whole preview out of the
                              // semantics tree (axe `aria-command-name` otherwise).
                              ExcludeSemantics(child: StyleExampleMessage()),
                              // Column(
                              //   mainAxisSize: .min,
                              //   children: [
                              //     const SizedBox(height: 16),
                              //     StateMessage(
                              //       Event(
                              //         eventId: 'style_dummy',
                              //         room: Room(
                              //           id: '!style_dummy',
                              //           client: client,
                              //         ),
                              //         content: {'membership': 'join'},
                              //         type: EventTypes.RoomMember,
                              //         senderId: client.userID!,
                              //         originServerTs: DateTime.now(),
                              //         stateKey: client.userID!,
                              //       ),
                              //     ),
                              //     Padding(
                              //       padding: EdgeInsets.only(
                              //         left: 12 + 12 + Avatar.defaultSize,
                              //         right: 12,
                              //         top: accountConfig.wallpaperUrl == null
                              //             ? 0
                              //             : 12,
                              //         bottom: 12,
                              //       ),
                              //       child: DecoratedBox(
                              //         decoration: BoxDecoration(
                              //           color: theme.bubbleColor,
                              //           borderRadius: BorderRadius.circular(
                              //             AppConfig.borderRadius,
                              //           ),
                              //         ),
                              //         child: Padding(
                              //           padding: const EdgeInsets.symmetric(
                              //             horizontal: 16,
                              //             vertical: 8,
                              //           ),
                              //           child: Text(
                              //             'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                              //             style: TextStyle(
                              //               color: theme.onBubbleColor,
                              //               fontSize:
                              //                   AppConfig.messageFontSize *
                              //                   AppSettings.fontSizeFactor.value,
                              //             ),
                              //           ),
                              //         ),
                              //       ),
                              //     ),
                              //     Align(
                              //       alignment: Alignment.centerLeft,
                              //       child: Padding(
                              //         padding: EdgeInsets.only(
                              //           right: 12,
                              //           left: 12,
                              //           top: accountConfig.wallpaperUrl == null
                              //               ? 0
                              //               : 12,
                              //           bottom: 12,
                              //         ),
                              //         child: Material(
                              //           color:
                              //               theme.colorScheme.surfaceContainerHigh,
                              //           borderRadius: BorderRadius.circular(
                              //             AppConfig.borderRadius,
                              //           ),
                              //           child: Padding(
                              //             padding: const EdgeInsets.symmetric(
                              //               horizontal: 16,
                              //               vertical: 8,
                              //             ),
                              //             child: Text(
                              //               'Lorem ipsum dolor sit amet',
                              //               style: TextStyle(
                              //                 color: theme.colorScheme.onSurface,
                              //                 fontSize:
                              //                     AppConfig.messageFontSize *
                              //                     AppSettings.fontSizeFactor.value,
                              //               ),
                              //             ),
                              //           ),
                              //         ),
                              //       ),
                              //     ),
                              //   ],
                              // ),
                              // Pangea#
                            ],
                          ),
                        ),
                      ),

                      Divider(color: theme.dividerColor),
                      ListTile(
                        title: TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                            foregroundColor:
                                theme.colorScheme.onSecondaryContainer,
                          ),
                          onPressed: controller.setWallpaper,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(L10n.of(context).setWallpaper),
                        ),
                        trailing: accountConfig.wallpaperUrl == null
                            ? null
                            : IconButton(
                                tooltip: L10n.of(context).delete,
                                icon: const Icon(Icons.delete_outlined),
                                color: theme.colorScheme.error,
                                onPressed: controller.deleteChatWallpaper,
                              ),
                      ),
                      if (accountConfig.wallpaperUrl != null) ...[
                        ListTile(title: Text(L10n.of(context).opacity)),
                        Slider(
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          value: controller.wallpaperOpacity,
                          onChanged: controller.updateWallpaperOpacity,
                          onChangeEnd: controller.saveWallpaperOpacity,
                        ),
                        ListTile(title: Text(L10n.of(context).blur)),
                        Slider(
                          min: 0.0,
                          max: 10.0,
                          divisions: 10,
                          value: controller.wallpaperBlur,
                          onChanged: controller.updateWallpaperBlur,
                          onChangeEnd: controller.saveWallpaperBlur,
                        ),
                      ],
                    ],
                  );
                },
              ),
              // #Pangea
              // The app-level font-size slider is gone; text size comes from
              // the device's own setting now (issue #7719).
              // Pangea#
              // #Pangea
              // Divider(color: theme.dividerColor),
              // ListTile(
              //   title: Text(
              //     L10n.of(context).overview,
              //     style: TextStyle(
              //       color: theme.colorScheme.secondary,
              //       fontWeight: FontWeight.bold,
              //     ),
              //   ),
              // ),
              // SettingsSwitchListTile.adaptive(
              //   title: L10n.of(context).presencesToggle,
              //   setting: AppSettings.showPresences,
              // ),
              // SettingsSwitchListTile.adaptive(
              //   title: L10n.of(context).separateChatTypes,
              //   setting: AppSettings.separateChatTypes,
              // ),
              // SettingsSwitchListTile.adaptive(
              //   title: L10n.of(context).displayNavigationRail,
              //   setting: AppSettings.displayNavigationRail,
              // ),
              // Pangea#
            ],
          ),
        ),
      ),
    );
  }
}
