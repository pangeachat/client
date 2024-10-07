import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/new_group/new_group.dart';
import 'package:fluffychat/pangea/pages/class_settings/p_class_widgets/room_capacity_button.dart';
import 'package:fluffychat/pangea/widgets/class/add_space_toggles.dart';
import 'package:fluffychat/pangea/widgets/conversation_bot/conversation_bot_settings.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class NewGroupView extends StatelessWidget {
  final NewGroupController controller;

  const NewGroupView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final avatar = controller.avatar;
    final error = controller.error;
    return Scaffold(
      appBar: AppBar(
        leading: Center(
          child: BackButton(
            onPressed: controller.loading ? null : Navigator.of(context).pop,
          ),
        ),
        // #Pangea
        // title: Text(L10n.of(context)!.createGroup),
        title: Text(L10n.of(context)!.createChat),
        // Pangea#
      ),
      // #Pangea
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.loading ? null : controller.submitAction,
        icon: controller.loading ? null : const Icon(Icons.chat_bubble_outline),
        label: controller.loading
            ? const CircularProgressIndicator.adaptive()
            : Text(L10n.of(context)!.createChat),
      ),
      // Pangea#
      body: MaxWidthBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(90),
              onTap: controller.loading ? null : controller.selectPhoto,
              child: CircleAvatar(
                radius: Avatar.defaultSize,
                child: avatar == null
                    ? const Icon(Icons.add_a_photo_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(90),
                        child: Image.memory(
                          avatar,
                          width: Avatar.defaultSize,
                          height: Avatar.defaultSize,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                // #Pangea
                maxLength: 64,
                // Pangea#
                autofocus: true,
                controller: controller.nameController,
                autocorrect: false,
                readOnly: controller.loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.people_outlined),
                  // #Pangea
                  // labelText: L10n.of(context)!.groupName,
                  labelText: L10n.of(context)!.chatName,
                  // Pangea#
                ),
              ),
            ),
            const SizedBox(height: 16),
            // #Pangea
            RoomCapacityButton(
              key: controller.addCapacityKey,
            ),
            ConversationBotSettings(
              key: controller.addConversationBotKey,
              activeSpaceId: controller.activeSpaceId,
            ),
            const Divider(height: 1),
            AddToSpaceToggles(
              key: controller.addToSpaceKey,
              startOpen: true,
              activeSpaceId: controller.activeSpaceId,
            ),
            // SwitchListTile.adaptive(
            //   secondary: const Icon(Icons.public_outlined),
            //   title: Text(L10n.of(context)!.groupIsPublic),
            //   value: controller.publicGroup,
            //   onChanged: controller.loading ? null : controller.setPublicGroup,
            // ),
            // AnimatedSize(
            //   duration: FluffyThemes.animationDuration,
            //   child: controller.publicGroup
            //       ? SwitchListTile.adaptive(
            //           secondary: const Icon(Icons.search_outlined),
            //           title: Text(L10n.of(context)!.groupCanBeFoundViaSearch),
            //           value: controller.groupCanBeFound,
            //           onChanged: controller.loading
            //               ? null
            //               : controller.setGroupCanBeFound,
            //         )
            //       : const SizedBox.shrink(),
            // ),
            // SwitchListTile.adaptive(
            //   secondary: Icon(
            //     Icons.lock_outlined,
            //     color: theme.colorScheme.onSurface,
            //   ),
            //   title: Text(
            //     L10n.of(context)!.enableEncryption,
            //     style: TextStyle(
            //       color: theme.colorScheme.onSurface,
            //     ),
            //   ),
            //   value: !controller.publicGroup,
            //   onChanged: null,
            // ),
            // Padding(
            //   padding: const EdgeInsets.all(16.0),
            //   child: SizedBox(
            //     width: double.infinity,
            //     child: ElevatedButton(
            //       onPressed:
            //           controller.loading ? null : controller.submitAction,
            //       child: controller.loading
            //           ? const LinearProgressIndicator()
            //           : Row(
            //               children: [
            //                 Expanded(
            //                   child: Text(
            //                     L10n.of(context)!.createGroupAndInviteUsers,
            //                   ),
            //                 ),
            //                 Icon(Icons.adaptive.arrow_forward_outlined),
            //               ],
            //             ),
            //     ),
            //   ),
            // ),
            // Pangea#
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              child: error == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: Icon(
                        Icons.warning_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        error.toLocalizedString(context),
                        style: TextStyle(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
