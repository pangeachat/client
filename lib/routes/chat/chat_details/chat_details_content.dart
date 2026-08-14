import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/instructions/instructions_enum.dart';
import 'package:fluffychat/features/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details_button_row.dart';
import 'package:fluffychat/routes/chat/chat_details/invite/pangea_invitation_selection.dart';
import 'package:fluffychat/routes/chat/chat_details/room_participants_widget.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/navigation_util.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

/// The chat (non-space) details page: the page chrome plus avatar, name, and
/// description editing, the action button row, and the participants list.
/// Spaces render the course page instead — see the shared `ChatDetails` entry.
class ChatDetailsContent extends StatelessWidget {
  final Room room;
  final Widget? embeddedCloseButton;

  const ChatDetailsContent({
    required this.room,
    this.embeddedCloseButton,
    super.key,
  });

  Future<void> _setDisplaynameAction(BuildContext context) async {
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).changeTheNameOfTheChat,
      maxLength: 64,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (success.error == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).displaynameHasBeenChanged)),
      );
    }
  }

  Future<void> _setTopicAction(BuildContext context) async {
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).setChatDescription,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
  }

  Future<void> _setAvatarAction(BuildContext context) async {
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (room.avatar != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).delete,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).editRoomAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null || !context.mounted) return;
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => room.setAvatar(null),
      );
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      final picked = await selectFiles(
        context,
        allowMultiple: false,
        type: FileType.image,
      );
      final pickedFile = picked.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    if (!context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room.setAvatar(file),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).pageLabel(L10n.of(context).chatDetails),
      container: true,
      child: Scaffold(
        appBar: AppBar(
          leading: embeddedCloseButton ?? const Center(child: BackButton()),
        ),
        body: Padding(
          padding: const EdgeInsetsGeometry.only(
            top: 16.0,
            left: 16.0,
            right: 16.0,
          ),
          child: MaxWidthBody(
            maxWidth: 900,
            showBorder: false,
            innerPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            withScrolling: true,
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: 2,
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) {
                  final theme = Theme.of(context);
                  final displayname = room.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(context)),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Stack(
                              children: [
                                Hero(
                                  tag: embeddedCloseButton != null
                                      ? 'embedded_content_banner'
                                      : 'content_banner',
                                  child: Avatar(
                                    mxContent: room.avatar,
                                    name: displayname,
                                    userId: room.directChatMatrixID,
                                    size: Avatar.defaultSize * 2.5,
                                  ),
                                ),
                                if (!room.isDirectChat &&
                                    room.canChangeStateEvent(
                                      EventTypes.RoomAvatar,
                                    ))
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: FloatingActionButton.small(
                                      onPressed: () =>
                                          _setAvatarAction(context),
                                      heroTag: null,
                                      tooltip: L10n.of(context).editRoomAvatar,
                                      child: const Icon(
                                        Icons.camera_alt_outlined,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextButton.icon(
                                  onPressed: room.isDirectChat
                                      ? null
                                      : () =>
                                            room.canChangeStateEvent(
                                              EventTypes.RoomName,
                                            )
                                            ? _setDisplaynameAction(context)
                                            : FluffyShare.share(
                                                displayname,
                                                context,
                                                copyOnly: true,
                                              ),
                                  icon: Icon(
                                    room.isDirectChat
                                        ? Icons.chat_bubble_outline
                                        : room.canChangeStateEvent(
                                            EventTypes.RoomName,
                                          )
                                        ? Icons.edit_outlined
                                        : Icons.copy_outlined,
                                    size: 16,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.onSurface,
                                    disabledForegroundColor:
                                        theme.colorScheme.onSurface,
                                  ),
                                  label: Text(
                                    room.isDirectChat
                                        ? L10n.of(context).directChat
                                        : displayname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed:
                                      room.isDirectChat || !room.canInvite
                                      ? null
                                      : () => NavigationUtil.goToSpaceRoute(
                                          room.id,
                                          ['details', 'invite'],
                                          context,
                                          filter: InvitationFilter.participants,
                                        ),
                                  icon: const Icon(
                                    Icons.group_outlined,
                                    size: 14,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.secondary,
                                    disabledForegroundColor:
                                        theme.colorScheme.onSurface,
                                  ),
                                  label: Text(
                                    L10n.of(context).countParticipants(
                                      (room.summary.mJoinedMemberCount ?? 0) +
                                          (room.summary.mInvitedMemberCount ??
                                              0),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Stack(
                        children: [
                          if (room.isRoomAdmin)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: IconButton(
                                tooltip: L10n.of(context).edit,
                                onPressed: () => _setTopicAction(context),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 32.0,
                              right: 32.0,
                              top: 16.0,
                              bottom: 16.0,
                            ),
                            child: SelectableLinkify(
                              text: room.topic.isEmpty
                                  ? L10n.of(context).noChatDescriptionYet
                                  : room.topic,
                              options: const LinkifyOptions(humanize: false),
                              linkStyle: const TextStyle(
                                color: Colors.blueAccent,
                                decorationColor: Colors.blueAccent,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: room.topic.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: theme.textTheme.bodyMedium!.color,
                                decorationColor:
                                    theme.textTheme.bodyMedium!.color,
                              ),
                              onOpen: (url) =>
                                  UrlLauncher(context, url.url).launchUrl(),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ChatDetailsButtonRow(room: room),
                      ),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const InstructionsInlineTooltip(
                        instructionsEnum:
                            InstructionsEnum.chatParticipantTooltip,
                        padding: EdgeInsets.only(bottom: 16.0),
                      ),
                      RoomParticipantsSection(room: room),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
