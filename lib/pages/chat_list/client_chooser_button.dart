import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:fluffychat/pangea/constants/class_default_values.dart';
import 'package:fluffychat/pangea/extensions/client_extension/client_extension.dart';
import 'package:fluffychat/pangea/utils/class_code.dart';
import 'package:fluffychat/pangea/utils/find_conversation_partner_dialog.dart';
import 'package:fluffychat/pangea/utils/logout.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../utils/fluffy_share.dart';
import 'chat_list.dart';

class ClientChooserButton extends StatelessWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  List<PopupMenuEntry<Object>> _bundleMenuItems(BuildContext context) {
    final matrix = Matrix.of(context);
    // #Pangea
    // final bundles = matrix.accountBundles.keys.toList()
    //   ..sort(
    //     (a, b) => a!.isValidMatrixId == b!.isValidMatrixId
    //         ? 0
    //         : a.isValidMatrixId && !b.isValidMatrixId
    //             ? -1
    //             : 1,
    //   );
    // Pangea#
    return <PopupMenuEntry<Object>>[
      // #Pangea
      // PopupMenuItem(
      //   value: SettingsAction.newGroup,
      //   child: Row(
      //     children: [
      //       const Icon(Icons.group_add_outlined),
      //       const SizedBox(width: 18),
      //       Text(L10n.of(context)!.createGroup),
      //     ],
      //   ),
      // ),
      PopupMenuItem(
        value: SettingsAction.joinWithClassCode,
        child: Row(
          children: [
            const Icon(Icons.join_full_outlined),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.joinWithClassCode)),
          ],
        ),
      ),
      PopupMenuItem(
        enabled: matrix.client.rooms.any(
          (room) =>
              room.isSpace &&
              room.ownPowerLevel >= ClassDefaultValues.powerLevelOfAdmin,
        ),
        value: SettingsAction.classAnalytics,
        child: Row(
          children: [
            const Icon(Icons.analytics_outlined),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.classAnalytics)),
          ],
        ),
      ),
      PopupMenuItem(
        enabled: matrix.client.allMyAnalyticsRooms.isNotEmpty,
        value: SettingsAction.myAnalytics,
        child: Row(
          children: [
            const Icon(Icons.analytics_outlined),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.myLearning)),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.newClass,
        child: Row(
          children: [
            const Icon(Icons.school),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.createNewClass)),
          ],
        ),
      ),
      // PopupMenuItem(
      //   value: SettingsAction.newSpace,
      //   child: Row(
      //     children: [
      //       const Icon(Icons.workspaces_outlined),
      //       const SizedBox(width: 18),
      //       Text(L10n.of(context)!.createNewSpace),
      //     ],
      //   ),
      // ),
      PopupMenuItem(
        value: SettingsAction.newExchange,
        child: Row(
          children: [
            const Icon(Icons.connecting_airports),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.newExchange)),
          ],
        ),
      ),
      if (controller.pangeaController.permissionsController.isUser18())
        PopupMenuItem(
          value: SettingsAction.findAConversationPartner,
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline),
              const SizedBox(width: 18),
              Expanded(child: Text(L10n.of(context)!.findALanguagePartner)),
            ],
          ),
        ),
      // PopupMenuItem(
      //   value: SettingsAction.setStatus,
      //   child: Row(
      //     children: [
      //       const Icon(Icons.edit_outlined),
      //       const SizedBox(width: 18),
      //       Text(L10n.of(context)!.setStatus),
      //     ],
      //   ),
      // ),
      // PopupMenuItem(
      //   value: SettingsAction.invite,
      //   child: Row(
      //     children: [
      //       Icon(Icons.adaptive.share_outlined),
      //       const SizedBox(width: 18),
      //       Text(L10n.of(context)!.inviteContact),
      //     ],
      //   ),
      // ),
      // Pangea#
      PopupMenuItem(
        value: SettingsAction.archive,
        child: Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 18),
            // #Pangea
            // Text(L10n.of(context)!.archive),
            Expanded(child: Text(L10n.of(context)!.viewArchive)),
            // Pangea#
          ],
        ),
      ),
      // #Pangea
      PopupMenuItem(
        value: SettingsAction.learning,
        child: Row(
          children: [
            const Icon(Icons.psychology_outlined),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.learningSettings)),
          ],
        ),
      ),
      // Pangea#
      PopupMenuItem(
        value: SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            // #Pangea
            // Text(L10n.of(context)!.settings),
            Expanded(child: Text(L10n.of(context)!.settings)),
            // Pangea#
          ],
        ),
      ),
      // #Pangea
      // const PopupMenuDivider(),
      // for (final bundle in bundles) ...[
      //   if (matrix.accountBundles[bundle]!.length != 1 ||
      //       matrix.accountBundles[bundle]!.single!.userID != bundle)
      //     PopupMenuItem(
      //       value: null,
      //       child: Column(
      //         crossAxisAlignment: CrossAxisAlignment.start,
      //         mainAxisSize: MainAxisSize.min,
      //         children: [
      //           Text(
      //             bundle!,
      //             style: TextStyle(
      //               color: Theme.of(context).textTheme.titleMedium!.color,
      //               fontSize: 14,
      //             ),
      //           ),
      //           const Divider(height: 1),
      //         ],
      //       ),
      //     ),
      //   ...matrix.accountBundles[bundle]!.map(
      //     (client) => PopupMenuItem(
      //       value: client,
      //       child: FutureBuilder<Profile?>(
      //         // analyzer does not understand this type cast for error
      //         // handling
      //         //
      //         // ignore: unnecessary_cast
      //         future: (client!.fetchOwnProfile() as Future<Profile?>)
      //             .onError((e, s) => null),
      //         builder: (context, snapshot) => Row(
      //           children: [
      //             Avatar(
      //               mxContent: snapshot.data?.avatarUrl,
      //               name:
      //                   snapshot.data?.displayName ?? client.userID!.localpart,
      //               size: 32,
      //             ),
      //             const SizedBox(width: 12),
      //             Expanded(
      //               child: Text(
      //                 snapshot.data?.displayName ?? client.userID!.localpart!,
      //                 overflow: TextOverflow.ellipsis,
      //               ),
      //             ),
      //             const SizedBox(width: 12),
      //             IconButton(
      //               icon: const Icon(Icons.edit_outlined),
      //               onPressed: () => controller.editBundlesForAccount(
      //                 client.userID,
      //                 bundle,
      //               ),
      //             ),
      //           ],
      //         ),
      //       ),
      //     ),
      //   ),
      // ],
      // PopupMenuItem(
      //   value: SettingsAction.addAccount,
      //   child: Row(
      //     children: [
      //       const Icon(Icons.person_add_outlined),
      //       const SizedBox(width: 18),
      //       Text(L10n.of(context)!.addAccount),
      //     ],
      //   ),
      // ),
      PopupMenuItem(
        value: SettingsAction.logout,
        child: Row(
          children: [
            const Icon(Icons.logout_outlined),
            const SizedBox(width: 18),
            Expanded(child: Text(L10n.of(context)!.logout)),
          ],
        ),
      ),
      // Pangea#
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);

    int clientCount = 0;
    matrix.accountBundles.forEach((key, value) => clientCount += value.length);
    return FutureBuilder<Profile>(
      future: matrix.client.fetchOwnProfile(),
      builder: (context, snapshot) => Stack(
        alignment: Alignment.center,
        children: [
          // ...List.generate(
          //   clientCount,
          //   (index) => KeyBoardShortcuts(
          //     keysToPress: _buildKeyboardShortcut(index + 1),
          //     helpLabel: L10n.of(context)!.switchToAccount(index + 1),
          //     onKeysPressed: () => _handleKeyboardShortcut(
          //       matrix,
          //       index,
          //       context,
          //     ),
          //     child: const SizedBox.shrink(),
          //   ),
          // ),
          // KeyBoardShortcuts(
          //   keysToPress: {
          //     LogicalKeyboardKey.controlLeft,
          //     LogicalKeyboardKey.tab,
          //   },
          //   helpLabel: L10n.of(context)!.nextAccount,
          //   onKeysPressed: () => _nextAccount(matrix, context),
          //   child: const SizedBox.shrink(),
          // ),
          // KeyBoardShortcuts(
          //   keysToPress: {
          //     LogicalKeyboardKey.controlLeft,
          //     LogicalKeyboardKey.shiftLeft,
          //     LogicalKeyboardKey.tab,
          //   },
          //   helpLabel: L10n.of(context)!.previousAccount,
          //   onKeysPressed: () => _previousAccount(matrix, context),
          //   child: const SizedBox.shrink(),
          // ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child:
                  // Pangea#
                  PopupMenuButton<Object>(
                onSelected: (o) => _clientSelected(o, context),
                itemBuilder: _bundleMenuItems,
                // #Pangea
                child: ListTile(
                  mouseCursor: SystemMouseCursors.click,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(L10n.of(context)!.mainMenu),
                ),
              ),
            ),
            // child: Material(
            //   color: Colors.transparent,
            //   borderRadius: BorderRadius.circular(99),
            //   child: Avatar(
            //     mxContent: snapshot.data?.avatarUrl,
            //     name: snapshot.data?.displayName ??
            //         matrix.client.userID!.localpart,
            //     size: 32,
            //   ),
            // ),
            // Pangea#
          ),
        ],
      ),
    );
  }

  Set<LogicalKeyboardKey>? _buildKeyboardShortcut(int index) {
    if (index > 0 && index < 10) {
      return {
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey(0x00000000030 + index),
      };
    } else {
      return null;
    }
  }

  void _clientSelected(
    Object object,
    BuildContext context,
  ) async {
    if (object is Client) {
      controller.setActiveClient(object);
    } else if (object is String) {
      controller.setActiveBundle(object);
    } else if (object is SettingsAction) {
      switch (object) {
        case SettingsAction.addAccount:
          final consent = await showOkCancelAlertDialog(
            context: context,
            title: L10n.of(context)!.addAccount,
            message: L10n.of(context)!.enableMultiAccounts,
            okLabel: L10n.of(context)!.next,
            cancelLabel: L10n.of(context)!.cancel,
          );
          if (consent != OkCancelResult.ok) return;
          context.go('/rooms/settings/addaccount');
          break;
        case SettingsAction.newGroup:
          context.go('/rooms/newgroup');
          break;
        case SettingsAction.newSpace:
          controller.createNewSpace();
          break;
        case SettingsAction.invite:
          FluffyShare.shareInviteLink(context);
          break;
        case SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case SettingsAction.archive:
          context.go('/rooms/archive');
          break;
        case SettingsAction.setStatus:
          controller.setStatus();
        // #Pangea
        case SettingsAction.learning:
          context.go('/rooms/settings/learning');
          break;
        case SettingsAction.newClass:
          context.go('/rooms/newspace');
          break;
        case SettingsAction.newExchange:
          context.go('/rooms/newspace/exchange');
          break;
        case SettingsAction.joinWithClassCode:
          ClassCodeUtil.joinWithClassCodeDialog(
            context,
            controller.pangeaController,
          );
          break;
        case SettingsAction.findAConversationPartner:
          findConversationPartnerDialog(
            context,
            controller.pangeaController,
          );
          break;
        case SettingsAction.classAnalytics:
          context.go('/rooms/analytics');
          break;
        case SettingsAction.myAnalytics:
          context.go('/rooms/mylearning');
          break;
        case SettingsAction.logout:
          pLogoutAction(context);
          break;
        // Pangea#
      }
    }
  }

  void _handleKeyboardShortcut(
    MatrixState matrix,
    int index,
    BuildContext context,
  ) {
    final bundles = matrix.accountBundles.keys.toList()
      ..sort(
        (a, b) => a!.isValidMatrixId == b!.isValidMatrixId
            ? 0
            : a.isValidMatrixId && !b.isValidMatrixId
                ? -1
                : 1,
      );
    // beginning from end if negative
    if (index < 0) {
      int clientCount = 0;
      matrix.accountBundles
          .forEach((key, value) => clientCount += value.length);
      _handleKeyboardShortcut(matrix, clientCount, context);
    }
    for (final bundleName in bundles) {
      final bundle = matrix.accountBundles[bundleName];
      if (bundle != null) {
        if (index < bundle.length) {
          return _clientSelected(bundle[index]!, context);
        } else {
          index -= bundle.length;
        }
      }
    }
    // if index too high, restarting from 0
    _handleKeyboardShortcut(matrix, 0, context);
  }

  int? _shortcutIndexOfClient(MatrixState matrix, Client client) {
    int index = 0;

    final bundles = matrix.accountBundles.keys.toList()
      ..sort(
        (a, b) => a!.isValidMatrixId == b!.isValidMatrixId
            ? 0
            : a.isValidMatrixId && !b.isValidMatrixId
                ? -1
                : 1,
      );
    for (final bundleName in bundles) {
      final bundle = matrix.accountBundles[bundleName];
      if (bundle == null) return null;
      if (bundle.contains(client)) {
        return index + bundle.indexOf(client);
      } else {
        index += bundle.length;
      }
    }
    return null;
  }

  void _nextAccount(MatrixState matrix, BuildContext context) {
    final client = matrix.client;
    final lastIndex = _shortcutIndexOfClient(matrix, client);
    _handleKeyboardShortcut(matrix, lastIndex! + 1, context);
  }

  void _previousAccount(MatrixState matrix, BuildContext context) {
    final client = matrix.client;
    final lastIndex = _shortcutIndexOfClient(matrix, client);
    _handleKeyboardShortcut(matrix, lastIndex! - 1, context);
  }
}

enum SettingsAction {
  addAccount,
  newGroup,
  newSpace,
  setStatus,
  invite,
  settings,
  archive,
  // #Pangea
  learning,
  joinWithClassCode,
  classAnalytics,
  myAnalytics,
  findAConversationPartner,
  logout,
  newClass,
  newExchange
  // Pangea#
}
