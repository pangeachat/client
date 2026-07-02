import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/settings/settings.dart';
import 'package:fluffychat/routes/settings/settings_learning/country_picker_tile.dart';
import 'package:fluffychat/routes/settings/settings_learning/gender_dropdown.dart';
import 'package:fluffychat/routes/settings/settings_learning/learning_settings_view_model.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  final TextEditingController _aboutTextController = TextEditingController();
  late final LearningSettingsViewModel _viewModel;

  Future<Profile>? _profileFuture;
  Future<Profile>? get _profileFutureGetter => _profileFuture ??= Matrix.of(
    context,
  ).client.getProfileFromUserId(Matrix.of(context).client.userID!);

  @override
  void initState() {
    super.initState();

    _viewModel = LearningSettingsViewModel(
      MatrixState.pangeaController.userController.profile,
      onUpdateProfile: _updateProfile,
    );

    _aboutTextController.text = _viewModel.about ?? '';
  }

  @override
  void dispose() {
    _aboutTextController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void updateProfileFuture() => setState(() => _profileFuture = null);

  void _setAvatarAction() async {
    final profile = await _profileFutureGetter;
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
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
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
        updateProfileFuture();
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
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }

    final resp = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final bytes = file.bytes;
        final mimeType = lookupMimeType(file.name, headerBytes: bytes);
        if (!AppConfig.allowedMimeTypes.contains(mimeType)) {
          throw L10n.of(context).invalidInput;
        }
      },
    );
    if (resp.isError) return;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfileFuture();
    }
  }

  void _setDisplaynameAction() async {
    final profile = await _profileFutureGetter;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
      maxLength: 50,
      maxLines: 1,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfileFuture();
    }
  }

  Future<void> _updateProfile() async {
    try {
      await MatrixState.pangeaController.userController
          .updateProfile(
            (_) => _viewModel.updatedProfile,
            waitForDataInSync: true,
          )
          .timeout(const Duration(seconds: 15));
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"updatedProfile": _viewModel.updatedProfile.toJson()},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBarAnnounced(
          SnackBar(
            content: Text(L10n.of(context).oopsSomethingWentWrong),
            showCloseIcon: true,
          ),
          assertive: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: MaxWidthBody(
        child: Column(
          spacing: 16.0,
          children: [
            FutureBuilder<Profile>(
              future: _profileFutureGetter,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final avatar = profile?.avatarUrl;
                final mxid =
                    Matrix.of(context).client.userID ?? L10n.of(context).user;
                final displayname =
                    profile?.displayName ?? mxid.localpart ?? mxid;
                return Padding(
                  padding: EdgeInsetsGeometry.all(16.0),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Avatar(
                            mxContent: avatar,
                            name: displayname,
                            userId: profile?.userId,
                            size: Avatar.defaultSize * 2.5,
                            onTap: avatar != null
                                ? () => showDialog(
                                    context: context,
                                    builder: (_) => MxcImageViewer(avatar),
                                  )
                                : null,
                          ),
                          if (profile != null)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: FloatingActionButton.small(
                                elevation: 2,
                                // Names the icon-only button for assistive tech
                                // (otherwise axe `aria-command-name`).
                                tooltip: L10n.of(context).changeYourAvatar,
                                onPressed: _setAvatarAction,
                                heroTag: null,
                                child: const Icon(Icons.camera_alt_outlined),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(width: 12.0),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: .center,
                          crossAxisAlignment: .start,
                          children: [
                            TextButton.icon(
                              onPressed: _setDisplaynameAction,
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                iconColor: theme.colorScheme.onSurface,
                              ),
                              label: Text(
                                displayname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => FluffyShare.share(mxid, context),
                              icon: const Icon(Icons.copy_outlined, size: 14),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.secondary,
                                iconColor: theme.colorScheme.secondary,
                              ),
                              label: Text(
                                mxid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Divider(color: theme.dividerColor, height: 1),
            ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 16.0,
                    ),
                    child: CountryPickerDropdown(
                      _viewModel.country,
                      _viewModel.setCountry,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 16.0,
                    ),
                    child: GenderDropdown(
                      initialGender: _viewModel.gender,
                      onChanged: _viewModel.setGender,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 16.0,
                    ),
                    child: TextField(
                      controller: _aboutTextController,
                      decoration: InputDecoration(
                        hintText: L10n.of(context).aboutMeHint,
                        labelText: L10n.of(context).aboutMeHint,
                      ),
                      onChanged: (val) => _viewModel.setAbout(val),
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 100,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    value: _viewModel.publicProfile,
                    onChanged: _viewModel.setPublicProfile,
                    title: Text(L10n.of(context).publicProfileTitle),
                    subtitle: Text(L10n.of(context).publicProfileDesc),
                    activeThumbColor: AppConfig.activeToggleColor,
                  ),
                  SwitchListTile.adaptive(
                    value: _viewModel.showDeveloperOptions,
                    title: Text(L10n.of(context).showDeveloperOptions),
                    subtitle: Text(L10n.of(context).showDeveloperOptionsDesc),
                    activeThumbColor: AppConfig.activeToggleColor,
                    onChanged: _viewModel.setShowDeveloperOptions,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
