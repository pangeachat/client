import 'dart:async';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/pangea/utils/logout.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;

  void updateProfile() => setState(() {
        profileUpdated = true;
        profileFuture = null;
      });

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context)!.editDisplayname,
      okLabel: L10n.of(context)!.ok,
      cancelLabel: L10n.of(context)!.cancel,
      textFields: [
        DialogTextField(
          // #Pangea
          maxLength: 32,
          // Pangea#
          initialText: profile?.displayName ??
              Matrix.of(context).client.userID!.localpart,
        ),
      ],
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () =>
          matrix.client.setDisplayName(matrix.client.userID!, input.single),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void logoutAction() async {
    final noBackup = showChatBackupBanner == true;
    // #Pangea
    pLogoutAction(context, isDestructiveAction: noBackup);
    // if (await showOkCancelAlertDialog(
    //       useRootNavigator: false,
    //       context: context,
    //       title: L10n.of(context)!.areYouSureYouWantToLogout,
    //       message: L10n.of(context)!.noBackupWarning,
    //       isDestructiveAction: noBackup,
    //       okLabel: L10n.of(context)!.logout,
    //       cancelLabel: L10n.of(context)!.cancel,
    //     ) ==
    //     OkCancelResult.cancel) {
    //   return;
    // }
    // final matrix = Matrix.of(context);
    // await showFutureLoadingDialog(
    //   context: context,
    //   future: () => matrix.client.logout(),
    // );
    // Pangea#
  }

  void setAvatarAction() async {
    final profile = await profileFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        SheetAction(
          key: AvatarAction.camera,
          label: L10n.of(context)!.openCamera,
          isDefaultAction: true,
          icon: Icons.camera_alt_outlined,
        ),
      SheetAction(
        key: AvatarAction.file,
        label: L10n.of(context)!.openGallery,
        icon: Icons.photo_outlined,
      ),
      if (profile?.avatarUrl != null)
        SheetAction(
          key: AvatarAction.remove,
          label: L10n.of(context)!.removeYourAvatar,
          isDestructiveAction: true,
          icon: Icons.delete_outlined,
        ),
    ];
    final action = actions.length == 1
        ? actions.single.key
        : await showModalActionSheet<AvatarAction>(
            context: context,
            title: L10n.of(context)!.changeYourAvatar,
            actions: actions,
          );
    if (action == null) return;
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
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
      file = MatrixFile(
        bytes: await result.readAsBytes(),
        name: result.path,
      );
    } else {
      final result = await AppLock.of(context).pauseWhile(
        FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        ),
      );
      final pickedFile = result?.files.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: pickedFile.bytes!,
        name: pickedFile.name,
      );
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  @override
  void initState() {
    // #Pangea
    // WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());
    // Pangea#

    super.initState();
    // #Pangea
    profileUpdated = true;
    profileFuture = null;
    // Pangea#
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    final crossSigning =
        await client.encryption?.crossSigning.isCached() ?? false;
    final needsBootstrap =
        await client.encryption?.keyManager.isCached() == false ||
            client.encryption?.crossSigning.enabled == false ||
            crossSigning == false;
    final isUnknownSession = client.isUnknownSession;
    setState(() {
      showChatBackupBanner = needsBootstrap || isUnknownSession;
    });
  }

  bool? crossSigningCached;
  bool? showChatBackupBanner;

  void firstRunBootstrapAction([_]) async {
    // #Pangea
    // if (showChatBackupBanner != true) {
    //   showOkAlertDialog(
    //     context: context,
    //     title: L10n.of(context)!.chatBackup,
    //     message: L10n.of(context)!.onlineKeyBackupEnabled,
    //     okLabel: L10n.of(context)!.close,
    //   );
    //   return;
    // }
    // await BootstrapDialog(
    //   client: Matrix.of(context).client,
    // ).show(context);
    // checkBootstrap();
    // Pangea#
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(
      client.userID!,
    );
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }
