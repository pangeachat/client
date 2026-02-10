import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: controller.showEmojiPicker
          ? DefaultTabController(
              // #Pangea
              // length: 2,
              length: 1,
              // Pangea#
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      // #Pangea
                      // Tab(text: L10n.of(context).stickers),
                      // Pangea#
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor:
                                  theme.colorScheme.onInverseSurface,
                            ),
                            bottomActionBarConfig: BottomActionBarConfig(
                              // #Pangea
                              // enabled: false,
                              showBackspaceButton: false,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              buttonColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              buttonIconColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              // Pangea#
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                            // #Pangea
                            viewOrderConfig: const ViewOrderConfig(
                              middle: EmojiPickerItem.searchBar,
                              top: EmojiPickerItem.categoryBar,
                              bottom: EmojiPickerItem.emojiView,
                            ),
                            searchViewConfig: SearchViewConfig(
                              backgroundColor: theme.colorScheme.surface,
                              buttonIconColor: theme.colorScheme.onSurface,
                            ),
                            // Pangea#
                          ),
                        ),
                        // #Pangea
                        // StickerPickerDialog(
                        //   room: controller.room,
                        //   onSelected: (sticker) {
                        //     controller.room.sendEvent(
                        //       {
                        //         'body': sticker.body,
                        //         'info': sticker.info ?? {},
                        //         'url': sticker.url.toString(),
                        //       },
                        //       type: EventTypes.Sticker,
                        //       threadRootEventId: controller.activeThreadId,
                        //       threadLastEventId: controller.threadLastEventId,
                        //     );
                        //     controller.hideEmojiPicker();
                        //   },
                        // ),
                        // Pangea#
                      ],
                    ),
                  ),
                  // #Pangea
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: FloatingActionButton(
                      onPressed: controller.hideEmojiPicker,
                      shape: const CircleBorder(),
                      mini: true,
                      child: const Icon(Icons.close),
                    ),
                  ),
                  // Pangea#
                ],
              ),
            )
          : null,
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
