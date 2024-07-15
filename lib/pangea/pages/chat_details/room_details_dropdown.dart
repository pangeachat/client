import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/pages/class_settings/p_class_widgets/class_details_toggle_add_students_tile.dart';
import 'package:fluffychat/pangea/pages/class_settings/p_class_widgets/class_invitation_buttons.dart';
import 'package:fluffychat/pangea/pages/class_settings/p_class_widgets/room_capacity_button.dart';
import 'package:fluffychat/pangea/utils/lock_room.dart';
import 'package:fluffychat/pangea/widgets/class/add_space_toggles.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class RoomDetailsDropdown extends StatefulWidget {
  final ChatDetailsController controller;
  const RoomDetailsDropdown({super.key, required this.controller});

  @override
  RoomDetailsDropdownState createState() => RoomDetailsDropdownState();
}

class RoomDetailsDropdownState extends State<RoomDetailsDropdown> {
  bool isOpen = false;
  Color? get iconColor => Theme.of(context).textTheme.bodyLarge!.color;
  Room? get room => widget.controller.room;

  @override
  Widget build(BuildContext context) {
    if (room == null) return const SizedBox();
    return Column(
      children: [
        ListTile(
          title: Text(
            room!.isSpace
                ? L10n.of(context)!.spaceDetails
                : L10n.of(context)!.roomDetails,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: iconColor,
            child: const Icon(Icons.settings_outlined),
          ),
          trailing: Icon(
            isOpen
                ? Icons.keyboard_arrow_down_outlined
                : Icons.keyboard_arrow_right_outlined,
          ),
          onTap: () {
            setState(() => isOpen = !isOpen);
          },
        ),
        // Divider(
        //   height: 1,
        //   color: Theme.of(context).dividerColor,
        // ),
        if (isOpen) ...[
          if (room!.isSpace && room!.isRoomAdmin)
            SpaceDetailsToggleAddStudentsTile(controller: widget.controller),
          if (room!.isSpace &&
              room!.isRoomAdmin &&
              widget.controller.displayAddStudentOptions)
            ClassInvitationButtons(roomId: room!.id),
          if (room!.isSpace &&
              room!.isRoomAdmin &&
              widget.controller.displayAddStudentOptions)
            Divider(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
          // if (room!.pangeaRoomRules != null)
          //   RoomRulesEditor(
          //     roomId: room!.id,
          //     startOpen: false,
          //   ),
          if (!room!.isDirectChat && !room!.isSpace && room!.isRoomAdmin)
            ListTile(
              title: Text(
                L10n.of(context)!.editChatPermissions,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                L10n.of(context)!.whoCanPerformWhichAction,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                foregroundColor: iconColor,
                child: const Icon(
                  Icons.edit_attributes_outlined,
                ),
              ),
              onTap: () => context.push(
                '/rooms/${room!.id}/details/permissions',
              ),
            ),
          RoomCapacityListTile(
            room: room!,
            controller: widget.controller,
          ),
          if (!room!.isDirectChat && room!.isRoomAdmin)
            AddToSpaceToggles(
              roomId: room!.id,
              startOpen: false,
            ),
          if (!room!.isDirectChat && room!.isRoomAdmin)
            ListTile(
              title: Text(
                room!.isSpace
                    ? L10n.of(context)!.archiveSpace
                    : L10n.of(context)!.archive,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                foregroundColor: iconColor,
                child: const Icon(
                  Icons.archive_outlined,
                ),
              ),
              onTap: () async {
                OkCancelResult confirmed = OkCancelResult.ok;
                bool shouldGo = false;
                // archiveSpace has its own popup; only show if not space
                if (!room!.isSpace) {
                  confirmed = await showOkCancelAlertDialog(
                    useRootNavigator: false,
                    context: context,
                    title: L10n.of(context)!.areYouSure,
                    okLabel: L10n.of(context)!.ok,
                    cancelLabel: L10n.of(context)!.cancel,
                    message: L10n.of(context)!.archiveRoomDescription,
                  );
                }
                if (confirmed == OkCancelResult.ok) {
                  if (room!.isSpace) {
                    shouldGo = await room!.archiveSpace(
                      context,
                      Matrix.of(context).client,
                    );
                  } else {
                    final success = await showFutureLoadingDialog(
                      context: context,
                      future: () async {
                        await room!.archive();
                      },
                    );
                    shouldGo = (success.error == null);
                  }
                  if (shouldGo) {
                    context.go('/rooms');
                  }
                }
              },
            ),
          ListTile(
            title: Text(
              L10n.of(context)!.leave,
              style: TextStyle(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              foregroundColor: iconColor,
              child: const Icon(
                Icons.arrow_forward,
              ),
            ),
            onTap: () async {
              OkCancelResult confirmed = OkCancelResult.ok;
              bool shouldGo = false;
              // If user is only admin, room will be archived
              final bool onlyAdmin = await room!.isOnlyAdmin();
              // archiveSpace has its own popup; only show if not space
              if (!room!.isSpace) {
                confirmed = await showOkCancelAlertDialog(
                  useRootNavigator: false,
                  context: context,
                  title: L10n.of(context)!.areYouSure,
                  okLabel: L10n.of(context)!.ok,
                  cancelLabel: L10n.of(context)!.cancel,
                  message: onlyAdmin
                      ? L10n.of(context)!.onlyAdminDescription
                      : L10n.of(context)!.leaveRoomDescription,
                );
              }
              if (confirmed == OkCancelResult.ok) {
                if (room!.isSpace) {
                  shouldGo = onlyAdmin
                      ? await room!.archiveSpace(
                          context,
                          Matrix.of(context).client,
                          onlyAdmin: true,
                        )
                      : await room!.leaveSpace(
                          context,
                          Matrix.of(context).client,
                        );
                } else {
                  final success = await showFutureLoadingDialog(
                    context: context,
                    future: () async {
                      onlyAdmin ? await room!.archive() : await room!.leave();
                    },
                  );
                  shouldGo = (success.error == null);
                }
                if (shouldGo) {
                  context.go('/rooms');
                }
              }
            },
          ),
          if (room!.isRoomAdmin && !room!.isDirectChat)
            SwitchListTile.adaptive(
              activeColor: AppConfig.activeToggleColor,
              title: Text(
                room!.isSpace
                    ? L10n.of(context)!.lockSpace
                    : L10n.of(context)!.lockChat,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              secondary: CircleAvatar(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                foregroundColor: iconColor,
                child: Icon(
                  room!.isLocked
                      ? Icons.lock_outlined
                      : Icons.no_encryption_outlined,
                ),
              ),
              value: room!.isLocked,
              onChanged: (value) => showFutureLoadingDialog(
                context: context,
                future: () => value
                    ? lockRoom(
                        room!,
                        Matrix.of(context).client,
                      )
                    : unlockRoom(
                        room!,
                        Matrix.of(context).client,
                      ),
              ),
            ),
        ],
      ],
    );
  }
}
