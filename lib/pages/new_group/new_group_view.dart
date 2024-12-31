import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/new_group/new_group.dart';
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
        title: Text(
          controller.createGroupType == CreateGroupType.space
              ? L10n.of(context).newSpace
              // #Pangea
              // : L10n.of(context).createGroup,
              : L10n.of(context).newChat,
          // Pangea#
        ),
      ),
      body: MaxWidthBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SegmentedButton<CreateGroupType>(
                selected: {controller.createGroupType},
                onSelectionChanged: controller.setCreateGroupType,
                segments: [
                  ButtonSegment(
                    value: CreateGroupType.group,
                    label: Text(L10n.of(context).group),
                  ),
                  ButtonSegment(
                    value: CreateGroupType.space,
                    label: Text(L10n.of(context).space),
                  ),
                ],
              ),
            ),
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
                          width: Avatar.defaultSize * 2,
                          height: Avatar.defaultSize * 2,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                autofocus: true,
                controller: controller.nameController,
                autocorrect: false,
                readOnly: controller.loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.people_outlined),
                  labelText: controller.createGroupType == CreateGroupType.space
                      ? L10n.of(context).spaceName
                      // #Pangea
                      // : L10n.of(context).groupName,
                      : L10n.of(context).chatName,
                  // Pangea#
                ),
                // #Pangea
                onSubmitted: (value) {
                  controller.loading ? null : controller.submitAction();
                },
                // Pangea#
              ),
            ),
            const SizedBox(height: 16),
            // #Pangea
            if (controller.createGroupType == CreateGroupType.space)
              // Pangea#
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                secondary: const Icon(Icons.public_outlined),
                // #Pangea
                // title: Text(
                //   controller.createGroupType == CreateGroupType.space
                //       ? L10n.of(context).spaceIsPublic
                //       : L10n.of(context).groupIsPublic,
                // ),
                title: Text(L10n.of(context).requireCodeToJoin),
                // value: controller.publicGroup,
                // onChanged:
                //     controller.loading ? null : controller.setPublicGroup,
                value: controller.requiredCodeToJoin,
                onChanged: controller.setRequireCode,
                // Pangea#
              ),
            // #Pangea
            if (controller.createGroupType == CreateGroupType.space)
              // Pangea#
              AnimatedSize(
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                child:
                    // #Pangea
                    // controller.publicGroup ?
                    // Pangea#
                    SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                  secondary: const Icon(Icons.search_outlined),
                  // #Pangea
                  // title: Text(L10n.of(context).groupCanBeFoundViaSearch),
                  title: Text(L10n.of(context).canFindInSearch),
                  // Pangea#
                  value: controller.groupCanBeFound,
                  onChanged:
                      controller.loading ? null : controller.setGroupCanBeFound,
                ),
                // #Pangea
                // : const SizedBox.shrink(),
                // Pangea#
              ),
            // AnimatedSize(
            //   duration: FluffyThemes.animationDuration,
            //   curve: FluffyThemes.animationCurve,
            //   child: controller.createGroupType == CreateGroupType.space
            //       ? const SizedBox.shrink()
            //       : SwitchListTile.adaptive(
            //           contentPadding:
            //               const EdgeInsets.symmetric(horizontal: 32),
            //           secondary: Icon(
            //             Icons.lock_outlined,
            //             color: theme.colorScheme.onSurface,
            //           ),
            //           title: Text(
            //             L10n.of(context).enableEncryption,
            //             style: TextStyle(
            //               color: theme.colorScheme.onSurface,
            //             ),
            //           ),
            //           value: !controller.publicGroup,
            //           onChanged: null,
            //         ),
            // ),
            // Pangea#
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              child: controller.createGroupType == CreateGroupType.space
                  ? ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 32),
                      trailing: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Icon(Icons.info_outlined),
                      ),
                      // #Pangea
                      // subtitle: Text(L10n.of(context).newSpaceDescription),
                      subtitle:
                          Text(L10n.of(context).updatedNewSpaceDescription),
                      // Pangea#
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      controller.loading ? null : controller.submitAction,
                  child: controller.loading
                      ? const LinearProgressIndicator()
                      : Text(
                          controller.createGroupType == CreateGroupType.space
                              ? L10n.of(context).createNewSpace
                              // #Pangea
                              // : L10n.of(context).createGroupAndInviteUsers,
                              : L10n.of(context).createChatAndInviteUsers,
                          // Pangea#
                        ),
                ),
              ),
            ),
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
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
